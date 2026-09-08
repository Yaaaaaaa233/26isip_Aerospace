function [dx, dy] = shift_truth(scn, t)
%SHIFT_TRUTH 任务1式平移调度分量(纯 jumps/ramps, 不含风场)。
% 任务7中风致偏移由对象内积分航向实时驱动(plant.m), 不再是时间的闭式函数,
% 故本函数只负责平移调度; 风分量见 wind_components。
dx=zeros(size(t)); dy=zeros(size(t));
for k=1:size(scn.jumps,1)
    hit=t>=scn.jumps(k,1);
    dx(hit)=dx(hit)+scn.jumps(k,2); dy(hit)=dy(hit)+scn.jumps(k,3);
end
for k=1:size(scn.ramps,1)
    r=scn.ramps(k,:); frac=min(max((t-r(1))/(r(2)-r(1)),0),1);
    dx=dx+r(3)*frac;
end
end
