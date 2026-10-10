function result = run_quad_realism_checks()
%RUN_QUAD_REALISM_CHECKS 建模调整方案 P2 控制现实性验收(开发级 smoke, 2026-10-11)。
% 运行: cd models/plane_quad && run_quad_realism_checks
% 口径: tier='smoke' —— 正式验收(标准图集+指标表)待样张清单确认后升格(同 P0/P1)。
% 矩阵/门槛预注册: +quad_sim/realism_opt(单一事实源, 先于数据冻结)。
% 门(全部硬断言, 失败携带归档路径退出):
%   G-R0 全部格完成同一趟行程且能量有限(可比性)
%   G-R1 保序: 典型整链(TYP)最优速度选择与 REF 一致(近平手带 <gapFloor 报告不判)
%   G-R2 磨损(M6 同款): TYP top-2 赢面磨损 |Δgap| <= 1pp
%   G-R3 真实注入: D2/K1/N1 中档相对 REF 必须留下逐位指纹(轨迹或能量有差)
%   G-R4 环带宽/超调: REF 与 TYP 阶跃就位 <=20 s 且超调 <=20% 步长
%   G-R5 估计链重标定: |bias(TYP)-bias(REF)| <= 2pp(绝对偏差报告, C3/C7)
%   G-R6 确定性: RERUN 与 REF 同会话逐位一致
% 运行口径澄清(2026-10-11 快测后登记, 门槛数值不动):
%   - 比较口径 = E/m(单位航程能量 Wh/m): 减速滑跑使各策略终点航程 200~216 m 不等,
%     逐米归一后同题可比; E_wh 与航程仍在表内如实列出。
%   - G-R4 阶跃表征在平静气流(风关)下进行——地速传感器+地速前馈控制器在头风下
%     有物理稳态差(快测 8 m/s 指令稳态 ~5.5 m/s), "就位到 v_ref"在风里失义;
%     风扰剧本只用于磨损表任务(涌现如实保留)。
% 输出: 磨损表 CSV(cell x strategy) + 阶跃 CSV + 图组 C 素材 PNG。
root = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(root));
addpath(root); addpath(fullfile(repo,'models','px4_x8'));
resDir = fullfile(root,'results');
if ~exist(resDir,'dir'), mkdir(resDir); end
opt = quad_sim.realism_opt();
g = opt.gates; m = opt.mission;
speeds = m.speeds_mps; nS = numel(speeds);
cells = opt.cells; nC = numel(cells);
base = quad_sim.config(quad_sim.baseline('b40'));
E = zeros(nC,nS); Ehat = zeros(nC,nS); bias = zeros(nC,nS);
sat = zeros(nC,nS); dst = zeros(nC,nS); tEnd = zeros(nC,nS); vc = zeros(nC,nS);
done = false(nC,nS); vlogs = cell(nC,nS);
runopt = m; runopt.profile = 'cruise';
for ic = 1:nC
    deg = cells(ic).deg;
    fn = fieldnames(deg); args = cell(1,2*numel(fn));
    for k = 1:numel(fn), args{2*k-1} = fn{k}; args{2*k} = deg.(fn{k}); end
    c = quad_sim.config(base,args{:});
    for is = 1:nS
        runopt.vCmd_mps = speeds(is);
        R = quad_sim.realism_run(c,runopt);
        E(ic,is) = R.E_wh; Ehat(ic,is) = R.Ehat_wh; bias(ic,is) = R.bias_pct;
        sat(ic,is) = R.satDuty; dst(ic,is) = R.dist_m; tEnd(ic,is) = R.tEnd_s;
        vc(ic,is) = R.vMeanCruise; done(ic,is) = R.completed; vlogs{ic,is} = R.vLog;
    end
    [~,ib] = min(E(ic,:)./dst(ic,:));
    fprintf('%-5s %-8s E/m(mJ/m) = %s | argmin %.0f m/s | bias %+0.2f%% | sat %0.3f\n', ...
        cells(ic).id, cells(ic).family, sprintf('%7.1f ',1000*E(ic,:)./dst(ic,:)), ...
        speeds(ib), mean(bias(ic,:)), mean(sat(ic,:)));
end
% ---- 磨损账(口径 E/m, 相对 REF 逐策略) ----
Epm = E./dst;
wear = zeros(nC,nS);
for ic = 1:nC, wear(ic,:) = 100*(Epm(ic,:)-Epm(1,:))./Epm(1,:); end
[Es,ix] = sort(Epm(1,:)); bestRef = speeds(ix(1));
gapRef_pp = 100*(Es(2)-Es(1))/Es(1);
iTYP = find(strcmp({cells.id},'TYP'),1); iRERUN = find(strcmp({cells.id},'RERUN'),1);
[Et,ixt] = sort(Epm(iTYP,:)); bestTyp = speeds(ixt(1));
gapTyp_pp = 100*(Et(2)-Et(1))/Et(1);
marginWear_pp = abs(gapTyp_pp-gapRef_pp);
biasWear_pp = abs(mean(bias(iTYP,:))-mean(bias(1,:)));
fails = {};
% ---- G-R0 ----
if ~all(done(:)) || ~all(isfinite(E(:))) || ~all(isfinite(Epm(:)))
    fails{end+1} = sprintf('G-R0: %d runs incomplete/nonfinite',nnz(~done(:)|~isfinite(E(:))));
end
% ---- G-R1/G-R2 ----
if g.argminStable && bestTyp ~= bestRef
    fails{end+1} = sprintf('G-R1: argmin REF %.0f != TYP %.0f m/s',bestRef,bestTyp);
end
if marginWear_pp > g.marginWearMax_pp
    fails{end+1} = sprintf('G-R2: margin wear %.3f pp > %.1f pp',marginWear_pp,g.marginWearMax_pp);
end
% ---- G-R3 真实注入指纹 ----
contrast = struct();
for id = {'D2','K1','N1'}
    ic = find(strcmp({cells.id},id{1}),1);
    fp = local_fp_diff(vlogs{1,1},vlogs{ic,1}) || any(E(ic,:)~=E(1,:));
    contrast.(id{1}) = fp;
    if ~fp, fails{end+1} = sprintf('G-R3: %s left no fingerprint (degradation not injected)',id{1}); end
end
% ---- G-R4 阶跃 ----
stepRows = cell(0,5);
for id = {'REF','TYP'}
    ic = find(strcmp({cells.id},id{1}),1);
    deg = cells(ic).deg;
    fn = fieldnames(deg); args = cell(1,2*numel(fn));
    for k = 1:numel(fn), args{2*k-1} = fn{k}; args{2*k} = deg.(fn{k}); end
    c = quad_sim.config(base,args{:});
    ro = m; ro.profile = 'step'; ro.vCmd_mps = NaN;
    ro.wind_base_mps = 0; ro.wind_sin_amp = 0; ro.wind_gust_mps = 0;   % 平静气流(口径澄清)
    Rs = quad_sim.realism_run(c,ro);
    stepRows(end+1,:) = {id{1}, Rs.settleS, Rs.overshoot_mps, Rs.overshoot_pct, 1}; %#ok<AGROW>
    if isnan(Rs.settleS) || Rs.settleS > g.settleMax_s
        fails{end+1} = sprintf('G-R4: %s settle %.2f s > %.0f s',id{1},Rs.settleS,g.settleMax_s);
    end
    if Rs.overshoot_pct > g.overshootMax_pct
        fails{end+1} = sprintf('G-R4: %s overshoot %.2f%% > %.0f%%', ...
            id{1},Rs.overshoot_pct,g.overshootMax_pct);
    end
    if strcmp(id{1},'REF'), RsRef = Rs; else, RsTyp = Rs; end
end
% ---- G-R5 ----
if biasWear_pp > g.estWearMax_pp
    fails{end+1} = sprintf('G-R5: estimator bias wear %.3f pp > %.1f pp', ...
        biasWear_pp,g.estWearMax_pp);
end
% ---- G-R6 ----
detOK = isequal(E(iRERUN,:),E(1,:)) && isequal(Ehat(iRERUN,:),Ehat(1,:)) && ...
    isequal(dst(iRERUN,:),dst(1,:)) && isequal(bias(iRERUN,:),bias(1,:));
if ~detOK
    fails{end+1} = 'G-R6: RERUN not bitwise equal to REF';
end
% ---- 磨损表 CSV ----
rows = cell(nC*nS,15); ir = 0;
for ic = 1:nC
    [~,ib] = min(Epm(ic,:));
    for is = 1:nS
        ir = ir + 1;
        rows(ir,:) = {cells(ic).id, cells(ic).family, cells(ic).level, speeds(is), ...
            E(ic,is), Epm(ic,is), wear(ic,is), Ehat(ic,is), bias(ic,is), sat(ic,is), ...
            dst(ic,is), vc(ic,is), tEnd(ic,is), double(done(ic,is)), ...
            double(speeds(is)==speeds(ib))};
    end
end
T = cell2table(rows,'VariableNames',{'cell','family','level','speed_mps','E_wh', ...
    'E_per_m_Whpm','wear_pp','Ehat_wh','bias_pct','sat_duty','dist_m', ...
    'v_cruise_mps','t_end_s','completed','is_argmin'});
csv = fullfile(resDir,'quad_realism_wear.csv');
writetable(T,csv,'Encoding','UTF-8');
Ts = cell2table(stepRows,'VariableNames',{'cell','settle_s','overshoot_mps','overshoot_pct','ok'});
stepCsv = fullfile(resDir,'quad_realism_step.csv');
writetable(Ts,stepCsv,'Encoding','UTF-8');
% ---- 图组 C 素材(脚本同源导出) ----
fig = figure('Visible','off');
subplot(2,2,1); hold on;
plot(speeds,Epm(1,:),'-o','DisplayName','REF'); plot(speeds,Epm(iTYP,:),'-s','DisplayName','TYP');
grid on; xlabel('cruise v command (m/s)'); ylabel('E/m (Wh/m)');
title('trip energy per meter by strategy'); legend('Location','best');
subplot(2,2,2);
bar(mean(wear,2)); set(gca,'XTick',1:nC,'XTickLabel',{cells.id});
xtickangle(45); ylabel('mean wear (pp)'); title('delay x saturation x noise wear');
grid on;
subplot(2,2,3); hold on;
plot(RsRef.tLog,RsRef.vLog,'DisplayName','REF'); plot(RsTyp.tLog,RsTyp.vLog,'DisplayName','TYP');
grid on; xlabel('t (s)'); ylabel('v (m/s)');
title(sprintf('step 5->8 m/s (settle %.1f/%.1f s)',RsRef.settleS,RsTyp.settleS));
legend('Location','best');
subplot(2,2,4); hold on;
plot(speeds,bias(1,:),'-o','DisplayName','REF'); plot(speeds,bias(iTYP,:),'-s','DisplayName','TYP');
grid on; xlabel('cruise v (m/s)'); ylabel('P-hat bias (%)');
title('estimator re-calibration (C3/C7 report)'); legend('Location','best');
png = fullfile(resDir,'quad_realism_figC.png');
saveas(fig,png); close(fig);
gates = struct('bestRef_mps',bestRef,'bestTyp_mps',bestTyp, ...
    'gapRef_pp',gapRef_pp,'gapTyp_pp',gapTyp_pp,'marginWear_pp',marginWear_pp, ...
    'biasWear_pp',biasWear_pp,'contrast',contrast,'deterministic',detOK, ...
    'nearTieBand_pp',g.marginFloor_pp);
result = struct('pass',isempty(fails),'tier','smoke','rows',height(T), ...
    'csv',csv,'stepCsv',stepCsv,'png',png,'gates',gates,'failures',{fails});
if ~result.pass
    error('quad:RealismChecks','SMOKE FAIL (%d): %s | archive: %s', ...
        numel(fails),strjoin(fails,'; '),csv);
end
fprintf('realism smoke PASS (%d cells x %d strategies) -> %s\n',nC,nS,csv);
fprintf('G-R1 argmin REF %.0f == TYP %.0f | G-R2 margin wear %.3f pp (gap %.2f->%.2f) | G-R5 bias wear %.3f pp | det %d\n', ...
    bestRef,bestTyp,marginWear_pp,gapRef_pp,gapTyp_pp,biasWear_pp,detOK);
end
function d = local_fp_diff(a,b)
if numel(a) ~= numel(b), d = true; else, d = any(a~=b); end
end
