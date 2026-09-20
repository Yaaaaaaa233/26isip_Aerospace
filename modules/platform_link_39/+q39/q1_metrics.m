function m = q1_metrics(log, info, c, anchor)
%Q39.Q1_METRICS Q1 单幕指标(双口径, P3)。
% 真值口径: excess_true/MOE 来自 powerTrue vs 滑动电压参照(与 moe38 同式);
% 估计口径: bias_meas_pct = 算法可见功率列相对真值列的尾段平均偏差(估计链的
% 实际失配, M7 双口径记账草案); uStarFit/duStarFit = 拟合谷底(sweepcal 显式,
% 其余臂 NaN); uOpTail = 尾段平均空速(全臂统一的运行点指标)。
% anchor = struct('excessOpen',...,'moeOpen',...,'vStarAir',...) 由 ANCHOR 幕提供。
m = struct();
mop = w36.mop_moe(log, c);
m.excess_true_pct = mop.energyExcessPercent;
m.moe_true = mop.MOE_energy;
m.margin_pp = anchor.excessOpen - m.excess_true_pct;   % 赢面 = 相对开环超额差
tail = max(1, height(log)-c.tailSteps+1):height(log);
pt = log.powerTrue(tail); pm = log.powerMeas(tail);
m.bias_meas_pct = 100*mean((pm-pt)./pt);
m.uOpTail = mean(log.airspeed(tail));
m.uStarFit = NaN; m.windErr = NaN;
if isfield(info,'uStar') && isfinite(info.uStar)
    m.uStarFit = info.uStar;
end
if isfield(info,'windFinal') && ~isempty(info.windFinal)
    wTrue = [mean(log.windX(tail)); mean(log.windY(tail))];
    m.windErr = norm(info.windFinal - wTrue);
end
m.duStarFit = m.uStarFit - anchor.vStarAir;
m.rowsN = height(log);
m.estimateTail = mean(log.estimate(tail));
end
