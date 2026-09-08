function result = run_eta_characteristics(outDir)
%RUN_ETA_CHARACTERISTICS T2.4 eta 特性展示正式批（T24_ETA_CHAR_PLAN v1.0 §3/§4）。
%   模型：P2 eta 路径 v1.1（delta(v)=delta0*(vi(v)/vi0)^kappa、映射 0.55、
%   回中项删除）——谷底位置 eta*(v) 是模型输出而非输入。E5/E6 由
%   run_p2_chain_check 独立承担（同 commit 运行，见证据 README）。
%
%   场景口径（与链检查 G-U 同协议）：圆 R=100 m、W=0、满电 96 Ah、eta 快速
%   到达（tau=1e-3 / rate=100），每 eta 点独立 settle 仿真（|v-v_ref|<=0.05
%   连续 4 s）后取 0.5 s 静默窗 power_demand 均值（需求口径：电池仅经
%   V_prev 进 P(n;V) 块插值，满电数秒内滑移可忽略）。
%
%   交付（T24 方案 §3）：
%     图 1  eta∈[0.75,1.1] × {悬停, v*=5, 8 m/s} 曲线族（κ 敏感带 + delta0
%           上沿叠加，逐子图标谷底位置与深度 W/%）；
%     图 2  eta*(v) 漂移 0..12 m/s（κ 带宽），标注悬停 ~0.90 文献锚与
%           "P4 共轴对台架可验证"口径；
%     指标表.md（E1-E3 机器门 + E4 报告带 + 漂移报告行）+ result.mat。
%   产物写 outDir（缺省 results/eta_characteristics/<stamp>_eta_char，gitignored）。
if nargin < 1 || isempty(outDir)
    outDir = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), ...
        'results', 'eta_characteristics', [char(datetime('now', 'Format', ...
        'yyyyMMdd_HHmmss')) '_eta_char']);
end
if ~exist(outDir, 'dir'), mkdir(outDir); end
addpath(fileparts(mfilename('fullpath')));

VSTAR = 5.0;                   % 登记值（G-U 实测 v*，T2_SCENARIO_PREREG 同源）
etaG = 0.75:0.01:1.1;          % 36 点（缺省曲线）
etaC = 0.75:0.02:1.1;          % 敏感带曲线（谷底定位 0.02 分辨率足够）
scenV = [0, VSTAR, 8];
scenName = {'悬停 v=0', sprintf('巡航 v*=%.0f m/s', VSTAR), '巡航 8 m/s'};
kappaBand = [0.3, 1.0];        % E4 登记带
delta0Hi = 0.176;              % E4 登记带上沿（1/0.85-1）

w0 = struct('time_s', 0, 'wind_truth_ne_mps', [0; 0], ...
    'wind_measured_ne_mps', [0; 0], 'wind_valid', true);
pathC = struct('time_s', 0, 'trajectory_type', 'circle', ...
    'circle_center_ne_m', [0; 0], 'circle_radius_m', 100, 'path_phase_rad', 0, ...
    'path_tangent_ne', [0; 1], 'path_normal_ne', [-1; 0], 'path_valid', true);
c0 = plane.config(); c0.eta_tau_s = 1e-3; c0.eta_rate_s = 100;

%% ---- 图 1 数据：三工况 × {缺省, κ 带, delta0 上沿} ----
Pdef = zeros(3, numel(etaG)); Pk30 = Pdef; Pk100 = Pdef; Pd0h = Pdef;
for si = 1:3
    Pdef(si, :) = local_eta_curve(c0, scenV(si), etaG, w0, pathC);
    ck = c0; ck.coaxial_decay_kappa = kappaBand(1);
    Pk30(si, :) = local_eta_curve(ck, scenV(si), etaG, w0, pathC);
    ck = c0; ck.coaxial_decay_kappa = kappaBand(2);
    Pk100(si, :) = local_eta_curve(ck, scenV(si), etaG, w0, pathC);
    cd = c0; cd.coaxial_delta_base = delta0Hi;
    Pd0h(si, :) = local_eta_curve(cd, scenV(si), etaG, w0, pathC);
    [es, ps] = local_valley(etaG, Pdef(si, :));
    fprintf('%s: P(1.00)=%.1f W, 谷底 eta*=%.3f (%.1f W)\n', ...
        scenName{si}, local_p_at(etaG, Pdef(si, :), 1.0), es, ps);
end

%% ---- 图 2 数据：eta*(v) 漂移 0..12 m/s（缺省全网格 + κ 带粗网格） ----
vD = 0:1:12;
etaD = zeros(size(vD)); etaDlo = etaD; etaDhi = etaD;
for vi = 1:numel(vD)
    Pd = local_eta_curve(c0, vD(vi), etaG, w0, pathC);
    etaD(vi) = local_valley(etaG, Pd);
    ck = c0; ck.coaxial_decay_kappa = kappaBand(1);
    etaDlo(vi) = local_valley(etaC, local_eta_curve(ck, vD(vi), etaC, w0, pathC));
    ck = c0; ck.coaxial_decay_kappa = kappaBand(2);
    etaDhi(vi) = local_valley(etaC, local_eta_curve(ck, vD(vi), etaC, w0, pathC));
    fprintf('v=%2d m/s: eta*=%.3f (κ 带 [%.3f, %.3f])\n', vD(vi), ...
        etaD(vi), etaDlo(vi), etaDhi(vi));
end
bandLo = min(etaDlo, etaDhi); bandHi = max(etaDlo, etaDhi);

%% ---- 门槛（T24 方案 §4，跑批前已冻结登记） ----
g = struct();
[esH, psH] = local_valley(etaG, Pdef(1, :)); g.E1_etaStar = esH;
[esV, psV] = local_valley(etaG, Pdef(2, :)); g.E2_etaStar = esV;
[es8, ps8] = local_valley(etaG, Pdef(3, :)); g.R1_etaStar8 = es8;
g.E1 = g.E1_etaStar >= 0.85 && g.E1_etaStar <= 0.95;
g.E2 = g.E2_etaStar >= 0.88 && g.E2_etaStar <= 1.00 && g.E2_etaStar >= g.E1_etaStar;
g.E3each = [local_unimodal(Pdef(1, :)), local_unimodal(Pdef(2, :)), ...
    local_unimodal(Pdef(3, :))];
g.E3 = all(g.E3each);
g.R2monoSegs = nnz(diff(etaD) >= -0.005);   % 12 段中非降段数（-0.005 容差=网格分辨率一半）
% E4 报告带：深度（对 eta=1 等分口径）与敏感性范围
for si = 1:3
    g.depthW(si) = local_p_at(etaG, Pdef(si, :), 1.0) - min(Pdef(si, :));
    g.depthPct(si) = 100 * g.depthW(si) / local_p_at(etaG, Pdef(si, :), 1.0);
    g.kapRange(si, :) = [local_valley(etaG, Pk30(si, :)), ...
        local_valley(etaG, Pk100(si, :))];
    g.d0hEta(si) = local_valley(etaG, Pd0h(si, :));
end
g.kapHoverWidth = max(abs(Pk30(1, :) - Pk100(1, :)));  % 悬停 κ 不变性（形式自检）
result = struct('pass', g.E1 && g.E2 && g.E3, 'gates', g, 'outDir', string(outDir));
save(fullfile(outDir, 'result.mat'), 'result');

%% ---- 图 1：曲线族 ----
F = figure('Visible', 'off', 'Position', [40 40 1560 500]);
for si = 1:3
    subplot(1, 3, si); hold on; grid on
    bLo = min(Pk30(si, :), Pk100(si, :)); bHi = max(Pk30(si, :), Pk100(si, :));
    fill([etaG, fliplr(etaG)], [bLo, fliplr(bHi)], [0.82 0.89 0.96], ...
        'EdgeColor', 'none');
    plot(etaG, Pdef(si, :), 'b-', 'LineWidth', 1.9);
    plot(etaG, Pd0h(si, :), '--', 'Color', [0.45 0.45 0.45], 'LineWidth', 1.1);
    xline(1.0, 'k:');
    [es, ps] = local_valley(etaG, Pdef(si, :));
    plot(es, ps, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
    text(es, ps, sprintf('  \\eta*=%.3f\n  谷深 %.2f W\n  (%.2f%%)', ...
        es, g.depthW(si), g.depthPct(si)), 'VerticalAlignment', 'bottom', ...
        'FontSize', 8, 'Color', [0.75 0 0]);
    xlabel('\eta（下/上转速比）'); ylabel('P_{demand} (W)');
    title(scenName{si});
    legend({'\kappa 敏感带 0.3–1.0', '\kappa=0.5 缺省', ...
        '\delta_0=0.176 上沿'}, 'Location', 'northwest', 'FontSize', 7);
end
sgtitle({sprintf(['图 1  \\eta–P 特性曲线族（P2 eta 路径 v1.1：' ...
    '\\delta(v)=\\delta_0 (v_i/v_{i0})^{\\kappa}，映射 0.55，无回中项）']); ...
    '悬停子图 κ 带宽恒为 0（v=0 不衰减，模型形式自洽）——带宽随前飞张开'});
saveas(F, fullfile(outDir, '图1_eta_P曲线族.png')); close(F);

%% ---- 图 2：eta*(v) 漂移 ----
F = figure('Visible', 'off', 'Position', [60 60 940 500]);
fill([vD, fliplr(vD)], [bandLo, fliplr(bandHi)], [0.82 0.89  0.96], ...
    'EdgeColor', 'none'); hold on; grid on
plot(vD, etaD, 'b-o', 'LineWidth', 1.9, 'MarkerFaceColor', 'b', 'MarkerSize', 5);
yline(1.0, 'k-', 'HandleVisibility', 'off');
yline(0.90, ':', 'Color', [0.45 0.45 0.45], 'LineWidth', 1.4, ...
    'DisplayName', '文献锚 0.90');
text(0.2, etaD(1) - 0.004, sprintf('悬停 \\eta*=%.3f（文献锚 ~0.90）', etaD(1)), ...
    'VerticalAlignment', 'top', 'Color', 'b');
text(8.2, interp1(vD, etaD, 8) + 0.004, sprintf('8 m/s: \\eta*=%.3f', ...
    interp1(vD, etaD, 8)), 'VerticalAlignment', 'bottom', 'Color', 'b');
xlabel('前飞空速 v_{air} (m/s)'); ylabel('\eta^*(v)（P(\eta) 谷底位置）');
title(sprintf(['图 2  \\eta^*(v) 漂移：悬停 %.3f \\rightarrow 高速向 1 回漂' ...
    '（\\kappa 敏感带 0.3–1.0）'], etaD(1)));
legend({'\kappa 敏感带', '\kappa=0.5 缺省', '文献锚 0.90'}, 'Location', 'southeast');
text(6.0, 0.915, {'模型预测（\delta_0/\kappa 为文献缺省，非实测宣称）', ...
    '升级路径：P4 共轴对台架 P(s_{up};T,v) 三维族一次实验定 \delta_0、\kappa、\eta^*'}, ...
    'FontSize', 8, 'Color', [0.3 0.3 0.3], 'BackgroundColor', [0.97 0.97 0.97]);
saveas(F, fullfile(outDir, '图2_eta_star漂移.png')); close(F);

%% ---- 指标表.md ----
rows = {
 'E1', '悬停 P(η) 谷底位置 η*', sprintf('%.3f', g.E1_etaStar), ...
     '∈ [0.85, 0.95]', g.E1
 'E2', sprintf('v*=%.0f m/s 谷底位置 η*', VSTAR), sprintf('%.3f', g.E2_etaStar), ...
     '∈ [0.88, 1.00] 且 ≥ 悬停', g.E2
 'E3', '单谷性（三工况，缺省 κ=0.5）', sprintf('%d/3', nnz(g.E3each)), ...
     '唯一极小、无多峰伪影', g.E3
 'E4', '悬停谷深（W / %，对 η=1 等分）', ...
     sprintf('%.2f W / %.2f%%', g.depthW(1), g.depthPct(1)), '报告带（不设门）', NaN
 'E4', 'v* 谷深（W / %）', sprintf('%.2f W / %.2f%%', g.depthW(2), g.depthPct(2)), ...
     '报告带（不设门）', NaN
 'E4', '8 m/s 谷深（W / %）', sprintf('%.2f W / %.2f%%', g.depthW(3), g.depthPct(3)), ...
     '报告带（不设门）', NaN
 'E4', 'κ∈[0.3,1.0] 谷底范围（悬停/v*/8）', ...
     sprintf('%.3f–%.3f / %.3f–%.3f / %.3f–%.3f', ...
     min(g.kapRange(1, :)), max(g.kapRange(1, :)), ...
     min(g.kapRange(2, :)), max(g.kapRange(2, :)), ...
     min(g.kapRange(3, :)), max(g.kapRange(3, :))), ...
     '报告带（不设门）', NaN
 'E4', 'δ₀=0.176 上沿谷底（悬停/v*/8）', ...
     sprintf('%.3f / %.3f / %.3f', g.d0hEta(1), g.d0hEta(2), g.d0hEta(3)), ...
     '报告带（不设门）', NaN
 'E4', '悬停 κ 不变性（带宽 max|ΔP|）', sprintf('%.1e W', g.kapHoverWidth), ...
     '报告（形式自检：v=0 不衰减）', NaN
 'R1', '8 m/s 谷底 η*（漂移方向）', sprintf('%.3f', g.R1_etaStar8), ...
     '报告（预期 ≥ v* 谷底）', NaN
 'R2', 'η*(v) 漂移非降段数（0..12 m/s）', sprintf('%d/12 段', g.R2monoSegs), ...
     '报告（方向性观察）', NaN
 'E5/E6', '链检查（悬停三点序 + 全门无回归）', '见 run_p2_chain_check', ...
     '独立承担（同 commit 运行）', NaN
};
fid = fopen(fullfile(outDir, '指标表.md'), 'w', 'n', 'UTF-8');
fprintf(fid, '# T2.4 eta 特性展示·指标表（正式运行）\n\n');
fprintf(fid, ['口径：T24_ETA_CHAR_PLAN v1.0 §3/§4（跑批前冻结）；模型 P2 eta 路径 ' ...
    'v1.1；settle 仿真协议与链检查 G-U 同源；E4 类为报告带不设门（H5 假设' ...
    '依赖，不构成实测宣称）。\n\n']);
fprintf(fid, '| # | 指标 | 实测 | 门槛/口径 | 判定 |\n|---|---|---|---|---|\n');
nPass = 0; nJudge = 0;
for k = 1:size(rows, 1)
    if isnan(rows{k, 5}), jd = '报告';
    else
        if rows{k, 5}, jd = 'PASS'; nPass = nPass + 1; else, jd = 'FAIL'; end
        nJudge = nJudge + 1;
    end
    fprintf(fid, '| %s | %s | %s | %s | %s |\n', rows{k, 1}, rows{k, 2}, ...
        rows{k, 3}, rows{k, 4}, jd);
end
fprintf(fid, '\n**合计：%d/%d PASS**（E4/R 类为登记的报告带与观察行）\n', nPass, nJudge);
fclose(fid);
if result.pass, verdict = 'PASS'; else, verdict = 'FAIL'; end
fprintf('ETA CHARACTERISTICS RUN %s (E1=%d E2=%d E3=%d) -> %s\n', verdict, ...
    g.E1, g.E2, g.E3, outDir);
end

function P = local_eta_curve(c, v, etaGrid, w0, pathC)
% 每 η 点独立 settle 仿真（G-U 同协议）：|v-v_ref|<=0.05 连续 4 s 后取
% 0.5 s 静默窗 power_demand 均值
P = zeros(size(etaGrid));
for gi = 1:numel(etaGrid)
    s = plane.reset(c);
    cmd = struct('v_ref_applied_mps', v, 'eta_ref_applied', etaGrid(gi), ...
        'controller_mode', 'fixed');
    holdCnt = 0; pbuf = [];
    for k = 1:15000
        [s, o] = plane.step(s, w0, pathC, cmd, 0.01, c);
        pbuf(end+1) = o.power_demand_w; %#ok<AGROW>
        if abs(s.v_ground_mps - v) <= 0.05
            holdCnt = holdCnt + 1;
            if holdCnt >= 400, break; end
        else
            holdCnt = 0;
        end
    end
    assert(holdCnt >= 400, 'eta_char:Settle', ...
        'v=%g eta=%.2f did not settle in 15000 steps', v, etaGrid(gi));
    P(gi) = mean(pbuf(end-49:end));
end
end

function [es, ps] = local_valley(etaG, P)
% 谷底位置：网格 argmin + 3 点抛物线细化（顶点偏离 argmin >0.02 时回退网格值）
[pm, i0] = min(P);
es = etaG(i0); ps = pm;
if i0 > 1 && i0 < numel(P)
    cof = polyfit(etaG(i0-1:i0+1), P(i0-1:i0+1), 2);
    ev = -cof(2) / (2 * cof(1));
    if isfinite(ev) && abs(ev - etaG(i0)) <= 0.02
        es = ev; ps = polyval(cof, ev);
    end
end
end

function p = local_p_at(etaG, P, e)
[~, i] = min(abs(etaG - e)); p = P(i);
end

function u = local_unimodal(P)
% 单谷性：全局极小前单调非增、后单调非减（1e-9 W 容差吸收静默窗数值残差）
d = diff(P);
[~, i0] = min(P);
u = all(d(1:i0-1) <= 1e-9) && all(d(i0:end) >= -1e-9);
end
