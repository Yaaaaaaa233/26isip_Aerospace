function [J0, J0min] = base_curve(v, c)
%BASE_CURVE 固定基准曲线 J0(v)（崎岖调试二次曲线, 评价侧）。
% J0(v) = 1 + 0.003(v−6)² + A1 cos(2π(v−6)/λ1+π) + A2 cos(2π(v−6)/λ2+π)
% 默认参数下 J0 关于 v=6 严格对称、全局最优恰在 6、J0(6)=1−A1−A2。
% A1=A2=0 退化为任务1纯调试二次曲线。
u = v - c.optimum0;
J0 = 1 + 0.003*u.^2 ...
    + c.rippleA1*cos(2*pi*u/c.rippleL1 + c.rippleF1) ...
    + c.rippleA2*cos(2*pi*u/c.rippleL2 + c.rippleF2);
J0min = 1 - c.rippleA1 - c.rippleA2;   % v=6 处取到(对称设计)
end
