function nHat = n_of_pwm(c, pwm, V)
%Q39.N_OF_PWM 油门(μs) -> 目标转速反解 [krpm]。
% 正向模型是植物内的 PWM 诊断派生式(step.m L128): pwm = 1000+1000*min(1, n*1000/nce),
% nce = c.ceiling_kn_rpm_per_V*V(H9 涌现上限随端电压线性缩放)。反解为直接乘回:
%   n_hat = frac * nce(V_hat)。
% 实机语义: 飞控下发的是油门指令, FC 侧油门->转速开环映射假设线性于 nce(V_hat);
% V_hat 带传感器偏差时(S4)反解转速与查表电压同时被污染, 这是 S4 场景的物理来源。
% 饱和域(pwm=2000)信息丢失: n_hat=nce <= 真实 n, 估计器系统性低估(诊断位声明)。
% 单位: ceiling_kn_rpm_per_V*V 是 RPM(1140@29.4V), 台架多项式吃 krpm -> 反解后 /1000。
frac = min(1, max(0, (double(pwm) - 1000) / 1000));
nHat = frac * (c.ceiling_kn_rpm_per_V * V) / 1000;
end
