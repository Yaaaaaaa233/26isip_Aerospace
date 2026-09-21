function tests = tests_q3()
%TESTS_Q3 Q3 机器验收单元门(QUAD_MIGRATION_PLAN 20260921 §4-Q3/§5-M7):
%   L1自洽  est_l1 = L0 + 声明修正逐项重组(<=1e-12 相对); 悬停域修正退化为 +aux;
%   L1闭合  无风配平域 est_l1(v) 与离线解析真值曲线(q39.trim_curve)逐点闭合
%           (<=1e-9 相对, 声明系数=配置自身档);
%   接线    estMode='l1' 测量链: 算法可见列 = 估计链(0.2s 时延 + 1.2% 噪声),
%           尾段偏差 |bias| <=2%(对比 l0 同点 >=5%, S3 结构偏差被 L1 修正闭合);
%   因果    l1 估计空速 lastUhat 只来自测量面字段(结构门), est_l1 不读真值空速;
%   M7      m7_metrics 双口径字段自洽(delta 恒等式) + m7_rows 三行展开;
%   M5短程  l1 模式同会话两遍逐位一致。
tests = functiontests(localfunctions);
end

function setupOnce(tc)  %#ok<INUSD>
q39.paths_q1();
end

%% ---------- L1 估计器单元 ----------
function test_l1_self_consistency(tc)
pc = plane.config();
pwm = 1650 * ones(8,1);
V = 26.8; uair = 6.5;
[P1, parts1] = q39.est_l1(pc, pwm, V, uair);
[Pl0, ~] = q39.est_l0(pc, pwm, V);
P2 = Pl0 - parts1.dH3 + parts1.dH5 + parts1.dDrag + parts1.aux;
tc.verifyLessThan(abs(P1-P2)/P2, 1e-12, 'L1: 输出应与分项重组逐位一致(<=1e-12 相对)');
tc.verifyGreaterThan(P1, 0, 'L1: 估计功率应为正');
end

function test_l1_hover_domain(tc)
pc = plane.config();
pwm = 1600 * ones(8,1);
V = 28.0;
[P1, parts1] = q39.est_l1(pc, pwm, V, 0);
[Pl0, ~] = q39.est_l0(pc, pwm, V);
tc.verifyLessThan(abs(P1 - (Pl0 + pc.aux_power_W))/P1, 1e-12, ...
    'L1: 悬停域修正应退化为 +aux(dH3=dH5=dDrag=0)');
tc.verifyLessThan(abs(parts1.dH3), 1e-12, 'L1: 悬停域 dH3 应为 0');
tc.verifyLessThan(abs(parts1.dH5), 1e-12, 'L1: 悬停域 dH5 应为 0');
tc.verifyLessThan(abs(parts1.dDrag), 1e-12, 'L1: 悬停域 dDrag 应为 0');
% 声明系数覆盖: aux 声明档降为 5W, 输出应跟随声明而非配置真值
[Pd, partsd] = q39.est_l1(pc, pwm, V, 0, struct('aux_power_W', 5));
tc.verifyLessThan(abs(Pd - (Pl0 + 5))/Pd, 1e-12, ...
    'L1: decl 覆盖应使 aux 项取声明值');
tc.verifyLessThan(abs(partsd.aux - 5), 1e-12, 'L1: decl 覆盖分项应等于声明值');
% 未知覆盖字段必须拒绝(防静默拼错字段名)
tc.verifyError(@() q39.est_l1(pc, pwm, V, 0, struct('aux_power_w', 5)), ...
    'q39:EstL1', 'L1: decl 未知字段应报错');
end

function test_l1_trim_closure(tc)
% 无风配平域: est_l1(n(pwm(n)), Vfull, v) 应与离线解析真值曲线闭合。
% 声明系数 = 配置自身 -> 唯一残差源是油门反解往返(Q1 已证 1e-12)。
out = q39.trim_curve();   % 不落盘的诊断调用
pc = plane.config();
Vfull = out.Vfull;
nce_krpm = pc.ceiling_kn_rpm_per_V * Vfull / 1000;
Tce = polyval(pc.bench_T_coef_desc, nce_krpm);
vv = [0 3 6 9 12];
err = zeros(size(vv));
for i = 1:numel(vv)
    v = vv(i);
    aD = 0.5 * pc.air_density_kgpm3 * pc.cda_m2 * v^2 / pc.mass_kg;
    th = atan(aD / pc.gravity_mps2);
    TrotKgf = pc.mass_kg / (8 * cos(th));
    b = pc.bench_T_coef_desc;
    r = roots([b(1), b(2), b(3) - TrotKgf]);
    r = r(imag(r) < 1e-9 & real(r) > 0);
    n = min(real(r));                          % krpm(台架 T 反解, 与 trim 同式)
    pwm = 1000 + 1000 * min(1, n / nce_krpm) * ones(8, 1);
    P1 = q39.est_l1(pc, pwm, Vfull, v);
    Pref = interp1(out.v, out.Ptrue, v, 'nearest');
    err(i) = abs(P1 - Pref) / Pref;
end
tc.verifyLessThan(max(err), 1e-9, ...
    'L1: 配平域应与解析真值曲线闭合(<=1e-9 相对, 声明上界档)');
end

%% ---------- 测量链接线(植物级, 120s 短程) ----------
function [c, scn, o1, o0] = local_cfg()
c = w36.config('backend','platform','evalSeconds',120,'tailSteps',5,'seed',11,...
    'windKind','composite','windBias',2.5,'windAmp',0,'windAmpY',0,'turbStd',0.3);
scn = w36.scenario('static', c);
o1 = opt('l1'); o0 = opt('l0');
end

function o = opt(mode)
o = struct('estMode',mode,'s1_pct',0,'s2_pct_mps',0,'s4_vpct',0,...
    'dwell_s',0,'pretrainCache',false);
o.arms = {};   % struct() 空 cell 陷阱
o.decl = [];
end

function test_plant_l1_measurement_chain(tc)
% L1 接线后: 算法可见列(估计口径)在开环运行点的尾段偏差应 <=2%
% (S3 结构偏差被 L1 气速修正闭合; 剩余 = 时延/噪声/一步电压因果偏移)。
[c, scn, o1, ~] = local_cfg();
[log, ~] = q39.run_algorithm('openloop', scn, c, o1);
tail = max(1, height(log)-c.tailSteps+1):height(log);
bias = 100 * mean((log.powerMeas(tail) - log.powerTrue(tail)) ./ log.powerTrue(tail));
tc.verifyGreaterThan(height(log), 0, 'L1 接线: 应产出日志');
tc.verifyLessThan(abs(bias), 2.0, ...
    'L1: 开环运行点估计口径尾段偏差应 <=2%(结构性偏差已闭合)');
end

function test_plant_l0_contrast(tc)
% 对照: 同点 l0 的尾段偏差应显著非零(>=5%, S3 本体), 且大于 l1。
[c, scn, o1, o0] = local_cfg();
[logL, ~] = q39.run_algorithm('openloop', scn, c, o0);
[log1, ~] = q39.run_algorithm('openloop', scn, c, o1);
tail = max(1, height(logL)-c.tailSteps+1):height(logL);
b0 = 100 * mean((logL.powerMeas(tail) - logL.powerTrue(tail)) ./ logL.powerTrue(tail));
tail = max(1, height(log1)-c.tailSteps+1):height(log1);
b1 = 100 * mean((log1.powerMeas(tail) - log1.powerTrue(tail)) ./ log1.powerTrue(tail));
tc.verifyGreaterThan(abs(b0), 5.0, ...
    '对照: l0 同点结构性偏差应 >=5%(Q1/S3 本体的短程复现)');
tc.verifyLessThan(abs(b1), abs(b0), '对照: l1 偏差应小于 l0');
end

function test_m7_metrics_and_rows(tc)
% M7 双口径: delta 恒等式 + 三行展开(diff 行 = 差值)。
[c, scn, o1, ~] = local_cfg();
[log, ~] = q39.run_algorithm('openloop', scn, c, o1);
anchor = struct('excessOpenTrue', 6.0, 'excessOpenEst', 5.5, 'vStarAir', 5.15);
m = q39.m7_metrics(log, c, anchor);
tc.verifyEqual(m.delta_excess_pp, m.excess_est_pct - m.excess_true_pct, ...
    'M7: delta_excess 恒等式应精确成立');
tc.verifyEqual(m.delta_margin_pp, m.margin_est_pp - m.margin_true_pp, ...
    'M7: delta_margin 恒等式应精确成立');
tc.verifyTrue(all(isfinite([m.excess_true_pct, m.excess_est_pct, m.moe_true, ...
    m.moe_est, m.bias_meas_pct])), 'M7: 双口径字段应有限');
rf = q39.m7_rows('T', 'openloop', m, 1.0);
tc.verifyEqual(numel(rf), 3, 'M7: 每臂应展开三行');
tc.verifyEqual({rf.caliber}, {'true','est','diff'}, 'M7: 三行口径命名');
tc.verifyEqual(rf(3).excess_pct, m.delta_excess_pp, 'M7: diff 行超额 = 双口径差');
tc.verifyEqual(rf(1).excess_pct, m.excess_true_pct, 'M7: true 行 = 真值口径');
tc.verifyEqual(rf(2).excess_pct, m.excess_est_pct, 'M7: est 行 = 估计口径');
tc.verifyEqual(strjoin({rf.arm}, ','), 'openloop,openloop,openloop__diff', ...
    'M7: diff 行 arm 名带 __diff 后缀');
end

function test_l1_determinism_smoke(tc)
% M5 短程(l1 口径): 同会话两遍逐位一致(全批两遍逐位留 Q4 正式批口径)。
[c, scn, o1, ~] = local_cfg();
[log1, ~] = q39.run_algorithm('sweepcal', scn, c, o1);
[log2, ~] = q39.run_algorithm('sweepcal', scn, c, o1);
tc.verifyEqual(log1.powerMeas, log2.powerMeas, 'M5(l1): 两遍 powerMeas 逐位一致');
tc.verifyEqual(log1.powerTrue, log2.powerTrue, 'M5(l1): 两遍 powerTrue 逐位一致');
end

%% ---------- 因果红线(结构门) ----------
function test_l1_causality_structural(tc)
% l1 的估计空速只允许来自测量面字段; est_l1 本体不得出现真值空速概念。
root = fileparts(mfilename('fullpath'));   % 本文件在模块根, +q39 在其下
src = fileread(fullfile(root, '+q39', 'make_platform_plant_l0.m'));
k = strfind(src, 'lastUhat = abs(dot(');   % 测量赋值行(非 0 初始化)
tc.verifyNotEmpty(k, '因果: lastUhat 测量赋值应存在');
seg = src(k(1):min(k(1) + 240, numel(src)));
tc.verifyTrue(contains(seg, 'ground_velocity_ne_mps') && ...
    contains(seg, 'wind_measured_ne_mps'), ...
    '因果: lastUhat 必须由测量地速 − 风测量合成(结构门)');
tc.verifyFalse(contains(seg, 'air_velocity'), ...
    '因果: lastUhat 不得读真值空速字段');
estNowBlk = regexp(src, 'function Pest = est_now\(\)[\s\S]*?\n    end', 'match');
tc.verifyNotEmpty(estNowBlk, '因果: est_now 块应存在');
tc.verifyFalse(contains(estNowBlk{1}, 'air_velocity'), ...
    '因果: est_now 块不得读真值空速 air_velocity');
src1 = fileread(fullfile(root, '+q39', 'est_l1.m'));
tc.verifyFalse(contains(src1, 'air_velocity'), ...
    '因果: est_l1 本体不得引用真值空速字段');
end
