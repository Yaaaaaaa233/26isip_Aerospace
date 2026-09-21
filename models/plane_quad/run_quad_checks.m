function summary = run_quad_checks()
%RUN_QUAD_CHECKS Q2 轨 A 机器验收入口(单元门 M2 物理不变量 + M3 eta/共轴清除
% + 稳态配平曲线表)。对拍门 M4' 需轨 B(Simulink)就绪后另跑。
% 运行: cd models/plane_quad && run_quad_checks
root = fileparts(mfilename('fullpath'));
addpath(root);
resDir = fullfile(root, 'results');
if ~exist(resDir, 'dir'), mkdir(resDir); end
unit = runtests(fullfile(root, 'tests_quad.m'));
fprintf('单元测试：%d/%d 通过\n', sum([unit.Passed]), numel(unit));
% ---- M4' 轨 A 侧基线: >=5 配平点稳态曲线(满电 + 5 档电压) ----
trimPts = [0 2 4 5 6 8 10 12];
Vfull = []; Vgrid = [];
c = plane_quad.config();
Vfull = c.battery_n_ser*interp1(c.battery_ocv_soc, c.battery_ocv_cell_V, 1);
Vlo = max(c.battery_cutoff_V, min(c.bench_V_nom));
Vgrid = linspace(Vlo, Vfull, 5);
vv = 0:0.05:14;
rows = cell(0, 8);
for iv = 1:numel(Vgrid)
    o = plane_quad.steady_curve(c, Vgrid(iv), vv);
    for it = 1:numel(trimPts)
        rows(end+1,:) = {Vgrid(iv), trimPts(it), interp1(vv,o.P,trimPts(it)), ...
            interp1(vv,o.nPerMotor_krpm,trimPts(it)), interp1(vv,o.satMargin,trimPts(it)), ...
            o.vStar, o.kValley, o.hoverW}; %#ok<AGROW>
    end
end
T = cell2table(rows, 'VariableNames', {'V','v_trim_mps','P_steady_W','n_per_motor_krpm',...
    'sat_margin_ratio','vStar_mps','kValley_W_per_mps2','hover_W'});
writetable(T, fullfile(resDir, 'quad_steady_table.csv'), 'Encoding', 'UTF-8');
oF = plane_quad.steady_curve(c, Vfull, vv);
writetable(table(vv(:), oF.P(:), oF.nPerMotor_krpm(:), oF.satMargin(:)), ...
    fullfile(resDir, 'quad_steady_curve_fullV.csv'), 'Encoding', 'UTF-8');
fprintf('track-A anchors @V=%.2f: hover=%.1fW vStar=%.2f m/s Pmin=%.1fW k=%.2f W/(m/s)^2\n', ...
    Vfull, oF.hoverW, oF.vStar, oF.Pmin_W, oF.kValley);
fprintf('ceiling margin: T_hover/motor=%.3f kgf vs Tce(full)=%.3f kgf (margin %.1f%%)\n', ...
    oF.T_hover_per_motor_kgf, oF.Tce_kgf, 100*(1-oF.T_hover_per_motor_kgf/oF.Tce_kgf));
summary = struct('unitPassed', sum([unit.Passed]), 'unitTotal', numel(unit), ...
    'steadyTable', T, 'anchors', oF);
end
