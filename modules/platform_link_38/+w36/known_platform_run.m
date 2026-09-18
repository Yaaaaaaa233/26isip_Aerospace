function info = known_platform_run(plant, c, n)
%KNOWN_PLATFORM_RUN 平台oracle参照(任务3.6, 评价侧, 非因果策略)。
% 飞平台解析真值的空速最优 v*_air + 当前风切向补偿(与 nominal 调度同构);
% 真值与风真值只进评价侧(oracle 允许, 红线1 对因果策略的约束不适用于参照)。
% MOE 的 Emin 来自 mop_moe 的 minPowerTrue 列(逐秒理论最低功率), 本策略用作
% demo/checks 的"信息上界"横比点与参照曲线。
% 任务3.8(2026-09-18) 航向改读真相位: 原死推 ψ+=v_cmd/R 因就位收敛期
%   v_ground<v_cmd 而系统性超前(实测 3600s 累积 ~+90°), 转向补偿的变成近
%   径向风分量 → MOE 0.917。oracle 是评价侧参照, 直接读 plant.phase()(真
%   相位), 转向公式保持 v=u*+wt(平台声明语义: 法向风无功率后果)。
% 诊断与对照实验: docs/evidence/platform_link/task38_eval_reference/known_oracle_diag/。
tf = plant.truth();
qs = w36.settled_q(plant, c, n);
v = c.initialSpeed; k = 0;
while plant.count() < n
    k = k + 1;
    t = plant.count();
    psi = plant.phase();               % 任务3.8: 真相位(oracle 评价侧允许; 死推会累积就位滞后)
    [Wx, Wy] = plant.windAt(t, psi);
    wt = -Wx*sin(psi) + Wy*cos(psi);   % 平台切向(圆周极角 psi 的切向)
    v = min(max(tf.vStarAir + wt, c.lower + 0.3), c.upper - 0.3);
    Pm = qs(v, 'known');
    if ~isfinite(Pm), break; end
end
while plant.count() < n
    plant.q(v, 'hold'); plant.amendEstimate(v);
end
info = struct('best', v, 'bestP', NaN, 'mode', 'known_platform', ...
    'vStarAir', tf.vStarAir, 'PminW', tf.PminW);
end
