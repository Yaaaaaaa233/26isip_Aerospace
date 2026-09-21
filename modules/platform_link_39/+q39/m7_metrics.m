function m = m7_metrics(log, c, anchor)
%Q39.M7_METRICS M7 双口径记账(QUAD_MIGRATION_PLAN 20260921 §5-M7)。
% 同一幕、同一参照列 minPowerTrue(评价器可用真值, 评价≠控制), 能耗超额与 MOE
% 在真值列(powerTrue)与估计列(powerMeas, 0.2s 时延 + 1.2% 噪声语义)各记一遍;
% 差值 = "若评价只能用测量功率, 结论动多少"(估计口径结论漂移)。
% margin = 相对开环超额差(赢面), 双口径各一, 差值 = 口径间赢面磨损。
% anchor = struct('excessOpenTrue',...,'excessOpenEst',...,'vStarAir',...)
% (由开环幕提供, q3_anchor.csv)。known 臂按 3.8 修复语义(真值相位)仍为 oracle
% 上界, 不入双口径对比(M7 注记)。
m = struct();
mop = w36.mop_moe(log, c);
Emin = mop.EminNorm;
Emea = sum(log.powerMeas) * c.tEval;
m.excess_true_pct = mop.energyExcessPercent;
m.moe_true = mop.MOE_energy;
m.excess_est_pct = 100 * (Emea - Emin) / Emin;
m.moe_est = Emin / Emea;
m.delta_excess_pp = m.excess_est_pct - m.excess_true_pct;
tail = max(1, height(log)-c.tailSteps+1):height(log);
pt = log.powerTrue(tail); pm = log.powerMeas(tail);
m.bias_meas_pct = 100 * mean((pm - pt) ./ pt);
m.margin_true_pp = anchor.excessOpenTrue - m.excess_true_pct;
m.margin_est_pp = anchor.excessOpenEst - m.excess_est_pct;
m.delta_margin_pp = m.margin_est_pp - m.margin_true_pp;
m.rowsN = height(log);
m.uOpTail = mean(log.airspeed(tail));
end
