function [dGam, dy] = shift_truth(scn, t)
%SHIFT_TRUTH 场景调度分量(纯阶跃/慢漂, 不含干扰场模板)。
%   dGam: γ 阶跃(jumpUp/jumpDown, 第 shiftTime 秒)与慢漂(ramp)分量 —— 类比速度包的
%         曲线平移 dx(最优点跳变/漂移), 这里的跳变量是"干扰因子"而非功率;
%   dy:   纯功率水平上移(offset 场景), 谷底位置不变, 考验算法不误触发。
dGam=zeros(size(t)); dy=zeros(size(t));
for k=1:size(scn.jumps,1)
    hit=t>=scn.jumps(k,1);
    dGam(hit)=dGam(hit)+scn.jumps(k,2);
end
for k=1:size(scn.ramps,1)
    r=scn.ramps(k,:); frac=min(max((t-r(1))/(r(2)-r(1)),0),1);
    dGam=dGam+r(3)*frac;
end
for k=1:size(scn.dys,1)
    hit=t>=scn.dys(k,1);
    dy(hit)=dy(hit)+scn.dys(k,2);
end
end
