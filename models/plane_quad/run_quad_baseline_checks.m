function result = run_quad_baseline_checks()
%RUN_QUAD_BASELINE_CHECKS 建模调整方案 P0/P1 冒烟验收(开发级 smoke, 2026-10-11)。
% 运行: cd models/plane_quad && run_quad_baseline_checks
% 口径: tier='smoke' —— 正式验收(标准图集+指标表, ACCEPTANCE_AUTOMATION_RULES v1.8
%   §10)待 docs/QUAD_SIM_MODEL_PLAN_20261011.md 的样张清单经文件负责人确认后升格。
% 门(冒烟级, 全部硬断言, 失败携带归档路径退出):
%   S1 配置一致性: 质量=BOM 总重; 惯量=inertia_from_bom 同参重算逐位一致; PM-L1 系数=0
%   S2 悬停锚: trim_run 悬停 Pmean 对映射合成锚 4*P_map(n_hover)+aux <= 3% 相对
%      (映射合成锚=自审量; 工作簿汇总值偏差作为 C7 测量如实报告, 不设门)
%   S3 确定性: 同会话两遍悬停逐位一致(抖动=0 记账)
%   S4 E1 涌现(轻量): P(v) 内点谷底 < P(0) 且 v* in [2, 9] m/s(U 形从物理涌现)
root = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(root));
addpath(root); addpath(fullfile(repo,'models','px4_x8'));
resDir = fullfile(root,'results');
if ~exist(resDir,'dir'), mkdir(resDir); end
names = {'bg','b40','b42'};
sheetHover_W = [359.8 569.99 485.34];   % 工作簿汇总悬停功率(仅报告, C7)
vGrid = [0 2 4 6 8 10];
rows = cell(0, 12); fails = {};
for ib = 1:numel(names)
    nm = names{ib};
    b = quad_sim.baseline(nm);
    c = quad_sim.config(b);
    % ---- S1 配置一致性 ----
    if c.mass_kg ~= b.mass_kg
        fails{end+1} = sprintf('%s: mass mismatch', nm); %#ok<AGROW>
    end
    I2 = quad_sim.inertia_from_bom(local_tip(nm), local_arm(nm), local_tube(nm), ...
        local_tubeLen(nm), local_nTubes(nm), local_central(nm));
    if ~isequal(I2, c.inertia_kgm2)
        fails{end+1} = sprintf('%s: inertia not reproducible from BOM', nm); %#ok<AGROW>
    end
    if c.rotor_advance_power_gain ~= 0 || c.rotor_axial_power_gain ~= 0
        fails{end+1} = sprintf('%s: PM-L1 loadFactor gains not zero', nm); %#ok<AGROW>
    end
    % ---- S2 悬停锚 + S3 确定性 ----
    nHoverK = sqrt((c.mass_kg/4)/c.bench_T_coef_desc(1));      % T=a*n^2 反解, krpm
    Panchor = 4*polyval(c.bench_P_coef(1,:), nHoverK) + c.aux_power_W;
    Rh1 = quad_sim.trim_run(b, 0, 40);
    Rh2 = quad_sim.trim_run(b, 0, 40);
    detOK = isequal(Rh1.Pmean,Rh2.Pmean) && isequal(Rh1.vMean,Rh2.vMean) && ...
        isequal(Rh1.Vmean,Rh2.Vmean) && isequal(Rh1.socEnd,Rh2.socEnd);
    dev = 100*(Rh1.Pmean-Panchor)/Panchor;
    sheetDev = 100*(Rh1.Pmean-sheetHover_W(ib))/sheetHover_W(ib);
    if abs(dev) > 3
        fails{end+1} = sprintf('%s: hover anchor dev %.3f%% > 3%%', nm, dev); %#ok<AGROW>
    end
    if ~detOK
        fails{end+1} = sprintf('%s: nondeterministic hover rerun', nm); %#ok<AGROW>
    end
    % ---- S4 U 形涌现 ----
    Pv = zeros(size(vGrid)); Vv = zeros(size(vGrid));
    for i = 1:numel(vGrid)
        R = quad_sim.trim_run(b, vGrid(i), 40);
        Pv(i) = R.Pmean; Vv(i) = R.vMean;
    end
    [Pmin, iv] = min(Pv(2:end)); vStar = Vv(iv+1);
    uOK = (Pmin < Pv(1)) && vStar >= 2 && vStar <= 9;
    if ~uOK
        fails{end+1} = sprintf('%s: U-shape not emerging (v*=%.2f, Pmin=%.1f vs P0=%.1f)', ...
            nm, vStar, Pmin, Pv(1)); %#ok<AGROW>
    end
    rows(end+1,:) = {nm, c.mass_kg, c.inertia_kgm2(3,3), Panchor, Rh1.Pmean, dev, ...
        sheetHover_W(ib), sheetDev, detOK, vStar, Pmin, Pv(1)}; %#ok<AGROW>
    fprintf('%-4s hover anchor %.1f W vs trim %.1f W (dev %+.3f%%) | sheet %.1f W (dev %+.1f%%, C7) | v*=%.2f m/s Pmin=%.1f W P0=%.1f W | det %d\n', ...
        nm, Panchor, Rh1.Pmean, dev, sheetHover_W(ib), sheetDev, vStar, Pmin, Pv(1), detOK);
end
T = cell2table(rows, 'VariableNames', {'baseline','mass_kg','Izz_kgm2','P_anchor_W', ...
    'P_hover_W','dev_pct','sheet_hover_W','sheet_dev_pct','deterministic', ...
    'vStar_mps','Pmin_W','P0_W'});
csv = fullfile(resDir,'quad_baseline_smoke.csv');
writetable(T, csv, 'Encoding','UTF-8');
% ---- 涌现曲线图(样张素材, 脚本同源导出) ----
fig = figure('Visible','off'); hold on;
for ib = 1:numel(names)
    b = quad_sim.baseline(names{ib});
    Pv = zeros(size(vGrid));
    for i = 1:numel(vGrid), Pv(i) = quad_sim.trim_run(b, vGrid(i), 40).Pmean; end
    plot(vGrid, Pv, '-o', 'DisplayName', names{ib});
end
grid on; xlabel('v_{ref} (m/s)'); ylabel('P_{mean} (W)');
title('baseline P(v) emergence (smoke, workbook-fit maps)');
legend('Location','best');
png = fullfile(resDir,'quad_baseline_Pcurve.png');
saveas(fig, png); close(fig);
result = struct('pass',isempty(fails),'tier','smoke', ...
    'rows',height(T),'csv',csv,'png',png,'failures',{fails});
if ~result.pass
    error('quad:BaselineChecks','SMOKE FAIL (%d): %s | archive: %s', ...
        numel(fails), strjoin(fails, '; '), csv);
end
fprintf('smoke PASS (3 baselines) -> %s\n', csv);
end
function v = local_tip(nm),  v = local_bom(nm,1); end
function v = local_arm(nm),  v = local_bom(nm,2); end
function v = local_tube(nm), v = local_bom(nm,3); end
function v = local_tubeLen(nm), v = local_bom(nm,4); end
function v = local_nTubes(nm), v = local_bom(nm,5); end
function v = local_central(nm), v = local_bom(nm,6); end
function v = local_bom(nm, k)
% 与 +quad_sim/baseline.m 中 inertia_from_bom 实参同源(审计一致性)
switch nm
    case 'b40', v = [0.630 1.00 0.315 2.00 2 6.139];
    case 'b42', v = [0.630 0.75 0.110 1.50 3 3.354];
    case 'bg',  v = [0.559 0.75 0.200 1.50 2 4.360];
    otherwise, error('quad:BaselineChecks','Unknown baseline: %s', nm);
end
v = v(k);
end
