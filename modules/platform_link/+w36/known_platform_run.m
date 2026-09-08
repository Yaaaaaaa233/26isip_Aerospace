function info = known_platform_run(plant, c, n)
%KNOWN_PLATFORM_RUN 平台oracle参照(任务3.6, 评价侧, 非因果策略)。
% 飞平台解析真值的空速最优 v*_air + 当前风切向补偿(与 nominal 调度同构);
% 真值与风真值只进评价侧(oracle 允许, 红线1 对因果策略的约束不适用于参照)。
% MOE 的 Emin 来自 mop_moe 的 minPowerTrue 列(逐秒理论最低功率), 本策略用作
% demo/checks 的"信息上界"横比点与参照曲线。
tf = plant.truth();
qs = w36.settled_q(plant, c, n);
psi = 0; v = c.initialSpeed; k = 0;
while plant.count() < n
    k = k + 1;
    t = plant.count();
    [Wx, Wy] = plant.windAt(t, psi);
    wt = -Wx*sin(psi) + Wy*cos(psi);   % 平台切向(圆周极角 psi 的切向)
    v = min(max(tf.vStarAir + wt, c.lower + 0.3), c.upper - 0.3);
    Pm = qs(v, 'known');
    if ~isfinite(Pm), break; end
    psi = psi + v/c.turnRadius*c.tEval;   % 死推(oracle与策略同构)
end
while plant.count() < n
    plant.q(v, 'hold'); plant.amendEstimate(v);
end
info = struct('best', v, 'bestP', NaN, 'mode', 'known_platform', ...
    'vStarAir', tf.vStarAir, 'PminW', tf.PminW);
end
