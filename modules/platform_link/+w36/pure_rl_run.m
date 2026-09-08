function info = pure_rl_run(plant, p, n)
%PURE_RL_RUN 纯奖励强化学习(任务3.6成员(源自3.2)): 无扫频、无模型、无u*/风知识——
% 只靠"调速度→仪表盘功率→奖励"直接学出每航向最优地速, 省掉3.1的150步标定学费。
% ── 纯在线RL的难点与本题对策(相对3.1 rl v3的改进) ──
% 难点A 谷底奖励二阶(ΔP≈½f''Δv²)+1%噪声 → 单步信噪比~0.1(ε=0.3时)
%   对策A 探索幅值大幅提高(±plSigma0=1.2 m/s起步): 信噪比∝ε, 推到>1;
%         探索期功率代价≈0.7%/步, σ按0.996/步退火, 学完即收回。
% 难点B 样本饥饿: 24桶各自只分到1/24样本, 纯表格收敛需数千步
%   对策B 邻域共享核更新: 最优地速轮廓随航向平滑, 更新桶ib时按高斯核权重
%         带动±plKern邻桶——等效样本×~5且方向一致(无Fourier式全局干扰)。
% 难点C 更新不稳定(大lr×大ε) → 步长限幅+桶参数有界+σ退火三重兜底。
% 难点D 奖励的航向结构污染梯度(风的调制) → 分航向桶基线(继承3.1)。
% 因果口径(红线1): 只用带噪功率+自身指令(航向死推ψ̂'=v_cmd/R)+tEval;
% p为ctrl_view白名单(无曲线/u*/风/噪声真值); 全程无扫频、无模型拟合。
qs=w36.settled_q(plant,p,n);
nBin=round(p.plBins);
muB=p.initialSpeed*ones(1,nBin);      % 表格型actor: 每航向桶的平均速度
sigma=p.plSigma0;
psiUnw=0; Pb=NaN; kStep=0; v=p.initialSpeed; lastSgn=1; stepsSinceFlip=99;
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
    v=min(max(muB(ib)+sgn*sigma,p.lower+0.3),p.upper-0.3);
    c0=plant.count();
    Pm=qs(v,'pure');
    if ~isfinite(Pm), kStep=kStep-1; break; end
    sUsed=plant.count()-c0;
    for j=1:sUsed
        psiUnw=psiUnw+v/p.turnRadius*p.tEval;
    end
    if isnan(Pb), Pb=Pm; else, Pb=0.98*Pb+0.02*Pm; end
    if isnan(bBase(ib)), bBase(ib)=Pm; else, bBase(ib)=0.9*bBase(ib)+0.1*Pm; end
    r=-(Pm-bBase(ib))/max(abs(bBase(ib)),0.1);
    aDev=v-muB(ib);                    % 截断后的实际动作偏移
    % 瞬态测量不更新: 就位步数>1说明该测量含执行暂态(指令还没飞到位),
    % 用它更新会把"执行误差"误当"动作好坏"——只采样, 不学习。
    if sUsed>1
        muTrace(kStep)=muB(ib); sigHist(kStep)=sigma; ibHist(kStep)=ib;
        continue;
    end
    % ---- 邻域共享高斯核更新(环形) ----
    % lr退火: 学习期大lr快速收敛, 之后降lr压稳态抖动(OU稳态抖动∝√lr)
    lrT=p.plLr*max(0.25,0.99^kStep);
    K=round(p.plKern);
    for b=ib-K:ib+K
        b2=mod(b-1,nBin)+1;
        w=exp(-0.5*((b-ib)/max(K,0.5))^2);
        dB=lrT*w*r*aDev/(sigma^2);
        dB=min(max(dB,-0.05),0.05);
        muB(b2)=min(max(muB(b2)+dB,p.lower+0.3),p.upper-0.3);
    end
    sigma=max(p.plSigmaMin,sigma*0.996);   % σ轻度退火但保持~1(抖动∝1/σ, 深退火反而放大)
    muTrace(kStep)=muB(ib); sigHist(kStep)=sigma; ibHist(kStep)=ib;
end
while plant.count()<n
    plant.q(v,'hold'); plant.amendEstimate(v);
end
info=struct('best',v,'bestP',NaN,'mode','purerl','muB',muB,...
    'muTrace',{muTrace},'sigma',sigma,'sigma0',p.plSigma0,...
    'baselineBins',nBin,'kern',p.plKern);
end
