function [Wx, Wy, Vx, Vy] = wind_components(scn, t)
%WIND_COMPONENTS 时间类风场取值(兼容旧签名的薄包装)。
% 任务9起统一入口是 wind_field(scn,t,psi) —— sector 模型依赖航向, 必须走
% wind_field; 本包装等价于 psi=0 的 wind_field(sector 下只反映 ψ=0 处的风,
% 仅供时间轴预览; 对象内与 oracle 一律走 wind_field)。
[Wx, Wy, Vx, Vy] = w9.wind_field(scn, t, 0);
end
