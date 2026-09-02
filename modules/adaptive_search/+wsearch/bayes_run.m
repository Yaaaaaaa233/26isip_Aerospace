function info = bayes_run(plant, p, n)
%BAYES_RUN 贝叶斯代理寻优(GP回归 + 置信下界采集)，滑窗适应时变风场。
% 流程:
%   1) 初始空间填充扫描 bayesInitN 点(tag=scan)；
%   2) 每个查询步在候选网格上取 LCB=μ−κ·σ 最小点查询(tag=refine,
%      最小化口径)——探索(σ)与利用(μ)由 κ 权衡;
%   3) 每 bayesRefit 步在最近 bayesWindow 个观测上按边际似然选核长
%      (核长网格 [1.5 2.5 4 6 9])——滑窗让陈旧观测自动老化,
%      代理模型跟随风场漂移;
%   4) 信念 v̂=后验均值最小点(纯利用, 与探索采集解耦);
%   5) 占空比调度: 每次采集查询后 bayesPeriod−1 步停在信念 v̂(hold),
%      搜索能耗随占空比下降。
% 定位与角色(如实): GP代理对全局定位极快(settle 8~20步, 全算法最快),
% 对多峰不设防; 但持续时变跟踪的尾段精度/能耗不如占空比梯度法
% (spsa/qnewton)——见验收报告横评。
% 黑箱口径：只用 plant.q 测量(红线1)；噪声水平由测量数据幅值估计。
ellGrid=[1.5 2.5 4 6 9];
vGrid=linspace(p.lower,p.upper,121);           % 候选网格
v0=linspace(p.lower+1,p.upper-1,p.bayesInitN);
V=zeros(0,1); Y=zeros(0,1);
for k=1:numel(v0)
    y=plant.q(v0(k),'scan'); plant.amendEstimate(NaN);
    V(end+1,1)=v0(k); Y(end+1,1)=y; %#ok<AGROW>
end
ell=ellGrid(3); step=0; vhat=v0(1);
while plant.count()<n
    step=step+1;
    Vw=V(max(1,end-p.bayesWindow+1):end); Yw=Y(max(1,end-p.bayesWindow+1):end);
    sF=max(std(Yw),0.01);
    sN=0.01*max(mean(abs(Yw)),0.1);           % 噪声水平: 测量幅值的1%(数据估计)
    if mod(step,p.bayesRefit)==0 || step==1    % 核长重估(边际似然最大)
        ybar=mean(Yw); yc=Yw-ybar; bestLL=-inf;
        for e=ellGrid
            K=sF^2*exp(-(Vw-Vw').^2/(2*e^2))+sN^2*eye(numel(Vw));
            [R,flag]=chol(K);
            if flag>0, continue; end
            alpha=R\(R'\yc);
            ll=-sum(log(diag(R)))-0.5*dot(yc,alpha)-0.5*numel(Vw)*log(2*pi);
            if ll>bestLL, bestLL=ll; ell=e; end
        end
    end
    post=wsearch.gp_posterior(Vw,Yw,vGrid,ell,sF,sN);
    [~,ivm]=min(post.mu); vhat=vGrid(ivm);
    % ε-强制多样性: 每第 bayesEvery 个采集步改为在信念±bayesRad内等间距
    % 轮询探针(打破LCB自增强采样簇, 给滑窗持续注入全局证据)
    if mod(step,p.bayesEvery)==0
        ring=linspace(vhat-p.bayesRad,vhat+p.bayesRad,5);
        ring=min(max(ring,p.lower),p.upper);
        iva=round((numel(vGrid)-1)*(ring(mod(step/p.bayesEvery,5)+1)-p.lower)/...
            (p.upper-p.lower))+1;
    else
        lcb=post.mu-p.bayesKappa*post.sig;
        [~,iva]=min(lcb);
    end
    y=plant.q(vGrid(iva),'refine'); plant.amendEstimate(vhat);
    V(end+1,1)=vGrid(iva); Y(end+1,1)=y; %#ok<AGROW>
    holdUntil=min(n,plant.count()+p.bayesPeriod-1);   % 占空比: 间歇hold在信念
    while plant.count()<holdUntil
        plant.q(vhat,'hold'); plant.amendEstimate(vhat);
    end
end
info=struct('best',vhat,'bestP',NaN,'ell',ell,'queries',numel(V),...
    'kappa',p.bayesKappa,'window',p.bayesWindow,'period',p.bayesPeriod);
end
