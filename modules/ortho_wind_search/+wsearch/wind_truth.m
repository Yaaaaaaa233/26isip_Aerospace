function [Wx, Wy, dxW, dyW, psiH, Vx, Vy] = wind_truth(scn, t)
%WIND_TRUTH 任务5环境模型(评价侧, 不给搜索器)：双正交正弦风 × 圆周盘旋。
% 地面坐标系中两个正交方向(由 windDirDeg 整体旋转)各有一列正弦风:
%   x向: Wx(t) = windAmp *sin(windOmega *t) + windBias      (任务4口径)
%   y向: Wy(t) = windAmpY*sin(windOmegaY*t) + windBiasY     (任务5新增)
% 合成风矢量 V(t) = Rx(phi)*[Wx;Wy], phi=windDirDeg;
% 航向 psiH(t)=2*pi*t/circlePeriod; 风在航向上的投影使功率曲线时变:
%   dxW(t)=windDxGain*proj, dyW(t)=windDyGain*proj,
%   proj = Vx*cos(psiH) + Vy*sin(psiH)
% 四个风参数全为0时退化为任务1+2口径(完全向后兼容)。
noWind = all([scn.windAmp,scn.windBias,scn.windAmpY,scn.windBiasY]==0);
if ~isfield(scn,'windAmpY') || noWind
    z=zeros(size(t)); Wx=z; Wy=z; dxW=z; dyW=z; psiH=z; Vx=z; Vy=z; return;
end
Wx=scn.windAmp *sin(scn.windOmega *t)+scn.windBias;
Wy=scn.windAmpY*sin(scn.windOmegaY*t)+scn.windBiasY;
phi=deg2rad(scn.windDirDeg);
Vx=Wx*cos(phi)-Wy*sin(phi);
Vy=Wx*sin(phi)+Wy*cos(phi);
psiH=2*pi*t/scn.circlePeriod;
proj=Vx.*cos(psiH)+Vy.*sin(psiH);
dxW=scn.windDxGain*proj;
dyW=scn.windDyGain*proj;
end
