function summary = run_quad_sim_checks()
%RUN_QUAD_SIM_CHECKS Q2 轨 B 机器验收入口(单元门 + M4' 对拍表 + n 效应 + 就位比)。
% 运行: cd models/plane_quad && run_quad_sim_checks
root = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(root));   % 26isip_Aerospace 仓库根
addpath(root); addpath(fullfile(repo,'models','px4_x8'));
resDir = fullfile(root,'results');
if ~exist(resDir,'dir'), mkdir(resDir); end
unit = runtests(fullfile(root,'tests_quad_sim.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
% ---- M4' 对拍表(Jgain=0): 6 配平点 + 轨 A 参照 + 相对差 ----
vs = [2 4 5 6 8 10]; rows = cell(0,8);
for i = 1:numel(vs)
    R = quad_sim.trim_run([],vs(i),40);
    A = plane_quad.steady_curve(plane_quad.config(),R.Vmean);
    P_A = interp1(A.v,A.P,R.vMean);
    rows(end+1,:) = {vs(i),R.vMean,R.Pmean,P_A,100*abs(R.Pmean-P_A)/P_A, ...
        R.Vmean,R.pitchDeg,R.loadFactorMean}; %#ok<AGROW>
end
T = cell2table(rows,'VariableNames',{'v_ref','v_steady_B','P_B_W','P_A_W', ...
    'relDiff_pct','Vmean','pitchDeg_B','loadFactorMean'});
writetable(T,fullfile(resDir,'quad_sim_m4p_parity.csv'),'Encoding','UTF-8');
fprintf('M4'' parity max rel diff = %.3f%%\n',max(T.relDiff_pct));
% ---- 就位时间比 ----
RB = quad_sim.trim_run([],8,60,struct('settleFrom',[5 8]));
% ---- n 效应复核(Jgain=3): L0 偏差剖面 ----
vs3 = [0 2 4 5 6 8 10]; rows3 = cell(0,5);
for i = 1:numel(vs3)
    R3 = quad_sim.trim_run([],vs3(i),40,struct('Jgain',3));
    rows3(end+1,:) = {vs3(i),R3.Pmean,R3.PHatL0,R3.biasL0_pct,R3.loadFactorMean}; %#ok<AGROW>
end
T3 = cell2table(rows3,'VariableNames',{'v','P_true_W','P_L0_W','biasL0_pct','loadFactorMean'});
writetable(T3,fullfile(resDir,'quad_sim_neffect.csv'),'Encoding','UTF-8');
% 谷底移动检查: Jgain=3 下 P(v) 的 argmin vs 轨 A 谷底
[Pmin3,iv3] = min(T3.P_true_W);
fprintf('n-effect(Jgain=3): vStar_B=%.2f m/s (Pmin %.1f W), biasL0@6=%.2f%% @10=%.2f%%\n', ...
    T3.v(iv3),Pmin3,interp1(T3.v,T3.biasL0_pct,6),interp1(T3.v,T3.biasL0_pct,10));
% ---- 电机滞后 t_dwell 贡献(解析: 4*tau) ----
c = quad_sim.config();
fprintf('motor spool: tau=%.2f s -> 4*tau=%.2f s (t_dwell 下限贡献)\n', ...
    c.motor_tau_s,4*c.motor_tau_s);
summary = struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit), ...
    'parity',T,'neffect',T3,'settleB',RB.settleS);
end
