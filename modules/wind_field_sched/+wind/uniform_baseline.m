function out = uniform_baseline(c, t)
%UNIFORM_BASELINE 最优匀速对照（一维搜索，路线交付项）。
% 在一个盘旋周期上以网格+黄金加密搜索最优常值地速 vU，
% 使平均功率最小——"匀速飞行"策略的信息-free下界参照。
% 解析调度(逐点最优)的平均功率不会劣于它；差值即变速调度的收益。
vg=linspace(c.vLower,c.vUpper,401);
nT=max(2,round(c.circlePeriod/c.tEval));
tt=linspace(0,c.circlePeriod,nT+1); tt=tt(1:end-1);
[wx,wy]=wind.wind_truth(c,tt);
psi=2*pi*tt/c.circlePeriod;
q=cos(psi).*wx+sin(psi).*wy; w2=wx.^2+wy.^2;
mp=zeros(size(vg));
for i=1:numel(vg)
    u2=vg(i)^2+2*vg(i).*q+w2;
    P=wind.power_curve(sqrt(max(u2,0)),c);
    mp(i)=mean(P);
end
[~,iU]=min(mp);
% 黄金加密两轮
lo=vg(max(1,iU-4)); hi=vg(min(end,iU+4));
gr=(sqrt(5)-1)/2;
a=lo; bnd=hi;
for it=1:30
    x1=bnd-gr*(bnd-a); x2=a+gr*(bnd-a);
    f1=meanPower(x1,q,w2,c); f2=meanPower(x2,q,w2,c);
    if f1<f2, bnd=x2; else, a=x1; end
end
vU=(a+bnd)/2;
out.vU=vU; out.meanPower=meanPower(vU,q,w2,c);
end

function m=meanPower(v,q,w2,c)
u2=v^2+2*v.*q+w2;
m=mean(wind.power_curve(sqrt(max(u2,0)),c));
end
