function info = pure_rl_run(plant, p, n)
%PURE_RL_RUN 纯奖励强化学习(w11成员, 源自3.2): 无扫频、无模型、无 r*/γ 知识——
% 只靠"调桨比→仪表盘功率→奖励"直接学出每航向最优桨比, 省掉150步标定学费。
% 难点与对策(移植自3.2, 幅值按桨比域 0.25/4.5 比例缩放):
% A 谷底奖励二阶+1%噪声 → 大幅值对偶探索 σ=plSigma0(0.065)起步, 信噪比∝ε;
%   σ按0.996/步退火到 plSigmaMin(0.03) 收回探索税;
% B 样本饥饿 → 邻域共享高斯核更新(最优桨比轮廓随航向平滑, 更新桶按核权重带动邻桶);
% C 大lr×大ε不稳 → 步长限幅+桶参数有界+σ退火;
% D 航向调制污染梯度 → 分航向桶基线。
% 因果口径(红线1): 只用带噪功率+自身指令+任务参数死推航向+tEval;
% p 为 ctrl_view 白名单; 全程无扫频、无模型拟合(结构性可验证: info 无 coefs/rStar)。
qs=w11.settled_q(plant,p,n);
nBin=round(p.plBins);
muB=1.0*ones(1,nBin);                 % 表格型actor初值: 等转速默认分配
sigma=p.plSigma0;
psiUnw=0; Pb=NaN; kStep=0; r=p.initialRatio; lastSgn=1; stepsSinceFlip=99;
bBase=nan(1,nBin);
muTrace=nan(1,n); sigHist=nan(1,n); ibHist=zeros(1,n);
while plant.count()<n
    kStep=kStep+1;
    ib=min(nBin,floor(mod(psiUnw,2*pi)/(2*pi/nBin))+1);
    % 对偶交替探索(+σ,−σ,...), 符号保持plHold步: 大幅值切换后执行需时间到位,
    % 让测量落在"已到位"的动作上(配合瞬态不更新), 学习信号才不被执行暂态污染。
    if stepsSinceFlip>=p.plHold, lastSgn=-lastSgn; stepsSinceFlip=0; end
    stepsSinceFlip=stepsSinceFlip+1;
    sgn=lastSgn;
    r=min(max(muB(ib)+sgn*sigma,p.lower+0.02),p.upper-0.02);
    c0=plant.count();
    Pm=qs(r,'pure');
    if ~isfinite(Pm), kStep=kStep-1; break; end
    sUsed=plant.count()-c0;
    tStart=(plant.count()-sUsed)*p.tEval;
    for j=1:sUsed
        psiUnw=psiUnw+w11.mission_speed(p,tStart+(j-0.5)*p.tEval)/p.turnRadius*p.tEval;
    end
    if isnan(Pb), Pb=Pm; else, Pb=0.98*Pb+0.02*Pm; end
    if isnan(bBase(ib)), bBase(ib)=Pm; else, bBase(ib)=0.9*bBase(ib)+0.1*Pm; end
    rew=-(Pm-bBase(ib))/max(abs(bBase(ib)),0.1);
    aDev=r-muB(ib);                    % 截断后的实际动作偏移
    % 瞬态测量不更新: 就位步数>1说明该测量含执行暂态(指令还没到位)——只采样不学习。
    if sUsed>1
        muTrace(kStep)=muB(ib); sigHist(kStep)=sigma; ibHist(kStep)=ib;
        continue;
    end
    % ---- 邻域共享高斯核更新(环形) ----
    lrT=p.plLr*max(0.25,0.99^kStep);
    K=round(p.plKern);
    for b=ib-K:ib+K
        b2=mod(b-1,nBin)+1;
        w=exp(-0.5*((b-ib)/max(K,0.5))^2);
        dB=lrT*w*rew*aDev/(sigma^2);
        dB=min(max(dB,-0.003),0.003);
        muB(b2)=min(max(muB(b2)+dB,p.lower+0.02),p.upper-0.02);
    end
    sigma=max(p.plSigmaMin,sigma*0.996);
    muTrace(kStep)=muB(ib); sigHist(kStep)=sigma; ibHist(kStep)=ib;
end
while plant.count()<n
    plant.q(r,'hold'); plant.amendEstimate(r);
end
info=struct('best',r,'bestP',NaN,'mode','purerl','muB',muB,...
    'muTrace',{muTrace},'sigma',sigma,'sigma0',p.plSigma0,...
    'baselineBins',nBin,'kern',p.plKern);
end
