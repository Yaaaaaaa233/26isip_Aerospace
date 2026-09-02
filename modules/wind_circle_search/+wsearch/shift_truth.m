function [dx, dy] = shift_truth(scn, t)
%SHIFT_TRUTH 任务3总偏移 = 任务1平移调度 + 环境(风×圆周)偏移。
% jumps=[time dx dy] 瞬时作用; ramps=[t0 t1 dx] 线性渐变, 端点外截断;
% 风场部分见 wind_truth(windSpeed=0 即任务1+2口径)。
dx=zeros(size(t)); dy=zeros(size(t));
for k=1:size(scn.jumps,1)
    hit=t>=scn.jumps(k,1);
    dx(hit)=dx(hit)+scn.jumps(k,2); dy(hit)=dy(hit)+scn.jumps(k,3);
end
for k=1:size(scn.ramps,1)
    r=scn.ramps(k,:); frac=min(max((t-r(1))/(r(2)-r(1)),0),1);
    dx=dx+r(3)*frac;
end
[dxW,dyW]=wsearch.wind_truth(scn,t);
dx=dx+dxW; dy=dy+dyW;
end
