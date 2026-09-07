function sse = curve_sse(coefs,th,psSet,rrSet,PmSet,p)
%CURVE_SSE 在给定样本集上评估当前 (f̂,θ̂) 的SSE(供重拟合接受/拒绝判断)。
% 模型: P = f̂(r − δ̂(ψ)), δ̂(ψ)=th(1)+th(2)·cos ψ+th(3)·sin ψ, f̂=归一化基四次式。
if nargin<6, p=struct('lower',0.75,'upper',1.25); end
ps=psSet(:); rr=rrSet(:); Pm=PmSet(:);
u=min(max(rr-(th(1)+th(2)*cos(ps)+th(3)*sin(ps)),p.lower+0.005),p.upper-0.005);
x=(u-1.0)/0.25;
Ph=[ones(size(u)), x, x.^2, x.^3, x.^4];
sse=sum((Ph*coefs(:)-Pm).^2);
end
