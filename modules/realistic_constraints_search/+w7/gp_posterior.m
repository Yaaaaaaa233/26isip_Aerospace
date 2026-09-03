function out = gp_posterior(Vw, Yw, vGrid, ell, sF, sN)
%GP_POSTERIOR 一维高斯过程回归后验(SE核)：代理模型 μ(x), σ(x)。
% bayes_run 的底层拟合器(与任务6 wsearch.gp_posterior 一致, 独立成函数以便单元测试)。
Vw=Vw(:); Yw=Yw(:); vGrid=vGrid(:);
m=numel(Vw); ybar=mean(Yw); yc=Yw-ybar;
K=sF^2*exp(-(Vw-Vw').^2/(2*ell^2))+sN^2*eye(m);
[R,flag]=chol(K);
if flag>0
    K=K+1e-6*eye(m)*max(diag(K));              % 数值兜底: 对角加载
    [R,flag]=chol(K);
    assert(flag==0,'w7:Cholesky','Kernel matrix not PD.');
end
alpha=R\(R'\yc);
S=sF^2*exp(-(Vw-vGrid.').^2/(2*ell^2));        % m×n: S(i,j)=k(vGrid(j),Vw(i))
mu=S'*alpha+ybar;
T=R\(R'\S);                                     % 列j = K^{-1}·S(:,j)
sig2=max(sF^2*ones(numel(vGrid),1)-sum(S.*T,1)',1e-12);
out.mu=mu; out.sig=sqrt(sig2);
end
