function [W, dxW, dyW, psi] = wind_truth(scn, t)
%WIND_TRUTH 任务4环境模型(评价侧, 不给搜索器)：正弦风 × 圆周盘旋。
% 单方向风(沿 windDirDeg 固定方向)的风速为正弦时间序列:
%   W(t) = windAmp*sin(windOmega*t) + windBias      (m/s, 可为负=反向)
% 飞机以 circlePeriod 周期盘旋, 航向 psi(t)=2*pi*t/circlePeriod+windDirDeg,
% 风在航向上的投影使功率曲线产生周期性平移:
%   dxW(t)=windDxGain*W(t)*cos(psi)   最优空速偏移
%   dyW(t)=windDyGain*W(t)*cos(psi)   功率水平偏移
% windAmp=0 且 windBias=0 时退化为任务1+2口径(完全向后兼容)。
if (~isfield(scn,'windAmp') || scn.windAmp==0) && ...
        (~isfield(scn,'windBias') || scn.windBias==0)
    W=zeros(size(t)); dxW=W; dyW=W; psi=W; return;
end
W=scn.windAmp*sin(scn.windOmega*t)+scn.windBias;
psi=2*pi*t/scn.circlePeriod + deg2rad(scn.windDirDeg);
proj=cos(psi);
dxW=scn.windDxGain*W.*proj;
dyW=scn.windDyGain*W.*proj;
end
