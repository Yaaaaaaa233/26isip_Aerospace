function [Wx, Wy, Vx, Vy] = wind_field(scn, t, psi)
%WIND_FIELD 任务9可选风场模型库(对象侧真值; 评价/显示侧复用, 不给因果搜索器)。
% 统一入口: [Wx,Wy,Vx,Vy] = wind_field(scn, t, psi)。t=时间(s), psi=航向角(rad,
% 仅sector使用)。七种模型(scn.windKind):
%   const      恒定风:        Wx=B, Wy=D
%   sin        双正交正弦风:  Wx=A·sin(ω1t)+B, Wy=C·sin(ω2t)+D (任务4/5/8原口径)
%   square     软边方波风:    Wx=A·sq(ω1t)+B, sq(x)=tanh(k·sin x)/tanh(k),
%              k=squareEdge(1≈正弦, k→∞纯方波; 默认4)。代表风区突变/阵风锋,
%              软边保证连续可微(纯方波不物理)。
%   triangle   三角波风:      Wx=A·tri(ω1t)+B, tri(x)=2/π·asin(sin x)。
%              代表缓慢线性爬升/回落的风(气压梯度渐变)。
%   turb       湍流风:        Wx=B+ξx(t), Wy=D+ξy(t)。Ornstein-Uhlenbeck过程,
%              平稳标准差=windAmp, 相关时间=1/turbTheta(默认5 s)。
%              代表大气湍流(Dryden型低通谱的时域等价)。
%   composite  复合风(推荐, 最贴近实际): sin慢变风 + 小幅湍流(平稳标准差
%              =turbStd, 默认0.3 m/s)。真实风=确定性慢变+宽带脉动的叠加。
%   sector     扇区风(随航向): 线性无散度应变风场 w(r)=w0+G·r 在半径R圆周上的
%              投影: Wx=B−A·cos(ψ+φ), Wy=D+C·sin(ψ+φ), φ=windDirDeg。
%              只依赖航向、周期2π, 模拟地形各向异性/空间不均匀风; 盘旋时
%              与时间周期风等价采样, 是"相位查表"类方法的物理载体。
% 湍流序列(ξ)在 scenario() 中以独立种子流(seed+917)预生成, 本函数按时间
% 线性插值取值 —— 确定性、可复现、可运行前预览。
% 整体旋转 phi=windDirDeg 只作用于时间类模型(sector 的 φ 已含在公式内)。
k=scn.windKind;
switch k
    case 'const'
        Wx=scn.windBias+0*t; Wy=scn.windBiasY+0*t;
    case 'sin'
        Wx=scn.windAmp *sin(scn.windOmega *t)+scn.windBias;
        Wy=scn.windAmpY*sin(scn.windOmegaY*t)+scn.windBiasY;
    case 'square'
        Wx=scn.windAmp *sqw(scn.windOmega *t,scn.squareEdge)+scn.windBias;
        Wy=scn.windAmpY*sqw(scn.windOmegaY*t,scn.squareEdge)+scn.windBiasY;
    case 'triangle'
        Wx=scn.windAmp *(2/pi)*asin(sin(scn.windOmega *t))+scn.windBias;
        Wy=scn.windAmpY*(2/pi)*asin(sin(scn.windOmegaY*t))+scn.windBiasY;
    case 'turb'
        Wx=scn.windBias +interp1(scn.windT,scn.windTurbX,t,'linear',0);
        Wy=scn.windBiasY+interp1(scn.windT,scn.windTurbY,t,'linear',0);
    case 'composite'
        Wx=scn.windBias +scn.windAmp *sin(scn.windOmega *t)...
            +interp1(scn.windT,scn.windTurbX,t,'linear',0);
        Wy=scn.windBiasY+scn.windAmpY*sin(scn.windOmegaY*t)...
            +interp1(scn.windT,scn.windTurbY,t,'linear',0);
    case 'sector'
        phi=deg2rad(scn.windDirDeg);
        Wx=scn.windBias -scn.windAmp *cos(psi+phi);
        Wy=scn.windBiasY+scn.windAmpY*sin(psi+phi);
        Vx=Wx; Vy=Wy;
        return;
    otherwise
        error('w9:Wind','Unknown windKind: %s',k);
end
phi=deg2rad(scn.windDirDeg);
Vx=Wx*cos(phi)-Wy*sin(phi);
Vy=Wx*sin(phi)+Wy*cos(phi);
end

function y=sqw(x,kk)
y=tanh(kk*sin(x))/tanh(kk);
end
