function result = run_quad_p3_checks()
%RUN_QUAD_P3_CHECKS 建模调整方案 P3 算法验证验收(2026-10-11, 方案 §4.3)。
% 运行: cd models/plane_quad && run_quad_p3_checks
% 预注册单一事实源: +quad_sim/p3_opt(门槛先于数据冻结)。按 R6 单机 b40, TYP 典型
% 整链口径; 任务=240 s 定速巡航窗 + 三段相位风(头风4/静/顺风4), 谷随风移动。
% 门(全部硬断言, 失败携带归档路径退出):
%   G-P0 全臂完成窗口且能量有限
%   G-P1 双口径排序一致 + top 赢面漂移 <=1pp
%   G-P2 因果门: 策略信息面仅白名单字段(逐调用断言, 结构强制)
%   G-P3 RERUN 同会话逐位
%   G-P4 |s1|<=3% 或 |s2|<=0.7 档 sweepcal 赢面磨损 <=1pp(其余档=探针报告)
% 结果交付(不设门): 排序结论/MOE/赢面、E1 扩带真值扫描(谷存在+谷会动)、E4 控制代价。
root = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(root));
addpath(root); addpath(fullfile(repo,'models','px4_x8'));
resDir = fullfile(root,'results');
if ~exist(resDir,'dir'), mkdir(resDir); end
opt = quad_sim.p3_opt(); m = opt.mission; g = opt.gates; sN = opt.sens;
ro = quad_sim.realism_opt();
deg = ro.cells(strcmp({ro.cells.id},'TYP')).deg;      % P3 口径 = P2 典型整链
fn = fieldnames(deg); args = cell(1,2*numel(fn));
for k = 1:numel(fn), args{2*k-1} = fn{k}; args{2*k} = deg.(fn{k}); end
c = quad_sim.config(quad_sim.baseline('b40'),args{:},'est_model','l1');   % P3 估计口径=L1(§4.3 勘误)
nPh = numel(m.windPhases_mps); nV = numel(m.vGrid_mps);
fails = {};
% ---- 真值扫描: 3 风相位 x vGrid(60 s 定速窗, 尾 30 s 均值) ----
Ptrue = zeros(nPh,nV); Phest = zeros(nPh,nV);
for p = 1:nPh
    for iv = 1:nV
        runopt = struct('profile','window','maxTime_s',m.sweepT_s,'seed',m.seed, ...
            'wind_profile','phases','windPhases_mps',m.windPhases_mps(p), ...
            'phaseBounds_s',[0 m.sweepT_s], ...
            'vref_policy',quad_sim.p3_arm('const',m.vGrid_mps(iv)));
        R = quad_sim.realism_run(c,runopt);
        tail = R.tLog >= (m.sweepT_s-m.sweepTail_s);
        Ptrue(p,iv) = mean(R.PLog(tail));
        Phest(p,iv) = mean(R.PhatLog(tail));
    end
    [pmin,ivs] = min(Ptrue(p,:));
    vStar(p) = m.vGrid_mps(ivs); %#ok<AGROW> % min 第一输出是最小值不是索引(首评勘误)
    PminArr(p) = pmin; %#ok<AGROW>
    fprintf('phase %d (wind %+0.1f): P(v) = %s W | v*=%.0f m/s Pmin=%.1f W\n', ...
        p, m.windPhases_mps(p), sprintf('%6.1f ',Ptrue(p,:)), m.vGrid_mps(ivs), pmin);
end
map = struct('bounds_s',m.phaseBounds_s,'vStar',vStar);
% ---- 三臂 240 s 窗(TYP, 相位风) ----
armNames = {'openloop','sweepcal','known'};
E = zeros(1,3); Ehat = zeros(1,3); done = false(1,3); sat = zeros(1,3);
vTraces = cell(1,3); tTraces = cell(1,3);
for ia = 1:3
    % 每个运行格新建臂句柄(sweepcal 为有状态闭包, 复用会串状态)
    pol0 = local_armpol(ia,opt,map);
    pol = @(info) local_chk(info,pol0,g.policyFields);
    runopt = struct('profile','window','maxTime_s',m.T_s,'seed',m.seed, ...
        'wind_profile','phases','windPhases_mps',m.windPhases_mps, ...
        'phaseBounds_s',m.phaseBounds_s,'vref_policy',pol);
    R = quad_sim.realism_run(c,runopt);
    E(ia) = R.E_wh; Ehat(ia) = R.Ehat_wh; done(ia) = R.completed;
    sat(ia) = R.satDuty; vTraces{ia} = R.vLog; tTraces{ia} = R.tLog;
end
Emin = E(3); Ehmin = Ehat(3);
excess = 100*(E/Emin-1); excessHat = 100*(Ehat/Ehmin-1);
MOE = Emin./E; MOEhat = Ehmin./Ehat;
marginTrue = excess(1)-excess(2); marginHat = excessHat(1)-excessHat(2);
drift = abs(marginTrue-marginHat);
fprintf('arms E = %s Wh | excess = %s pp | margin(sweep vs open) = %+.3f pp (hat %+.3f)\n', ...
    sprintf('%7.2f ',E), sprintf('%6.2f ',excess), marginTrue, marginHat);
% ---- G-P0 ----
if ~all(done) || ~all(isfinite(E)) || ~all(isfinite(Ehat))
    fails{end+1} = sprintf('G-P0: incomplete/nonfinite arms (done=%s)',mat2str(done));
end
% ---- G-P1 双口径 ----
[~,rTrue] = sort(E); [~,rHat] = sort(Ehat);
if ~isequal(rTrue,rHat)
    fails{end+1} = sprintf('G-P1: ranking differs true %s vs hat %s', ...
        mat2str(rTrue),mat2str(rHat));
end
if drift > g.driftMax_pp
    fails{end+1} = sprintf('G-P1: margin drift %.3f pp > %.1f pp',drift,g.driftMax_pp);
end
% ---- G-P3 RERUN(openloop + sweepcal 同会话逐位) ----
detOK = true;
for ia = [1 2]
    pol0 = local_armpol(ia,opt,map);
    pol = @(info) local_chk(info,pol0,g.policyFields);
    runopt = struct('profile','window','maxTime_s',m.T_s,'seed',m.seed, ...
        'wind_profile','phases','windPhases_mps',m.windPhases_mps, ...
        'phaseBounds_s',m.phaseBounds_s,'vref_policy',pol);
    R = quad_sim.realism_run(c,runopt);
    if ~isequal(R.E_wh,E(ia)) || ~isequal(R.Ehat_wh,Ehat(ia)), detOK = false; end
end
if ~detOK, fails{end+1} = 'G-P3: RERUN not bitwise equal'; end
% ---- G-P4 敏感性(Q1 式叠差施于 P̂: P̂'=P̂*(1+(s1+s2*v)/100), 对地速) ----
sensRows = cell(0,6); wearGated = []; sensLabels = cell(0,1);
for kind = {'s1','s2'}
    if strcmp(kind{1},'s1'), lv = sN.s1_pct; else, lv = sN.s2_pct_mps; end
    for l = lv
        if strcmp(kind{1},'s1'), s1 = l; s2 = 0; else, s1 = 0; s2 = l; end
        pol0 = local_armpol(2,opt,map);
        pol = @(info) local_chk(info,pol0, ...
            g.policyFields,sN_overlay(s1,s2));
        runopt = struct('profile','window','maxTime_s',m.T_s,'seed',m.seed, ...
            'wind_profile','phases','windPhases_mps',m.windPhases_mps, ...
            'phaseBounds_s',m.phaseBounds_s,'vref_policy',pol);
        R = quad_sim.realism_run(c,runopt);
        margS = excess(1) - 100*(R.E_wh/Emin-1);
        wear = abs(margS-marginTrue);
        gated = (strcmp(kind{1},'s1') && abs(l) <= sN.gate_s1_pct) || ...
            (strcmp(kind{1},'s2') && abs(l) <= sN.gate_s2_pct_mps);
        if gated, wearGated(end+1) = wear; end %#ok<AGROW>
        sensRows(end+1,:) = {kind{1}, s1, s2, margS, wear, double(gated)}; %#ok<AGROW>
        sensLabels{end+1} = sprintf('%s%+g',kind{1},l); %#ok<AGROW>
        fprintf('sens %s=%+0.2f: margin %+.3f pp, wear %.3f pp%s\n', ...
            kind{1}, l, margS, wear, tern(gated,' [gated]',''));
    end
end
if any(wearGated > g.sensWearMax_pp)
    fails{end+1} = sprintf('G-P4: gated wear max %.3f pp > %.1f pp', ...
        max(wearGated),g.sensWearMax_pp);
end
% ---- CSV ----
sw = cell(nPh*nV,5); ir = 0;
for p = 1:nPh
    for iv = 1:nV
        ir = ir + 1;
        sw(ir,:) = {p, m.windPhases_mps(p), m.vGrid_mps(iv), Ptrue(p,iv), Phest(p,iv)};
    end
end
Tsw = cell2table(sw,'VariableNames',{'phase','wind_mps','v_mps','P_true_W','P_hat_W'});
csv1 = fullfile(resDir,'quad_p3_sweep.csv'); writetable(Tsw,csv1,'Encoding','UTF-8');
Ta = cell2table([armNames(:), num2cell(E(:)), num2cell(Ehat(:)), ...
    num2cell(excess(:)), num2cell(excessHat(:)), num2cell(MOE(:)), ...
    num2cell(MOEhat(:)), num2cell(sat(:)), num2cell(double(done(:)))], ...
    'VariableNames',{'arm','E_wh','Ehat_wh','excess_true_pp','excess_hat_pp', ...
    'MOE_true','MOE_hat','sat_duty','completed'});
csv2 = fullfile(resDir,'quad_p3_arms.csv'); writetable(Ta,csv2,'Encoding','UTF-8');
Ts = cell2table(sensRows,'VariableNames',{'kind','s1_pct','s2_pct_mps', ...
    'margin_pp','wear_pp','gated'});
csv3 = fullfile(resDir,'quad_p3_sens.csv'); writetable(Ts,csv3,'Encoding','UTF-8');
% ---- 图(P3 素材, 脚本同源导出) ----
fig = figure('Visible','off');
subplot(2,2,1); hold on;
for p = 1:nPh
    plot(m.vGrid_mps,Ptrue(p,:),'-o','DisplayName',sprintf('wind %+.0f',m.windPhases_mps(p)));
    [~,ivs] = min(Ptrue(p,:));
    plot(m.vGrid_mps(ivs),Ptrue(p,ivs),'kp','HandleVisibility','off');
end
grid on; xlabel('v (m/s)'); ylabel('P_{true} tail (W)');
title(sprintf('valley exists and moves (v*=%s)',mat2str(vStar)));
legend('Location','best');
subplot(2,2,2); bar(E); set(gca,'XTickLabel',armNames);
ylabel('E_{240s} (Wh)'); title(sprintf('arms (margin sweep-vs-open %+.2f pp)',marginTrue));
grid on;
subplot(2,2,3); hold on;
for ia = 1:3, plot(tTraces{ia},vTraces{ia},'DisplayName',armNames{ia}); end
grid on; xlabel('t (s)'); ylabel('v (m/s)'); title('achieved speed (sweepcal probing)');
legend('Location','best');
subplot(2,2,4);
bar([sensRows{:,5}]); hold on;
plot([0 size(sensRows,1)+1],[g.sensWearMax_pp g.sensWearMax_pp],'r--');
set(gca,'XTick',1:size(sensRows,1),'XTickLabel',sensLabels);
xtickangle(45); ylabel('margin wear (pp)'); title('estimator-error sensitivity'); grid on;
png = fullfile(resDir,'quad_p3_fig.png'); saveas(fig,png); close(fig);
gates = struct('vStar',vStar,'marginTrue_pp',marginTrue,'marginHat_pp',marginHat, ...
    'drift_pp',drift,'detOK',detOK,'wearGatedMax_pp',max([wearGated 0]));
result = struct('pass',isempty(fails),'tier','smoke', ...
    'csv',csv1,'armsCsv',csv2,'sensCsv',csv3,'png',png,'gates',gates,'failures',{fails});
if ~result.pass
    error('quad:P3Checks','P3 FAIL (%d): %s | archive: %s', ...
        numel(fails),strjoin(fails,'; '),csv2);
end
fprintf('P3 PASS: v*=%s | margin %+.3f pp (drift %.3f) | gated wear max %.3f pp | det %d -> %s\n', ...
    mat2str(vStar),marginTrue,drift,max([wearGated 0]),detOK,csv2);
end
function pol = local_armpol(ia,opt,map)
switch ia
    case 1, pol = quad_sim.p3_arm('openloop',opt.arms.openloop_v);
    case 2, pol = quad_sim.p3_arm('sweepcal',opt.arms.sweepcal);
    case 3, pol = quad_sim.p3_arm('known',map);
    otherwise, error('quad:P3Checks','Unknown arm index %d',ia);
end
end
function v = local_chk(info,pol,fields,ov)
assert(isequal(sort(fieldnames(info)),sort(fields(:))), ...
    'quad:P3Causality','policy info face has non-whitelist fields.');
if nargin >= 4 && ~isempty(ov)
    info.Phat = info.Phat*(1+(ov(1)+ov(2)*info.v)/100);
end
v = pol(info);
end
function ov = sN_overlay(s1,s2), ov = [s1 s2]; end
function s = tern(c,a,b), if c, s = a; else, s = b; end, end
