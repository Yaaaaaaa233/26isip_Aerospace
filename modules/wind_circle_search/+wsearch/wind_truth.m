function [dxW, dyW, psi] = wind_truth(scn, t)
%WIND_TRUTH 环境模型(评价侧, 不给搜索器)：恒定风 × 圆周运动 → 时变偏移。
% 飞机以 circlePeriod 周期做盘旋(任务3动机: 不能一直朝一个方向飞),
% 航向角 psi(t)=2*pi*t/circlePeriod + windDirDeg。恒定风矢量沿固定方向,
% 逆风半圈需更快/更耗功率, 顺风半圈相反, 故对功率曲线产生周期性平移:
%   dxW(t)=windDxGain*W*cos(psi)   最优空速随航向周期偏移(逆风增大)
%   dyW(t)=windDyGain*W*cos(psi)   功率水平随航向周期升降
% windSpeed=0 时退化为任务1+2口径(完全向后兼容)。
if ~isfield(scn,'windSpeed') || scn.windSpeed==0
    dxW=zeros(size(t)); dyW=zeros(size(t)); psi=zeros(size(t));
    return;
end
psi=2*pi*t/scn.circlePeriod + deg2rad(scn.windDirDeg);
proj=cos(psi);
dxW=scn.windDxGain*scn.windSpeed*proj;
dyW=scn.windDyGain*scn.windSpeed*proj;
end
