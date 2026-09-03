function info = bayes_run(plant, p, n)
%BAYES_RUN 贝叶斯代理寻优(GP回归+置信下界采集, 算法逻辑原样移植任务6)。
% 任务7差异: 全部查询经 w7.settled_q 指令就位包装器(扫描/采集/占空比hold
% 都在就位规则下进行), GP超参数与滑窗设计与任务6一致。
% 定位与角色(如实): GP代理全局定位快; 时变尾段跟踪非其专长(见验收横比)。
ellGrid=[1.5 2.5 4 6 9];
vGrid=linspace(p.lower,p.upper,121);           % 候选网格
v0=linspace(p.lower+1,p.upper-1,p.bayesInitN);
V=zeros(0,1); Y=zeros(0,1);
qs=w7.settled_q(plant,p,n);
for k=1:numel(v0)
    y=qs(v0(k),'scan');
    if ~isfinite(y), break; end
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
    post=w7.gp_posterior(Vw,Yw,vGrid,ell,sF,sN);
    [~,ivm]=min(post.mu); vhat=vGrid(ivm);
    % ε-强制多样性: 每第 bayesEvery 个采集步改为在信念±bayesRad内等间距轮询
    if mod(step,p.bayesEvery)==0
        ring=linspace(vhat-p.bayesRad,vhat+p.bayesRad,5);
        ring=min(max(ring,p.lower),p.upper);
        iva=round((numel(vGrid)-1)*(ring(mod(step/p.bayesEvery,5)+1)-p.lower)/...
            (p.upper-p.lower))+1;
    else
        lcb=post.mu-p.bayesKappa*post.sig;
        [~,iva]=min(lcb);
    end
    y=qs(vGrid(iva),'refine');
    if ~isfinite(y), break; end
    V(end+1,1)=vGrid(iva); Y(end+1,1)=y; %#ok<AGROW>
    holdUntil=min(n,plant.count()+p.bayesPeriod-1);   % 占空比: 间歇hold在信念
    while plant.count()<holdUntil
        qs(vhat,'hold');
    end
end
while plant.count()<n
    plant.q(vhat,'hold'); plant.amendEstimate(vhat);
end
info=struct('best',vhat,'bestP',NaN,'ell',ell,'queries',numel(V),...
    'kappa',p.bayesKappa,'window',p.bayesWindow,'period',p.bayesPeriod);
end
