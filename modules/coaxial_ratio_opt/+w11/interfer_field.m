function [gRaw, gEff] = interfer_field(scn, t, psi)
%INTERFER_FIELD 等效诱导干扰因子场(对象侧真值; 评价/显示侧复用, 不给因果搜索器)。
% 统一入口: [gRaw,gEff] = interfer_field(scn,t,psi)。t=时间(s),
% psi=积分航向(rad, 仅sector使用)。七种模板与速度包 wind_field 同构(类比移植):
%   const      恒定干扰:      γ = 1+B
%   sin        双正交慢变:    γ = 1+A·sin(ω1t)+B
%   square     软边方波:      γ = 1+A·sq(ω1t)+B (sq=tanh(k·sin)/tanh(k), 阵风锋类比)
%   triangle   三角波:        γ = 1+A·(2/π)·asin(sin ω1t)+B (渐变类比)
%   turb       OU湍动:        γ = 1+B+ξ(t), 平稳std=gammaAmp, 相关时间1/turbTheta
%   composite  复合(推荐):    慢变正弦 + 小幅湍动(std=turbStd) —— 漂移干扰主口径
%   sector     扇区(随航向):  γ = 1+B−A·cos(ψ+φ), φ=gammaDirDeg —— 姿态/来流
%              不对称类比; 只依赖航向、周期2π, 盘旋一圈采样一遍。
% 湍动序列由 scenario() 用独立种子流(seed+917)预生成, 本函数按时间线性插值取值。
% 场景的 γ 阶跃/慢漂分量(dGam)与纯功率偏移(dy)由 shift_truth 单独给出,
% plant 侧取有效干扰 gEff = gRaw + dGam。
k=scn.gammaKind;
switch k
    case 'const'
        gRaw=1+scn.gammaBias+0*t;
    case 'sin'
        gRaw=1+scn.gammaAmp *sin(scn.gammaOmega *t)+scn.gammaBias;
    case 'square'
        gRaw=1+scn.gammaAmp *sqw(scn.gammaOmega *t,scn.squareEdge)+scn.gammaBias;
    case 'triangle'
        gRaw=1+scn.gammaAmp *(2/pi)*asin(sin(scn.gammaOmega *t))+scn.gammaBias;
    case 'turb'
        gRaw=1+scn.gammaBias +interp1(scn.intT,scn.intTurbX,t,'linear',0);
    case 'composite'
        gRaw=1+scn.gammaBias +scn.gammaAmp *sin(scn.gammaOmega *t)...
            +interp1(scn.intT,scn.intTurbX,t,'linear',0);
    case 'sector'
        phi=deg2rad(scn.gammaDirDeg);
        gRaw=1+scn.gammaBias -scn.gammaAmp *cos(psi+phi);
        gEff=gRaw;
        return;
    otherwise
        error('w11:Interfer','Unknown gammaKind: %s',k);
end
gEff=gRaw;
end

function y=sqw(x,kk)
y=tanh(kk*sin(x))/tanh(kk);
end
