function [Pw, nHat] = est_l0(c, pwm, V)
%Q39.EST_L0 L0 静态台架功率估计器(QUAD_MIGRATION_PLAN 20260921 D1)。
%   P_hat = sum_i P_bench(n_hat_i(pwm_i), V_hat)   [W]
% 即实机"每电机油门 + 电池电压"可观测量经一张静态查表合成总功率:
%   - 油门 -> 转速: q39.n_of_pwm(H9 电压耦合反解);
%   - 转速 -> 电功率: 电压分块台架多项式 q39.p_coef(MN1005 拟合, 5 块);
%   - 不含: H3 前飞诱导节省 / H5 共轴干扰 / H4 废阻 / 辅助负载 / 电机动态
%     (静态标定做不到的事, S3 结构性偏差的全部来源)。
% 输入 c = plane.config 结构; pwm = 每电机油门 [us] (任意长度); V = 端电压 [V]。
% 输出 Pw = 估计总功率 [W]; nHat = 反解转速 [krpm] (诊断)。
% 口径: P_hat 属估计口径(ADR-004), 仿真内部真功率仍由植物保留(P3 双口径)。
nHat = q39.n_of_pwm(c, pwm, V);
pc = q39.p_coef(c, V);
Pw = sum(polyval(pc, nHat(:)'));
Pw = max(Pw, 0);
end
