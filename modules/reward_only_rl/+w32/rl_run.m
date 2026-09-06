function info = rl_run(plant, p, n)
%RL_RUN 强化学习v3: 仿真器预训练 + 在线微调(任务3.2, sim-to-real, 纯因果, 曲线未知)。
% ── 难点逐层拆解(v0→v3迭代史, 全过程见README) ──
% 困难1 谷底奖励是二阶量(ΔP≈½f''·Δv²≈0.005) + 1%测量噪声 → 单步梯度信噪比~0.1
%   对策: 对偶成对探索(±σ交替, 配对奖励差是一阶干净信号) + 分航向桶基线(消风的
%   航向调制结构) + REINFORCE正确缩放(÷σ²)。
% 困难2 探索能耗 → σ退火+下限; 对偶对围绕策略均值对称, 平均能耗不受探索抬升。
% 困难3 Fourier参数互相干扰(单航向梯度要掰弯全部参数, 800步只学23%)
%   → 对策: 表格型actor——24个航向桶各自独立μ, 每桶独立REINFORCE。
% 困难4 变风非平稳 → 在线梯度天然重学; σ保持下限; 步长限幅。
% 困难5 真实交互样本太贵(纯在线RL需3000-5000步才收敛, 每步1s且有能耗代价)
%   → 对策(v3核心, sim-to-real): Stage A首飞全速域扫(150步)联合辨识出控制器
%     自己的世界模型(f̂,ŵ); Stage B在学到的模型仿真器里离线预训练策略(数千步
%     仿真瞬间完成、零能耗); Stage C部署到真实对象, 用真实奖励在线微调(吸收
%     模型误差与风漂移)。
% 因果口径(红线1): f̂/ŵ是控制器从自己采的功率学的(非对象真值); 在线更新只用
% 真实测量+自身指令(航向死推); p为ctrl_view白名单(无曲线/u*/风/噪声真值)。
qs=w32.settled_q(plant,p,n);
nBin=24;
muB=p.initialSpeed*ones(1,nBin);      % 表格型actor: 每航向桶的平均速度
% ============ Stage A: 首飞全速度域双向扫标定(与sweepcal同) ============
nUp=ceil(0.6*p.swSteps);
vSw=[linspace(p.swLo,p.swHi,nUp), linspace(p.swHi,p.swLo,p.swSteps-nUp)];
calPsi=zeros(1,p.swSteps); calV=zeros(1,p.swSteps); calP=zeros(1,p.swSteps);
psiUnw=0; kStep=0; Pb=NaN;
while kStep<p.swSteps && plant.count()<n
    kStep=kStep+1;
    v=vSw(kStep);
    c0=plant.count();
    Pm=qs(v,'calib');
    if ~isfinite(Pm), kStep=kStep-1; break; end
    sUsed=plant.count()-c0;
    for j=1:sUsed
        psiUnw=psiUnw+v/p.turnRadius*p.tEval;
    end
    calPsi(kStep)=psiUnw; calV(kStep)=v; calP(kStep)=Pm;
end
calibSteps=kStep;
[coefs,wHat,fitRms,uLo,uHi]=w32.fit_curve_wind(calPsi(1:calibSteps),...
    calV(1:calibSteps),calP(1:calibSteps),p);
uStar=w32.curve_argmin(coefs,uLo,uHi,p);
% ============ Stage B: 学到的模型仿真器里离线预训练(纯RL, 零真实成本) ============
% 仿真环境: u=|v·t̂−ŵ|, P=f̂(u)——即控制器的世界模型; REINFORCE与在线完全同构,
% 只是"真实测量"换成模型读数。数千仿真步瞬间完成。
nSim=60000;   % 仿真零成本: 充分预训练(纯在线要3-5千真实步, 这里瞬间完成)
bBase=nan(1,nBin);
sigma=p.rlSigma;
psiS=0;
for j=1:nSim
    ib=min(nBin,floor(mod(psiS,2*pi)/(2*pi/nBin))+1);
    sgn=(-1)^j;
    v=min(max(muB(ib)+sgn*sigma,p.lower+0.3),p.upper-0.3);
    u=min(max(hypot(v*cos(psiS)-wHat(1),v*sin(psiS)-wHat(2)),0.5),19.5);
    x=(u-7.5)/4.5;
    Pm=coefs(1)+coefs(2)*x+coefs(3)*x.^2+coefs(4)*x.^3+coefs(5)*x.^4;
    r0=bBase(ib);
    if isnan(r0), bBase(ib)=Pm; r0=Pm; end
    r=-(Pm-r0)/max(abs(r0),0.1);
    if isnan(bBase(ib)), bBase(ib)=Pm; else, bBase(ib)=0.9*bBase(ib)+0.1*Pm; end
    aDev=v-muB(ib);
    lrT=p.rlLr*max(0.03,1-j/nSim);       % 仿真内lr退火: 先快后紧, 收敛到点
    dB=lrT*r*aDev/(sigma^2);
    dB=min(max(dB,-0.10),0.10);
    muB(ib)=min(max(muB(ib)+dB,p.lower+0.3),p.upper-0.3);
    psiS=psiS+v/p.turnRadius*p.tEval;
end
% ============ Stage C: 部署+在线微调(真实奖励) ============
% μB已收敛到模型最优轮廓; 在线只做小幅修正(吸收模型误差/风漂移)。
sigma=max(p.rlSigmaMin,0.5*p.rlSigma);
phHist=ones(1,n); phHist(1:min(calibSteps,n))=1;
uHat=nan(1,n); wEst=nan(2,n);
uHat(1:min(calibSteps,n))=uStar;
wEst(:,1:min(calibSteps,n))=repmat(wHat,1,min(calibSteps,n));
v=NaN;
while plant.count()<n
    kStep=kStep+1;
    ib=min(nBin,floor(mod(psiUnw,2*pi)/(2*pi/nBin))+1);
    sgn=(-1)^kStep;
    v=min(max(muB(ib)+sgn*sigma,p.lower+0.3),p.upper-0.3);
    c0=plant.count();
    Pm=qs(v,'rl');
    if ~isfinite(Pm), kStep=kStep-1; break; end
    sUsed=plant.count()-c0;
    for j=1:sUsed
        psiUnw=psiUnw+v/p.turnRadius*p.tEval;
    end
    if isnan(Pb), Pb=Pm; else, Pb=0.98*Pb+0.02*Pm; end
    if isnan(bBase(ib)), bBase(ib)=Pm; else, bBase(ib)=0.9*bBase(ib)+0.1*Pm; end
    r=-(Pm-bBase(ib))/max(Pb,0.1);
    aDev=v-muB(ib);
    dB=p.rlLr*r*aDev/(sigma^2);
    dB=min(max(dB,-0.10),0.10);
    muB(ib)=min(max(muB(ib)+dB,p.lower+0.3),p.upper-0.3);
    sigma=max(p.rlSigmaMin,sigma*0.995);
    uHat(kStep)=uStar; wEst(:,kStep)=wHat; phHist(kStep)=3;
end
while plant.count()<n
    plant.q(v,'hold'); plant.amendEstimate(v);
end
info=struct('best',v,'bestP',NaN,'mode','rl','muB',muB,...
    'muHist',{muHist0(muB,n)},'sigma',sigma,'coefs',coefs,'windFinal',wHat,...
    'uStar',uStar,'uLo',uLo,'uHi',uHi,'calibSteps',calibSteps,'fitRms',fitRms,...
    'uHat',uHat,'windEst',wEst,'phase',phHist,'windEst2',{wEst});
end
function y=muHist0(muB,n)
y=repmat(muB(:),1,n);   % 表格参数逐段常数, demo/分析按当前值绘制
end
