function result = t1_acceptance_run(outDir)
%T1_ACCEPTANCE_RUN T1 开环验收入口（P1/WP5，平台线；验收以
%   docs/T1_ACCEPTANCE_CHECKLIST.md v1.0 为准）。图集 A/B/C/D + S 汇总 +
%   指标表.md + result.mat，全部由本脚本从同一次批量运行的日志导出
%   （同源/同种子/同 commit）。产物默认写 results/（gitignored）。
%
%   场景预登记（P1，验收以本登记为准，参数细节见 t1_openloop_run 头注）：
%     主任务   T=400 s, 圆 R=100 m, 种子 1..20, 两臂（fixed / nominal_sched）
%     A3 阶跃  T=60 s, W=0, v_ref 8→9 @ t=10（小阶跃呈现 τ=1 s；大阶跃由
%              2 m/s² 限幅主导——06 方案 v1.1 §2 决策 4 的分层，见 G2 教训）
%     A3 夹断  T=60 s, W=0, clamp 注入窗 [30,50)（v_cmd=25→20+bit0）
%     C3/C4    T=200 s, fixed, seed1, anomaly [60,80) + invalid [100,110)
%     B4 异风  T=60 s, fixed, W=0 vs W=3（轨迹逐点差，风不进力平衡）
%     D2 截止  T=200 s, fixed, seed1, capScale=0.02（截止锁存）
%     A4 静默窗=参考平稳段（w_t 极值附近）+ fixed 常值段
if nargin < 1 || isempty(outDir)
    outDir = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), ...
        'results', 't1_openloop', [char(datetime('now', 'Format', ...
        'yyyyMMdd_HHmmss')) '_t1']);
end
if ~exist(outDir, 'dir'), mkdir(outDir); end
addpath(fileparts(mfilename('fullpath')));

INJ = struct('anomaly', [60, 80], 'invalid', [100, 110]);
NS = 20;
TM = 400;   % 主任务时长（预登记）：2πR/v̄≈126 s，需 ≥2 个完整摆动周期
planStub = struct('vStar', 6*1.8/2.15, 'Epred', 0);

%% ---- 批量：两臂 × 20 种子（共享 E_pred 分母）
PctF = zeros(1, NS); PctN = zeros(1, NS);
Ef = zeros(1, NS); En = zeros(1, NS); Ep = zeros(1, NS); Ws = zeros(1, NS);
runsN = cell(1, NS); runsF = cell(1, NS);
for sd = 1:NS
    pl = t1_openloop_run('plan', sd, [], struct('T', TM));  % 分母与两臂同 T
    rf = t1_openloop_run('fixed', sd, pl, struct('T', TM));
    rn = t1_openloop_run('nominal', sd, pl, struct('T', TM));
    PctF(sd) = rf.Percent; PctN(sd) = rn.Percent;
    Ef(sd) = rf.Eactual; En(sd) = rn.Eactual; Ep(sd) = pl.Epred;
    Ws(sd) = pl.W;
    runsF{sd} = rf; runsN{sd} = rn;
    fprintf('seed %2d: W=%.3f  fixed %+7.3f%%  nominal %+7.3f%%\n', ...
        sd, pl.W, rf.Percent, rn.Percent);
end

%% ---- 注入/专项运行
st = t1_openloop_run('fixed', 1, planStub, ...
    struct('T', 60, 'W0', 0, 'windAmpJitter', 0, 'vStep', [10, 8, 9]));  % A3 阶跃 8->9
cl = t1_openloop_run('fixed', 1, planStub, ...
    struct('T', 60, 'W0', 0, 'windAmpJitter', 0, ...
    'inject', struct('clamp', [30, 50])));                          % A3 夹断
cx = t1_openloop_run('fixed', 1, planStub, struct('inject', INJ));  % C3/C4
b4a = t1_openloop_run('fixed', 7, planStub, ...
    struct('T', 60, 'W0', 0, 'windAmpJitter', 0));                  % B4 异风
b4b = t1_openloop_run('fixed', 7, planStub, ...
    struct('T', 60, 'W0', 3, 'windAmpJitter', 0));
d2 = t1_openloop_run('fixed', 1, planStub, struct('capScale', 0.02)); % D2

%% ---- 门槛计算（对照 checklist 18 项）
rn1 = runsN{1}; rf1 = runsF{1};
L = rn1.L;
g = struct();
g.A1 = max(abs(L.radial));
g.A2 = max(abs(L.phiU*rn1.R - L.mileage));   % 未回卷相位（φ 在 2π 回卷）
tt = st.L.t; vgv = st.L.vg;
i63 = find(vgv >= 8 + 0.63*(9-8), 1);
g.A3_t63 = tt(i63) - 10;
seg = tt >= 10 & tt < 20;
g.A3_amax = max(abs(diff(vgv(seg)))/st.dt);
winC = cl.L.t >= 30 & cl.L.t < 50;
g.A3_clampApp = all(abs(cl.L.vApp(winC) - 20) < 1e-12);
g.A3_clampBit0 = all(cl.L.flags8(winC) >= 1);
g.A3_clampOut = all(cl.L.flags8(cl.L.t < 30) == 0);
% A4 静默窗：参考平稳段（w_t 极值附近 |dv_ref/dt|≈0）+ fixed 臂常值段；
% nominal 的 v_ref 连续爬升段非"静默"（滞后=τ·斜率是设计行为，见 06 决策 4）
wtPk = find(L.wt(2:end-1) > L.wt(1:end-2) & L.wt(2:end-1) > L.wt(3:end) ...
    & L.t(2:end-1) >= 30 & L.t(2:end-1) <= TM-30) + 1;
q = false(size(L.t));
for pk = wtPk(:)'
    q = q | (abs(L.t - L.t(pk)) <= 5);
end
qf = (rf1.L.t >= 30 & rf1.L.t <= 40) | (rf1.L.t >= TM-50 & rf1.L.t <= TM-40);
g.A4 = max(max(abs(L.vg(q) - L.vApp(q))), ...
    max(abs(rf1.L.vg(qf) - rf1.L.vApp(qf))));
g.B1 = max(abs(L.vair - (L.vg - L.wt)));
% B3 摆动周期（主任务 nominal，稳态段）：观测周期取首末峰平均间隔，
% 理论 2πR/v̄ 的 v̄ 取同跨度（整数个周期）的里程/时间 —— 自洽无窗口偏置
sel = L.t >= 30;
sig = L.vg(sel); tsel = L.t(sel); msel = L.mileage(sel);
pk = find(sig(2:end-1) > sig(1:end-2) & sig(2:end-1) > sig(3:end) & ...
    sig(2:end-1) > 4) + 1;
if numel(pk) >= 2
    Tobs = (tsel(pk(end)) - tsel(pk(1))) / (numel(pk) - 1);
    vbar = (msel(pk(end)) - msel(pk(1))) / (tsel(pk(end)) - tsel(pk(1)));
    g.B3 = abs(Tobs - 2*pi*rn1.R/vbar)/Tobs;
else
    g.B3 = NaN;
end
g.B4 = max(max(abs(b4a.L.vg - b4b.L.vg)), max(abs(b4a.L.phi - b4b.L.phi)));
g.C1_in = g.A3_clampBit0; g.C1_out = g.A3_clampOut;
% C2 ZOH：vApp 跳变只在指令周期边界（用 nominal 主任务——每周期都有跳变）
bnd = abs(mod(L.t, rn1.Tc)) < rn1.dt;
chg = find(diff(L.vApp) ~= 0);
g.C2 = ~isempty(chg) && all(bnd(chg + 1));
% C3 延迟（陡沿 15% 线，阈值基线取 Pmeas 自身沿前后稳态值——异常在入队侧
% 放大，Pmeas 沿后电平=1.3×真值，用真值基线会把阈值压到噪声内）
pm = cx.L.Pmeas;
k0 = find(cx.L.t >= 60, 1);
pre = median(pm(cx.L.t >= 55 & cx.L.t < 60));
post = median(pm(cx.L.t >= 62 & cx.L.t < 66));
thr = pre + 0.15*(post - pre);
kc = find(pm(k0:end) > thr, 1);
g.C3 = cx.L.t(k0 + kc - 1) - 60;
wA = cx.L.t >= 60 & cx.L.t < 80;
wI = cx.L.t >= 100 & cx.L.t < 110;
bit2 = bitget(cx.L.flags8, 3); bit6 = bitget(cx.L.flags8, 7);
g.C4 = all(bit2(wA)) && all(~bit2(~wA)) && all(bit6(wI)) && all(~bit6(~wI));
g.D1 = abs(L.Eplant(end) - L.E(end));
g.D2_mono = all(diff(d2.L.soc) <= 1e-12);
iCut = find(d2.L.flags8 >= 128, 1);
afterCut = d2.L.t > d2.L.t(iCut);
g.D2_cut = ~isempty(iCut) && all(d2.L.Pe(afterCut) == 0);
g.D2_tCut = d2.L.t(iCut);
g.D3 = all(isnan(pm(wI))) && all(cx.L.pval(wI) == false);
vAll = [rf1.L.Vb, rn1.L.Vb, d2.L.Vb];
vAll = vAll(~isnan(vAll));
g.D4 = min(vAll) >= 19.6 - 1e-9 && max(vAll) <= 29.4 + 1e-9;
g.D4min = min(vAll); g.D4max = max(vAll);
g.S1_nominal = median(abs(PctN));
g.S1_fixed = median(PctF);
g.S1_pass = g.S1_nominal <= 5;
g.S2_mean = mean(PctF - PctN);
g.S2_max = max(PctF - PctN);
g.S2_std = std(PctF - PctN);
g.nSeeds = NS;

%% ---- 图集 A/B/C/D + S
% A 组
F = figure('Visible', 'off', 'Position', [50 50 1250 900]);
subplot(2, 2, 1); hold on; grid on; axis equal
th = linspace(0, 2*pi, 400);
plot(rn1.R*cos(th), rn1.R*sin(th), 'k--', 'LineWidth', 1.2);
plot(rn1.R*cos(L.phi), rn1.R*sin(L.phi), 'b-', 'LineWidth', 1.0);
title('A1 轨迹 vs 理想圆（nominal seed1）'); xlabel('E (m)'); ylabel('N (m)');
subplot(2, 2, 2); hold on; grid on
plot(L.t, L.radial, 'b-'); xlabel('t (s)'); ylabel('径向误差 (m)');
title(sprintf('A1 径向误差 max=%.2e m', g.A1));
subplot(2, 2, 3); hold on; grid on
plot(L.t, L.phi*rn1.R, 'b-', L.t, L.mileage, 'r--');
legend('\phi·R', '\int v dt', 'Location', 'northwest');
xlabel('t (s)'); ylabel('里程 (m)');
title(sprintf('A2 里程恒等式残差 max=%.2e m', g.A2));
subplot(2, 2, 4); hold on; grid on
plot(st.L.t, st.L.vApp, 'k-', st.L.t, st.L.vg, 'b-');
xline(10, 'r:'); xlabel('t (s)'); ylabel('v (m/s)');
legend('v_{ref,applied}', 'v_{ground}', 'Location', 'southeast');
title(sprintf('A3 小阶跃 8→9: t63=%.2fs, |a|max=%.2f m/s^2', g.A3_t63, g.A3_amax));
saveas(F, fullfile(outDir, 'A_运动正确性.png')); close(F);
% B 组
F = figure('Visible', 'off', 'Position', [50 50 1250 900]);
subplot(2, 2, 1); hold on; grid on
plot(L.t, L.wt, 'b-', L.t, L.vair, 'r-', L.t, L.vg, 'k-');
legend('w_t', 'v_{air}', 'v_{ground}', 'Location', 'best');
xlabel('t (s)'); ylabel('m/s');
title('B w_t / 空速 / 地速（nominal：空速≈v* 近恒定）');
subplot(2, 2, 2); hold on; grid on; axis equal
quiver(0, 0, 3, 0, 0, 'r', 'LineWidth', 1.5, 'MaxHeadSize', 0.6);
quiver(3, 0, -1.5, 2.6, 0, 'g', 'LineWidth', 1.5, 'MaxHeadSize', 0.6);
quiver(0, 0, 1.5, 2.6, 0, 'b', 'LineWidth', 1.5, 'MaxHeadSize', 0.6);
legend('风 w', '空速 v_{air}=v_g-w', '地速 v_g', 'Location', 'southwest');
axis([-1 4 -0.5 3.2]);
title('B2 风三角：红(风)+绿(空速)=蓝(地速) [人工核对]');
subplot(2, 2, 3); hold on; grid on; axis equal
plot(rn1.R*cos(th), rn1.R*sin(th), 'k--');
plot(b4a.R*cos(b4a.L.phi), b4a.R*sin(b4a.L.phi), 'b-', 'LineWidth', 1.2);
plot(b4b.R*cos(b4b.L.phi), b4b.R*sin(b4b.L.phi), 'go', 'MarkerSize', 3);
title(sprintf('B4 异风轨迹差=%.1e（风不进力平衡）', g.B4));
xlabel('E (m)'); ylabel('N (m)');
subplot(2, 2, 4); hold on; grid on
vv = linspace(0, 12, 200);
pv = rn1.pc.hover_power_W + rn1.pc.speed_power_gain_W_per_mps2*(vv-6).^2 ...
    + rn1.pc.drag_power_gain_W_per_mps2*vv.^2 + rn1.pc.aux_power_W;
plot(vv, pv, 'k-', L.vair(6000:end), L.Pe(6000:end), 'b.', 'MarkerSize', 2);
xline(rn1.vStar, 'r:');
xlabel('v_{air} (m/s)'); ylabel('P (W)');
title('U 形工作点滑动（nominal 恒驻谷底 v*）');
saveas(F, fullfile(outDir, 'B_风的影响.png')); close(F);
% C 组
F = figure('Visible', 'off', 'Position', [50 50 1250 900]);
subplot(2, 2, 1); hold on; grid on
plot(cl.L.t, cl.L.vCmd, 'r-', cl.L.t, cl.L.vApp, 'k-', cl.L.t, cl.L.vg, 'b-');
xline(30, 'k:'); xline(50, 'k:');
legend('v_{cmd}(25 注入)', 'v_{applied}(20)', 'v_{ground}', 'Location', 'northwest');
xlabel('t (s)'); ylabel('m/s');
title(sprintf('C1 夹断窗 [30,50)：applied=20(%d), bit0(%d)', ...
    g.A3_clampApp, g.A3_clampBit0));
subplot(2, 2, 2); hold on; grid on
selz = cl.L.t >= 28 & cl.L.t <= 34;
plot(cl.L.t(selz), cl.L.vApp(selz), 'k.-');
xlabel('t (s)'); ylabel('v_{applied}');
title('C2 ZOH 台阶（跳变仅发生在 0.5s 边界）[人工核对]');
subplot(2, 2, 3); hold on; grid on
selc = cx.L.t >= 58 & cx.L.t <= 62;
plot(cx.L.t(selc), cx.L.Pe(selc), 'k-', cx.L.t(selc), cx.L.Pmeas(selc), 'r.-');
xline(60, 'b:'); xline(60.2, 'g:');
legend('P 真值', 'P_{meas}(延迟0.2s)', 'Location', 'northwest');
xlabel('t (s)'); ylabel('W');
title(sprintf('C3 测量延迟 %.2f s（15%% 线）', g.C3));
subplot(2, 2, 4); hold on; grid on
stairs(cx.L.t, bit2*2 + bit6, 'b-');
xline(60, 'r:'); xline(80, 'r:'); xline(100, 'g:'); xline(110, 'g:');
ylim([-0.2 3.2]); xlabel('t (s)'); ylabel('bit2×2 + bit6');
title('C4 注入窗：bit2 [60,80) / bit6 [100,110)');
saveas(F, fullfile(outDir, 'C_飞控转写.png')); close(F);
% D 组
F = figure('Visible', 'off', 'Position', [50 50 1250 900]);
subplot(2, 2, 1); hold on; grid on
plot(L.t, L.E, 'b-', L.t, cumsum(L.Pe)*rn1.dt, 'r--');
legend('E 对账值', '\Sigma P·dt', 'Location', 'northwest');
xlabel('t (s)'); ylabel('J');
title(sprintf('D1 能量对账残差 %.1e J', g.D1));
subplot(2, 2, 2); hold on; grid on
yyaxis left; plot(d2.L.t, d2.L.soc, 'b-'); ylabel('SOC'); ylim([0 1.05]);
yyaxis right; plot(d2.L.t, d2.L.Vb, 'r-'); ylabel('V_{bat} (V)');
yline(19.6, 'k:'); xline(g.D2_tCut, 'k--');
xlabel('t (s)');
title(sprintf('D2 截止注入 t=%.1fs，截止后 P=0（锁存）', g.D2_tCut));
subplot(2, 2, 3); hold on; grid on
plot(cx.L.t, cx.L.Pmeas, 'b.');
xline(100, 'r:'); xline(110, 'r:');
xlabel('t (s)'); ylabel('P_{meas} (W)');
title('D3 无效窗 [100,110)：P_{meas}=NaN 不可用');
subplot(2, 2, 4); hold on; grid on
histogram(vAll, 30);
xline(19.6, 'r:'); xline(29.4, 'r:');
xlabel('V_{bat} (V)'); title('D4 电压窗 [19.6, 29.4] V');
saveas(F, fullfile(outDir, 'D_功率电池.png')); close(F);
% S 组
F = figure('Visible', 'off', 'Position', [50 50 1150 480]);
subplot(1, 2, 1)
boxplot([PctF', PctN'], 'Labels', {'fixed', 'nominal_sched'});
grid on; ylabel('Percent (%)');
title(sprintf('S1 两臂 Percent（%d 种子）: median fixed %+.2f%% / nominal |%.2f|%%', ...
    NS, g.S1_fixed, g.S1_nominal));
subplot(1, 2, 2)
histogram(PctF - PctN, 10); grid on;
xlabel('配对差 fixed−nominal (%)'); ylabel('种子数');
title(sprintf('S2 配对差 mean %+.2f%% / max %+.2f%% / std %.2f%%', ...
    g.S2_mean, g.S2_max, g.S2_std));
saveas(F, fullfile(outDir, 'S_Percent两臂汇总.png')); close(F);

%% ---- 指标表.md（checklist 18 项 + S）
rows = {
 'A1', '最大径向误差 (m)', sprintf('%.2e', g.A1), '<= 1e-6', g.A1 <= 1e-6
 'A2', '里程恒等式残差 (m)', sprintf('%.2e', g.A2), '<= 1e-9', g.A2 <= 1e-9
 'A3', '小阶跃 t63 (s)', sprintf('%.3f', g.A3_t63), '0.9–1.1', g.A3_t63 >= 0.9 && g.A3_t63 <= 1.1
 'A3', '最大加速度 (m/s^2)', sprintf('%.3f', g.A3_amax), '<= 2.0', g.A3_amax <= 2.0 + 1e-9
 'A3', '夹断窗 applied=20 且 bit0', sprintf('%d / %d', g.A3_clampApp, g.A3_clampBit0), 'true / true', g.A3_clampApp && g.A3_clampBit0
 'A3', '窗外 bit0 全 0', sprintf('%d', g.A3_clampOut), 'true', g.A3_clampOut
 'A4', '静默窗最大跟踪误差 (m/s)', sprintf('%.3f', g.A4), '<= 0.2', g.A4 <= 0.2
 'B1', '空速恒等式残差 (m/s)', sprintf('%.2e', g.B1), '<= 1e-12', g.B1 <= 1e-12
 'B2', '风三角矢量方向', '见图 B', '人工核对', NaN
 'B3', '摆动周期 vs 2πR/v̄ 相对差 (%)', sprintf('%.2f', 100*g.B3), '<= 5%', g.B3 <= 0.05
 'B4', '异风轨迹最大偏差', sprintf('%.1e', g.B4), '= 0', g.B4 == 0
 'C1', 'bit0 窗内 100%/窗外 0', sprintf('%d/%d', g.C1_in, g.C1_out), 'true/true', g.C1_in && g.C1_out
 'C2', 'ZOH 跳变仅在边界', sprintf('%d', g.C2), 'true（+人工核对图）', g.C2
 'C3', '测量延迟 (s)', sprintf('%.3f', g.C3), '0.2±0.02', abs(g.C3 - 0.2) <= 0.02
 'C4', 'bit2/bit6 注入窗 100%/窗外 0', sprintf('%d', g.C4), 'true', g.C4
 'D1', '能量对账残差 (J)', sprintf('%.1e', g.D1), '<= 1e-6', g.D1 <= 1e-6
 'D2', 'SOC 单调 + 截止锁存 P=0', sprintf('%d/%d', g.D2_mono, g.D2_cut), 'true/true', g.D2_mono && g.D2_cut
 'D3', '无效窗 Pmeas=NaN', sprintf('%d', g.D3), 'true', g.D3
 'D4', 'V_bat 全程在 [19.6,29.4] V', sprintf('[%.2f, %.2f]', g.D4min, g.D4max), 'true', g.D4
 'S1', sprintf('nominal |Percent| 中位数 (%%, %d 种子)', NS), sprintf('%.3f', g.S1_nominal), '<= 5（参考带）', g.S1_pass
 'S1', 'fixed Percent 中位数 (%)（不适应代价，报告）', sprintf('%.3f', g.S1_fixed), '仅报告', true
 'S2', '配对差 mean/max/std (%)', sprintf('%+.3f / %+.3f / %.3f', g.S2_mean, g.S2_max, g.S2_std), '>= 20 种子齐全', NS >= 20
};
fid = fopen(fullfile(outDir, '指标表.md'), 'w', 'n', 'UTF-8');
fprintf(fid, '# T1 开环验收·指标表（正式运行，统一 Plane 代理）\n\n');
fprintf(fid, ['口径：场景预登记见 t1_openloop_run 头注（T=200s / R=100m / ' ...
    'W0=3 东 / Tc=0.5s / dt=0.01s / 电池窗口占位参数）；Percent 用评价侧' ...
    '真值能量，两臂共用同种子 E_pred 分母（T1_ACCEPTANCE_CHECKLIST §4 冻结' ...
    '口径）。\n\n']);
fprintf(fid, '| # | 指标 | 实测 | 门槛 | 判定 |\n|---|---|---|---|---|\n');
nPass = 0; nJudge = 0;
for k = 1:size(rows, 1)
    if isnan(rows{k, 5}), jd = '人工'; else
        if rows{k, 5}, jd = 'PASS'; nPass = nPass + 1; else, jd = 'FAIL'; end
        nJudge = nJudge + 1;
    end
    fprintf(fid, '| %s | %s | %s | %s | %s |\n', rows{k, 1}, rows{k, 2}, ...
        rows{k, 3}, rows{k, 4}, jd);
end
fprintf(fid, '\n**合计：%d/%d PASS**（余 1 项人工核对：B2 风三角）\n\n', ...
    nPass, nJudge);
fprintf(fid, ['附注：fixed 臂 Percent 为"不适应代价"（不设门槛，仅报告）；' ...
    'nominal 臂残差含 4-迭代固定点 rollout 的截断，属真实残差而非循环论证；' ...
    '代理世界中"电厂功率偏置"种子扰动不适用（plant==名义模型），该扰动类' ...
    '在 P2 物理化后引入。\n']);
fclose(fid);

result = struct('pass', nPass == nJudge, 'gates', g, ...
    'outDir', string(outDir), 'PctF', PctF, 'PctN', PctN, ...
    'Epred', Ep, 'Ef', Ef, 'En', En, 'Ws', Ws);
save(fullfile(outDir, 'result.mat'), 'result');
if result.pass
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
fprintf('T1 ACCEPTANCE RUN %s (%d/%d gates PASS) -> %s\n', verdict, ...
    nPass, nJudge, outDir);
end
