function out = trim_curve(resDir)
%Q39.TRIM_CURVE Q1/S3 结构偏差离线分解 + S2 谷移解析表(无风配平, 解析真值口径)。
% 对无风配平点 v 逐点解析(与 3.8 local_curveJV 同式):
%   P_true(v) = 8*bench(n) - 8*sav(T,v) + 4*bench(n)*delta(v) + P_drag(v) + P_aux
%   P_l0(v)   = 8*bench(n)                          (L0 静态映射)
% 分解: dH3 = 8*sav(估计器缺失的诱导节省, 负偏), dH5 = 4*bench*delta(缺失的共轴
% 惩罚, 正偏), dDrag/dAux 同理。P_l0 - P_true = dH3 + dH5 - dDrag - dAux。
% 再对 S2 倾斜档逐档解析 P_l0(v)*(1+b/100*v) 的谷底, 与真值谷底/L0 谷底相减得
% 解析谷移(与闭环 duStarFit 对照的 Tier-1 预测)。
% 输出: <resDir>/q1_trim_curve.csv(逐点) 与 q1_valley_shift.csv(逐档) + 结构体。
pc = plane.config();
vv = 0:0.05:14;
n = numel(vv);
PT = zeros(1,n); PL0 = zeros(1,n); dH3 = zeros(1,n); dH5 = zeros(1,n);
dDrag = zeros(1,n); dAux = zeros(1,n); nkrpm = zeros(1,n);
Vfull = pc.battery_n_ser * interp1(pc.battery_ocv_soc, pc.battery_ocv_cell_V, 1);
nce = pc.ceiling_kn_rpm_per_V * Vfull;
Tce = polyval(pc.bench_T_coef_desc, nce / 1000);
for i = 1:n
    v = vv(i);
    aD = 0.5 * pc.air_density_kgpm3 * pc.cda_m2 * v^2 / pc.mass_kg;
    th = atan(aD / pc.gravity_mps2);
    Trot = pc.mass_kg * pc.gravity_mps2 / (8 * cos(th) * pc.gravity_mps2);  % kgf/桨
    nn = local_n_of_t(pc, min(Trot, Tce));
    nkrpm(i) = nn;
    bench = polyval(q39.p_coef(pc, Vfull), nn);
    sav = local_ind_saving(pc, Trot * pc.gravity_mps2, v);
    dLo = pc.coaxial_delta_base * local_vi_ratio(pc, Trot * pc.gravity_mps2, v)^pc.coaxial_decay_kappa;
    PL0(i) = 8 * bench;
    dH3(i) = 8 * sav;
    % 共轴惩罚作用于扣 H3 之后的功率(植物口径 P_lo=(bench-sav)*(1+delta))
    dH5(i) = 4 * (bench - sav) * dLo;
    dDrag(i) = 0.5 * pc.air_density_kgpm3 * pc.cda_m2 * v^3;
    dAux(i) = pc.aux_power_W;
    PT(i) = PL0(i) - dH3(i) + dH5(i) + dDrag(i) + dAux(i);
end
bias = PL0 - PT;
T = table(vv(:), PT(:), PL0(:), bias(:), dH3(:), dH5(:), dDrag(:), dAux(:), nkrpm(:), ...
    'VariableNames', {'v','Ptrue_W','Pl0_W','bias_W','dH3_W','dH5_W','dDrag_W','dAux_W','n_krpm'});
% ---- 谷底与曲率锚点(二次拟合, 窗 ±1.5 m/s) ----
[vStarT, PTmin] = local_argmin(vv, PT);
[vStarL, PLmin] = local_argmin(vv, PL0);
kTrue = local_curv(vv, PT, vStarT);
kL0 = local_curv(vv, PL0, vStarL);
% ---- S2 逐档解析谷移(真值口径基座 + 合成倾斜, 对应闭环 S2 场景) ----
% 预注册修正(2026-09-21): L0 曲线无谷(argmin 在 v=0, 由 H3 缺失所致), 倾斜
% 敏感性(b1*)只在"已抓住曲线形状的估计器"上有定义 -> 解析表基于 P_true。
bs = [-2.8 -1.4 -0.7 0.7 1.4 2.8];
vStarB = zeros(size(bs)); dvB = zeros(size(bs)); excB = zeros(size(bs));
for ib = 1:numel(bs)
    Pb = PT .* (1 + bs(ib)/100 * vv);
    vStarB(ib) = local_argmin(vv, Pb);
    dvB(ib) = vStarB(ib) - vStarT;
    % 若算法飞在"带偏拟合谷底", 真实口径付出的超额(相对真谷)
    excB(ib) = 100 * (interp1(vv, PT, vStarB(ib)) - PTmin) / PTmin;
end
TV = table(bs(:), vStarB(:), dvB(:), excB(:), ...
    'VariableNames', {'b_pct_mps','vstar_fitted','dv_vs_true','true_excess_pred_pct'});
if nargin > 0 && ~isempty(resDir)
    if ~exist(resDir, 'dir'), mkdir(resDir); end
    writetable(T, fullfile(resDir, 'q1_trim_curve.csv'), 'Encoding', 'UTF-8');
    writetable(TV, fullfile(resDir, 'q1_valley_shift.csv'), 'Encoding', 'UTF-8');
end
out = struct('v', vv, 'Ptrue', PT, 'Pl0', PL0, 'bias', bias, 'dH3', dH3, 'dH5', dH5, ...
    'dDrag', dDrag, 'dAux', dAux, 'vStarTrue', vStarT, 'PminTrue', PTmin, ...
    'vStarL0', vStarL, 'PminL0', PLmin, 'kTrue', kTrue, 'kL0', kL0, ...
    'bList', bs, 'vStarBiased', vStarB, 'dvVsTrue', dvB, 'Vfull', Vfull);
fprintf('trim: vStarTrue=%.3f (Pmin=%.1fW, k=%.2f W/(m/s)^2) | vStarL0=%.3f (k=%.2f)\n', ...
    vStarT, PTmin, kTrue, vStarL, kL0);
fprintf('L0 hover bias=%.2f%% (%.1fW) | bias@6m/s=%.2f%% @9m/s=%.2f%%\n', ...
    100*bias(find(vv==0,1))/PT(find(vv==0,1)), bias(find(vv==0,1)), ...
    100*interp1(vv,bias,6)/interp1(vv,PT,6), 100*interp1(vv,bias,9)/interp1(vv,PT,9));
end
function [vStar, Pmin] = local_argmin(v, P)
[Pmin, i] = min(P); vStar = v(i);
end
function k = local_curv(v, P, v0)
msk = v >= v0-1.5 & v <= v0+1.5;
p = polyfit(v(msk)-v0, P(msk), 2);
k = 2*p(1);
end
function n = local_n_of_t(pc, t)
b = pc.bench_T_coef_desc;
r = roots([b(1), b(2), b(3) - t]); r = r(imag(r) < 1e-9 & real(r) > 0); n = min(real(r));
if isempty(n) || ~isfinite(n), n = 0; end
end
function [vi, vi0] = local_vi(pc, T_N, vair)
vi = 0; vi0 = 0;
if T_N <= 0 || vair <= 0, return; end
A = pi * (pc.prop_diameter_m^2) / 4; k = T_N / (2 * pc.air_density_kgpm3 * A);
vi0 = sqrt(k); vi = sqrt((vair/2)^2 + k) - vair/2;
end
function ratio = local_vi_ratio(pc, T_N, vair)
[vi, vi0] = local_vi(pc, T_N, vair);
if vi0 > 0, ratio = vi / vi0; else, ratio = 0; end
end
function sv = local_ind_saving(pc, T_N, vair)
[vi, vi0] = local_vi(pc, T_N, vair);
sv = max(0, pc.h3_induced_gain * T_N * (vi0 - vi));
end
