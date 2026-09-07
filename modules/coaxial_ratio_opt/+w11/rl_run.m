function info = rl_run(plant, p, n)
%RL_RUN 强化学习v3: 仿真器预训练 + 在线微调(w11, sim-to-real, 纯因果)。
% 逐层对策移植自 3.4 rl_run(谷底奖励二阶+1%噪声 → 对偶成对探索+分航向桶基线+
% REINFORCE正确缩放; 真实交互贵 → 三段式 sim-to-real):
% Stage A 首飞全比域扫(150步)联合辨识控制器自己的世界模型 (f̂,θ̂);
% Stage B 在学到的模型仿真器里离线预训练策略(60000步, 零真实成本);
% Stage C 部署到真实对象, 用真实奖励在线微调(吸收模型误差与漂移)。
% 因果口径(红线1): f̂/θ̂ 来自自己的标定拟合; 在线更新只用真实测量+自身指令;
% p 为 ctrl_view 白名单。动作=桨比(表格型 actor: 每航向桶一个平均桨比 μ(桶))。
qs=w11.settled_q(plant,p,n);
nBin=24;
muB=1.0*ones(1,nBin);                 % 表格型actor初值: 等转速默认分配
% ============ Stage A: 首飞全比域双向扫标定(与sweepcal同) ============
nUp=ceil(0.6*p.swSteps);
rSw=[linspace(p.swLo,p.swHi,nUp), linspace(p.swHi,p.swLo,p.swSteps-nUp)];
calPsi=zeros(1,p.swSteps); calR=zeros(1,p.swSteps); calP=zeros(1,p.swSteps);
psiUnw=0; kStep=0; Pb=NaN;
while kStep<p.swSteps && plant.count()<n
    kStep=kStep+1;
    r=rSw(kStep);
    c0=plant.count();
    Pm=qs(r,'calib');
    if ~isfinite(Pm), kStep=kStep-1; break; end
    sUsed=plant.count()-c0;
    tStart=(plant.count()-sUsed)*p.tEval;
    for j=1:sUsed
        psiUnw=psiUnw+w11.mission_speed(p,tStart+(j-0.5)*p.tEval)/p.turnRadius*p.tEval;
    end
    calPsi(kStep)=psiUnw; calR(kStep)=r; calP(kStep)=Pm;
end
calibSteps=kStep;
[coefs,thHat,fitRms,rLo,rHi,rKept]=w11.fit_curve_interf(calPsi(1:calibSteps),...
    calR(1:calibSteps),calP(1:calibSteps),p);
rStar=w11.curve_argmin(coefs,rLo,rHi,p,rKept);
% ============ Stage B: 学到的模型仿真器里离线预训练(纯RL, 零真实成本) ============
nSim=60000;
bBase=nan(1,nBin);
sigma=p.rlSigma;
psiS=0;
for j=1:nSim
    ib=min(nBin,floor(mod(psiS,2*pi)/(2*pi/nBin))+1);
    sgn=(-1)^j;
    r=min(max(muB(ib)+sgn*sigma,p.lower+0.02),p.upper-0.02);
    % u 钳位到谷底邻域 r̂*±0.15(2026-09-08修复移植): 截断拟合的 f̂ 只在谷底邻域
    % 可信——预训练若探索到拟合区边缘, 虚假低谷会把策略引进错误盆地。
    thS=thHat(1)+thHat(2)*cos(psiS)+thHat(3)*sin(psiS);
    u=min(max(r-thS,0.76),1.24);
    u=min(max(u,rStar-0.15),rStar+0.15);
    x=(u-1.0)/0.25;
    Pm=coefs(1)+coefs(2)*x+coefs(3)*x.^2+coefs(4)*x.^3+coefs(5)*x.^4;
    r0=bBase(ib);
    if isnan(r0), bBase(ib)=Pm; r0=Pm; end
    rew=-(Pm-r0)/max(abs(r0),0.1);
    if isnan(bBase(ib)), bBase(ib)=Pm; else, bBase(ib)=0.9*bBase(ib)+0.1*Pm; end
    aDev=r-muB(ib);
    lrT=p.rlLr*max(0.03,1-j/nSim);
    dB=lrT*rew*aDev/(sigma^2);
    dB=min(max(dB,-0.005),0.005);
    muB(ib)=min(max(muB(ib)+dB,p.lower+0.02),p.upper-0.02);
    psiS=psiS+w11.mission_speed(p,j*p.tEval)/p.turnRadius*p.tEval;
end
% ============ Stage C: 部署+在线微调(真实奖励) ============
sigma=max(p.rlSigmaMin,0.5*p.rlSigma);
phHist=ones(1,n); phHist(1:min(calibSteps,n))=1;
rHat=nan(1,n); thEst=nan(3,n);
rHat(1:min(calibSteps,n))=rStar;
thEst(:,1:min(calibSteps,n))=repmat(thHat,1,min(calibSteps,n));
r=NaN;
while plant.count()<n
    kStep=kStep+1;
    ib=min(nBin,floor(mod(psiUnw,2*pi)/(2*pi/nBin))+1);
    sgn=(-1)^kStep;
    r=min(max(muB(ib)+sgn*sigma,p.lower+0.02),p.upper-0.02);
    c0=plant.count();
    Pm=qs(r,'rl');
    if ~isfinite(Pm), kStep=kStep-1; break; end
    sUsed=plant.count()-c0;
    tStart=(plant.count()-sUsed)*p.tEval;
    for j=1:sUsed
        psiUnw=psiUnw+w11.mission_speed(p,tStart+(j-0.5)*p.tEval)/p.turnRadius*p.tEval;
    end
    if isnan(Pb), Pb=Pm; else, Pb=0.98*Pb+0.02*Pm; end
    if isnan(bBase(ib)), bBase(ib)=Pm; else, bBase(ib)=0.9*bBase(ib)+0.1*Pm; end
    rew=-(Pm-bBase(ib))/max(Pb,0.1);
    aDev=r-muB(ib);
    dB=p.rlLr*rew*aDev/(sigma^2);
    dB=min(max(dB,-0.005),0.005);
    muB(ib)=min(max(muB(ib)+dB,p.lower+0.02),p.upper-0.02);
    sigma=max(p.rlSigmaMin,sigma*0.995);
    rHat(kStep)=rStar; thEst(:,kStep)=thHat; phHist(kStep)=3;
end
while plant.count()<n
    plant.q(r,'hold'); plant.amendEstimate(r);
end
info=struct('best',r,'bestP',NaN,'mode','rl','muB',muB,...
    'sigma',sigma,'coefs',coefs,'thFinal',thHat,...
    'rStar',rStar,'rLo',rLo,'rHi',rHi,'calibSteps',calibSteps,'fitRms',fitRms,...
    'rHat',rHat,'thEst',thEst,'phase',phHist);
end
