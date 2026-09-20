function pc = p_coef(c, V)
%Q39.P_COEF 分块台架功率系数按端电压线性插值(与 plane.step local_p_coef / 3.8
% local_p_coef38 同式)。Q1 L0 估计器的查表内核: 实机静态标定只能得到这种
% "电压分块 + 转速多项式" 映射, 不含 H3 前飞诱导项/共轴干扰/废阻/辅助负载。
% 输入 c = plane.config 结构, V = 端电压 [V]; 输出 pc = polyval 降序系数(1x4)。
V = min(max(V, c.bench_V_nom(1)), c.bench_V_nom(end));
i = find(c.bench_V_nom <= V, 1, 'last'); j = min(i + 1, numel(c.bench_V_nom));
if i == j, pc = c.bench_P_coef(i, :); return; end
w = (V - c.bench_V_nom(i)) / (c.bench_V_nom(j) - c.bench_V_nom(i));
pc = (1 - w) * c.bench_P_coef(i, :) + w * c.bench_P_coef(j, :);
end
