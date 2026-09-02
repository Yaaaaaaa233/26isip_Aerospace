function [wx, wy] = wind_truth(c, t)
%WIND_TRUTH 统一风场模块 w(t)（评价侧真值；console 不可见）。
% 三模式（任务3/4/5为同一公式的特例）：
%   const: w=(W,0)  sin: w=(A·sin(ω1t)+B, 0)  dual: 双正交分量
% 再按 windDirDeg 把风从"风坐标系"旋转到世界系（保持正交性）。
t=t(:)';
switch c.windMode
    case 'const'
        Wx=c.windSpeed*ones(size(t)); Wy=zeros(size(t));
    case 'sin'
        Wx=c.windAmp*sin(c.windOmega*t)+c.windBias; Wy=zeros(size(t));
    case 'dual'
        Wx=c.windAmp*sin(c.windOmega*t)+c.windBias;
        Wy=c.windAmpY*sin(c.windOmegaY*t)+c.windBiasY;
end
phi=deg2rad(c.windDirDeg);
wx=Wx*cos(phi)-Wy*sin(phi);
wy=Wx*sin(phi)+Wy*cos(phi);
end
