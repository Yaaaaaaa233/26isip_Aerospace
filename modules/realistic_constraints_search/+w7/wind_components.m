function [Wx, Wy, Vx, Vy] = wind_components(scn, t)
%WIND_COMPONENTS 双正交正弦风分量(评价/显示侧, 不给搜索器)。
%   x向: Wx(t) = windAmp *sin(windOmega *t) + windBias      (任务4口径)
%   y向: Wy(t) = windAmpY*sin(windOmegaY*t) + windBiasY     (任务5新增)
% 合成风矢量 = R(phi)*[Wx;Wy], phi=windDirDeg(整体旋转)。
% 风对功率的作用 = 在航向上的投影经 windDxGain/windDyGain 平移功率曲线,
% 投影在对象内用积分航向 psi(t) 计算(plant.m), 半径经航向角速度进入风场。
noWind = all([scn.windAmp,scn.windBias,scn.windAmpY,scn.windBiasY]==0);
Wx=zeros(size(t)); Wy=zeros(size(t));
if ~noWind
    Wx=scn.windAmp *sin(scn.windOmega *t)+scn.windBias;
    Wy=scn.windAmpY*sin(scn.windOmegaY*t)+scn.windBiasY;
end
phi=deg2rad(scn.windDirDeg);
Vx=Wx*cos(phi)-Wy*sin(phi);
Vy=Wx*sin(phi)+Wy*cos(phi);
end
