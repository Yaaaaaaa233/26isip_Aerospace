function sse = curve_sse(coefs,w,psSet,vvSet,PmSet)
%CURVE_SSE 在给定样本集上评估当前(f̂,ŵ)的SSE(供重拟合接受/拒绝判断)。
ps=psSet(:); vv=vvSet(:); Pm=PmSet(:);
u=min(max(hypot(vv.*cos(ps)-w(1),vv.*sin(ps)-w(2)),0.5),19.5);
x=(u-7.5)/4.5;
Ph=[ones(size(u)), x, x.^2, x.^3, x.^4];
sse=sum((Ph*coefs(:)-Pm).^2);
end
