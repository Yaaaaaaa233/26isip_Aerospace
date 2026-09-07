function result = t2_acceptance_run(outDir)
%T2_ACCEPTANCE_RUN T2 闭环物理化验收入口（P2/WP6，平台线；验收以
%   docs/T2_ACCEPTANCE_CHECKLIST.md v1.2 + docs/T2_SCENARIO_PREREG.md v1.0
%   为准——场景与门槛全部预登记冻结，本脚本只执行与导出）。
%   图集 A/B/C/D/D5/E + S 汇总 + 指标表.md + result.mat，全部由本脚本从
%   同一次批量运行的日志导出（同源/同种子/同 commit）。产物写 results/
%   （gitignored），权威拷贝入 docs/evidence/。
if nargin < 1 || isempty(outDir)
    outDir = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), ...
        'results', 't2_closedloop', [char(datetime('now', 'Format', ...
        'yyyyMMdd_HHmmss')) '_t2']);
end
if ~exist(outDir, 'dir'), mkdir(outDir); end
addpath(fileparts(mfilename('fullpath')));

INJ = struct('anomaly', [60, 80], 'invalid', [100, 110]);
NS = 20;
TM = 400;
planStub = struct('vStar', 5.0, 'Epred', 0);

%% ---- 批量：两臂 × 20 种子（共享 E_pred 分母）
PctF = zeros(1, NS); PctN = zeros(1, NS);
Ef = zeros(1, NS); En = zeros(1, NS); Ep = zeros(1, NS); Ws = zeros(1, NS);
runsN = cell(1, NS); runsF = cell(1, NS);
for sd = 1:NS
    pl = t2_openloop_run('plan', sd, [], struct('T', TM));
    rf = t2_openloop_run('fixed', sd, pl, struct('T', TM));
    rn = t2_openloop_run('nominal', sd, pl, struct('T', TM));
    PctF(sd) = rf.Percent; PctN(sd) = rn.Percent;
    Ef(sd) = rf.Eactual; En(sd) = rn.Eactual; Ep(sd) = pl.Epred;
    Ws(sd) = pl.W;
    runsF{sd} = rf; runsN{sd} = rn;
    fprintf('seed %2d: W=%.3f  fixed %+7.3f%%  nominal %+7.3f%%\n', ...
        sd, pl.W, rf.Percent, rn.Percent);
end

%% ---- 注入/专项运行（全部按 T2_SCENARIO_PREREG §2）
o0 = struct('W0', 0, 'windAmpJitter', 0);
st = t2_openloop_run('fixed', 1, planStub, ...
    struct('T', 60, 'W0', 0, 'windAmpJitter', 0, 'vStep', [10, 8, 9]));
stL = t2_openloop_run('fixed', 1, planStub, ...
    struct('T', 60, 'W0', 0, 'windAmpJitter', 0, 'vStep', [10, 0, 8]));
cl = t2_openloop_run('fixed', 1, planStub, ...
    struct('T', 60, 'W0', 0, 'windAmpJitter', 0, ...
    'inject', struct('clamp', [30, 50])));
cx = t2_openloop_run('fixed', 1, planStub, struct('inject', INJ));
b4a = t2_openloop_run('fixed', 7, planStub, struct('T', 60, 'W0', 0, 'windAmpJitter', 0));
b4b = t2_openloop_run('fixed', 7, planStub, struct('T', 60, 'W0', 3, 'windAmpJitter', 0));
d2 = t2_openloop_run('fixed', 1, planStub, struct('T', 200, 'soc0', 0.05));
oE = struct('T', 60, 'W0', 0, 'windAmpJitter', 0, 'Vfix', 12, ...
    'cfgOver', {{'az_cmd_mps2', 2.0}});
eF = t2_openloop_run('fixed', 1, planStub, oE);
oE2 = oE; oE2.soc0 = 0.15;
eE = t2_openloop_run('fixed', 1, planStub, oE2);

%% ---- 门槛计算（对照 T2_SCENARIO_PREREG §3）
rn1 = runsN{1}; rf1 = runsF{1};
L = rn1.L;
g = struct();
g.A1 = max(abs(L.radial));
g.A2 = max(abs(L.phiU*rn1.R - L.mileage));
tt = st.L.t; vgv = st.L.vg;
i63 = find(vgv >= 8 + 0.63*(9-8), 1);
g.A3_t63 = tt(i63) - 10;
seg = tt >= 10 & tt < 20;
g.A3_amax = max(abs(diff(vgv(seg)))/st.dt);
segL = stL.L.t >= 10 & stL.L.t < 16;
g.A3L_amax = max(abs(diff(stL.L.vg(segL)))/stL.dt);
winC = cl.L.t >= 30 & cl.L.t < 50;
g.A3_clampApp = all(abs(cl.L.vApp(winC) - 20) < 1e-12);
g.A3_clampBit0 = all(cl.L.flags8(winC) >= 1);
g.A3_clampOut = all(cl.L.flags8(cl.L.t < 30) == 0);
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
sel = L.t >= 30;
sig = L.vg(sel); tsel = L.t(sel); msel = L.mileage(sel);
pk = find(sig(2:end-1) > sig(1:end-2) & sig(2:end-1) > sig(3:end) & ...
    sig(2:end-1) > 3) + 1;
if numel(pk) >= 2
    Tobs = (tsel(pk(end)) - tsel(pk(1))) / (numel(pk) - 1);
    vbar = (msel(pk(end)) - msel(pk(1))) / (tsel(pk(end)) - tsel(pk(1)));
    g.B3 = abs(Tobs - 2*pi*rn1.R/vbar)/Tobs;
else
    g.B3 = NaN;
end
g.B4 = max(max(abs(b4a.L.vg - b4b.L.vg)), max(abs(b4a.L.phi - b4b.L.phi)));
g.C1_in = g.A3_clampBit0; g.C1_out = g.A3_clampOut;
bnd = abs(mod(L.t, rn1.Tc)) < rn1.dt;
chg = find(diff(L.vApp) ~= 0);
g.C2 = ~isempty(chg) && all(bnd(chg + 1));
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
vAll = [rf1.L.Vb, rn1.L.Vb, cx.L.Vb, eF.L.Vb, eE.L.Vb, ...
    d2.L.Vb(d2.L.t < d2.L.t(iCut))];
vAll = vAll(~isnan(vAll));
g.D4 = min(vAll) >= 19.6 - 1e-9 && max(vAll) <= 29.4 + 1e-9;
g.D4min = min(vAll); g.D4max = max(vAll);
% E 组四门（T2_SCENARIO_PREREG §2/§3）
b4F = bitget(eF.L.flags8, 5); b4E = bitget(eE.L.flags8, 5);
b0E = bitget(eE.L.flags8, 1);
satE = find(b4E);
g.E_full = ~any(b4F);
g.E_empty = ~isempty(satE) && numel(satE) > 100;
g.E_bit0 = ~any(b0E);
g.E_cap = max(abs(eE.L.Tact(satE) - eE.L.Tce(satE))) <= 1e-9;
g.E_short = eE.L.vg(end) < eF.L.vg(end) - 1.0;
g.S1_nominal = median(abs(PctN));
g.S1_fixed = median(PctF);
g.S1_pass = g.S1_nominal <= 5;
g.S2_mean = mean(PctF - PctN);
g.S2_max = max(PctF - PctN);
g.S2_std = std(PctF - PctN);
g.nSeeds = NS;

%% ---- 图集 A/B/C/D/D5/E + S
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
title(sprintf('A3 小阶跃 8→9: t63=%.2fs (门 [3.2,3.8]), |a|max=%.2f', g.A3_t63, g.A3_amax));
saveas(F, fullfile(outDir, 'A_运动正确性.png')); close(F);
% B 组
F = figure('Visible', 'off', 'Position', [50 50 1250 900]);
subplot(2, 2, 1); hold on; grid on
plot(L.t, L.wt, 'b-', L.t, L.vair, 'r-', L.t, L.vg, 'k-');
legend('w_t', 'v_{air}', 'v_{ground}', 'Location', 'best');
xlabel('t (s)'); ylabel('m/s');
title('B w_t / 空速 / 地速（nominal：空速≈v*=5 近恒定）');
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
vv = 0:0.1:14;
c2 = rn1.pc;
pv = arrayfun(@(x) local_pmap_pub(c2, x), vv);
plot(vv, pv, 'k-', L.vair(6000:end), L.Pe(6000:end), 'b.', 'MarkerSize', 2);
xline(rn1.vStar, 'r:');
xlabel('v_{air} (m/s)'); ylabel('P (W)');
title('U 形工作点滑动（nominal 恒驻谷底 v*=5，H3 修复后）');
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
yyaxis left; plot(d2.L.t, d2.L.soc, 'b-'); ylabel('SOC'); ylim([0 0.1]);
yyaxis right; plot(d2.L.t, d2.L.Vb, 'r-'); ylabel('V_{bat} (V)');
yline(19.6, 'k:'); xline(g.D2_tCut, 'k--');
xlabel('t (s)');
title(sprintf('D2 深放电截止 t=%.1fs（soc0=0.05，无容量缩放）', g.D2_tCut));
subplot(2, 2, 3); hold on; grid on
plot(cx.L.t, cx.L.Pmeas, 'b.');
xline(100, 'r:'); xline(110, 'r:');
xlabel('t (s)'); ylabel('P_{meas} (W)');
title('D3 无效窗 [100,110)：P_{meas}=NaN 不可用');
subplot(2, 2, 4); hold on; grid on
histogram(vAll, 30);
xline(19.6, 'r:'); xline(29.4, 'r:');
xlabel('V_{bat} (V)'); title('D4 电压窗 [19.6, 29.4] V（量化）');
saveas(F, fullfile(outDir, 'D_功率电池.png')); close(F);
% D5：八电机转速 + 每电机功率（nominal seed1，共轴差动=eta 可视化）
F = figure('Visible', 'off', 'Position', [50 50 1250 700]);
subplot(2, 1, 1); hold on; grid on
plot(L.t, L.nUp, 'b-', L.t, L.nLo, 'r--');
legend('上桨 n_{up}', '下桨 n_{lo}', 'Location', 'best');
xlabel('t (s)'); ylabel('转速 (RPM)');
title('D5 八电机转速（nominal seed1；eta=1 上下桨同推力，H5 δ 造成功率差）');
subplot(2, 1, 2); hold on; grid on
plot(L.t, L.Pe, 'k-');
xlabel('t (s)'); ylabel('P_{total} (W)');
title(sprintf('合成总功率（台架 P(n;V)+H3+δ+废阻；v*=%.1f m/s 驻谷）', rn1.vStar));
saveas(F, fullfile(outDir, 'D5_八电机与合成功率.png')); close(F);
% E：标准饱和负向
F = figure('Visible', 'off', 'Position', [50 50 1250 800]);
subplot(3, 1, 1); hold on; grid on
plot(eF.L.t, eF.L.vg, 'b-', eE.L.t, eE.L.vg, 'r--');
legend('满电臂 v_{ground}', '亏电臂 v_{ground}', 'Location', 'southeast');
ylabel('v (m/s)');
title('E 标准饱和负向：同指令（v=12+爬升 2 m/s²），仅电池状态不同');
subplot(3, 1, 2); hold on; grid on
plot(eE.L.t, eE.L.Tact, 'r-', eE.L.t, eE.L.Tce, 'k--');
legend('ΣT_{actual}', 'H9 上限 T_{ceiling}(V)', 'Location', 'best');
ylabel('推力 (N)');
subplot(3, 1, 3); hold on; grid on
stairs(eE.L.t, b4E, 'r-'); hold on
stairs(eE.L.t, b0E, 'k-');
legend('bit4 rpm 饱和（亏电）', 'bit0 指令夹断', 'Location', 'best');
ylim([-0.2 1.4]); xlabel('t (s)'); ylabel('flags');
title(sprintf('bit4=%d 步 / bit0=%d 步（涌现上限压过指令限幅，分层直接证据）', ...
    numel(satE), sum(b0E)));
saveas(F, fullfile(outDir, 'E_涌现限幅饱和负向.png')); close(F);
% S 组
F = figure('Visible', 'off', 'Position', [50 50 1150 480]);
subplot(1, 2, 1)
boxplot([PctF', PctN'], 'Labels', {'fixed', 'nominal_sched'});
grid on; ylabel('Percent (%)');
title(sprintf('S1 两臂 Percent（%d 种子）: fixed %+.2f%% / nominal |%.2f|%%', ...
    NS, g.S1_fixed, g.S1_nominal));
subplot(1, 2, 2)
histogram(PctF - PctN, 10); grid on;
xlabel('配对差 fixed−nominal (%)'); ylabel('种子数');
title(sprintf('S2 配对差 mean %+.2f%% / max %+.2f%% / std %.2f%%', ...
    g.S2_mean, g.S2_max, g.S2_std));
saveas(F, fullfile(outDir, 'S_Percent两臂汇总.png')); close(F);

%% ---- 指标表.md（对照 T2_SCENARIO_PREREG §3）
rows = {
 'A1', '最大径向误差 (m)', sprintf('%.2e', g.A1), '<= 1e-6', g.A1 <= 1e-6
 'A2', '里程恒等式残差 (m)', sprintf('%.2e', g.A2), '<= 1e-9', g.A2 <= 1e-9
 'A3', '小阶跃 t63 (s)', sprintf('%.3f', g.A3_t63), '3.2–3.8（内核重预登记）', g.A3_t63 >= 3.2 && g.A3_t63 <= 3.8
 'A3', '小阶跃 max加速度 (m/s^2)', sprintf('%.3f', g.A3_amax), '<= 2.0', g.A3_amax <= 2.0 + 1e-9
 'A3', '大阶跃 max加速度 (m/s^2)', sprintf('%.3f', g.A3L_amax), '<= 2.0（指令限幅主导）', g.A3L_amax <= 2.0 + 1e-9
 'A3', '夹断窗 applied=20 且 bit0', sprintf('%d / %d', g.A3_clampApp, g.A3_clampBit0), 'true / true', g.A3_clampApp && g.A3_clampBit0
 'A3', '窗外 bit0 全 0', sprintf('%d', g.A3_clampOut), 'true', g.A3_clampOut
 'A4', '静默窗最大跟踪误差 (m/s)', sprintf('%.3f', g.A4), '<= 0.5（内核重预登记）', g.A4 <= 0.5
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
 'D4', 'V_bat 量化窗 [19.6, 29.4] V', sprintf('[%.2f, %.2f]', g.D4min, g.D4max), 'true（D2 取截止前）', g.D4
 'D5', '转速域/功率量级', '见图 D5', '人工核对（H3 后 U 形驻谷）', NaN
 'E', '满电臂零饱和 (bit4)', sprintf('%d', g.E_full), 'true', g.E_full
 'E', '亏电臂饱和触发 (bit4>100 步)', sprintf('%d 步', numel(satE)), 'true', g.E_empty
 'E', '饱和全程 bit0 不亮（分层）', sprintf('%d', g.E_bit0), 'true', g.E_bit0
 'E', 'ΣT 精确封顶 H9 上限', sprintf('%.1e N', max(abs(eE.L.Tact(satE) - eE.L.Tce(satE)))), '<= 1e-9', g.E_cap
 'E', '亏电臂 shortfall 可见 (v 终值差>1)', sprintf('%.2f vs %.2f', eE.L.vg(end), eF.L.vg(end)), 'true', g.E_short
 'S1', sprintf('nominal |Percent| 中位数 (%%, %d 种子)', NS), sprintf('%.3f', g.S1_nominal), '<= 5（参考带）', g.S1_pass
 'S1', 'fixed Percent 中位数 (%)（不适应代价，报告）', sprintf('%.3f', g.S1_fixed), '仅报告', true
 'S2', '配对差 mean/max/std (%)', sprintf('%+.3f / %+.3f / %.3f', g.S2_mean, g.S2_max, g.S2_std), '>= 20 种子齐全', NS >= 20
};
fid = fopen(fullfile(outDir, '指标表.md'), 'w', 'n', 'UTF-8');
fprintf(fid, '# T2 闭环物理化验收·指标表（正式运行，P2 物理链）\n\n');
fprintf(fid, ['口径：场景与门槛按 docs/T2_SCENARIO_PREREG.md v1.0（跑批前冻结）；' ...
    'plant=P2 物理链默认配置（真实 96 Ah 电池，无占位/缩放）；Percent 用评价' ...
    '侧真值能量，两臂共用同种子 E_pred 分母（解析名义图沿固定点 rollout，' ...
    '满 OCV 电压口径，非循环论证）。\n\n']);
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
fprintf(fid, '\n**合计：%d/%d PASS**（余 2 项人工核对：B2 风三角、D5 量级）\n\n', ...
    nPass, nJudge);
fprintf(fid, ['附注：E 组为 06 v1.2 §2 决策 4 的标准饱和负向（深放电以 soc0 初始化' ...
    '实现，无容量缩放）；fixed 臂 Percent 为"不适应代价"（仅报告）；nominal 臂' ...
    '残差为解析图（满 OCV 口径）与 plant（电压反馈链）的物理差，方向已核（' ...
    'plant 随放电电压略降功率）。\n']);
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
fprintf('T2 ACCEPTANCE RUN %s (%d/%d gates PASS) -> %s\n', verdict, ...
    nPass, nJudge, outDir);
end

function P = local_pmap_pub(c, vair)
% 与 t2_openloop_run 名义图同式（绘图用）
aD = 0.5*c.air_density_kgpm3*c.cda_m2*vair*abs(vair)/c.mass_kg;
th = atan(aD/c.gravity_mps2);
Tkgf = c.mass_kg/(8*cos(th));
Vfull = c.battery_n_ser*interp1(c.battery_ocv_soc, c.battery_ocv_cell_V, 1);
b = c.bench_T_coef_desc;
r = roots([b(1), b(2), b(3) - Tkgf]); r = r(imag(r) < 1e-9 & real(r) > 0);
n = min(real(r));
i = find(c.bench_V_nom <= Vfull, 1, 'last'); j = min(i+1, numel(c.bench_V_nom));
w = (Vfull - c.bench_V_nom(i))/(c.bench_V_nom(j) - c.bench_V_nom(i));
Pc = (1-w)*c.bench_P_coef(i, :) + w*c.bench_P_coef(j, :);
A = pi*(c.prop_diameter_m^2)/4; k = Tkgf*c.gravity_mps2/(2*c.air_density_kgpm3*A);
vi0 = sqrt(k); vi = sqrt((vair/2)^2 + k) - vair/2;
sav = max(0, c.h3_induced_gain*Tkgf*c.gravity_mps2*(vi0 - min(vi, vi0)));
pro = polyval(Pc, n) - sav;
P = c.arm_count*(pro + pro*(1 + c.coaxial_delta_base)) ...
    + 0.5*c.air_density_kgpm3*c.cda_m2*abs(vair)^3 + c.aux_power_W;
end
