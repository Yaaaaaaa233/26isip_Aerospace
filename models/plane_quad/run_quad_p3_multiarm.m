function result = run_quad_p3_multiarm(estMode, smoke)
%RUN_QUAD_P3_MULTIARM 多臂适配对比批(2026-10-15, 预注册 +quad_sim/p3_multiarm_opt)。
% 运行: cd models/plane_quad && run_quad_p3_multiarm          % vi 主档(R8③)
%       run_quad_p3_multiarm('l1')                           % l1 档对照
%       run_quad_p3_multiarm('vi', true)                     % 冒烟(新臂 60 s 小窗)
% 臂(8): openloop/sweepcal/hybrid/rl/purerl/purerl_on/purerl_off/known——
%   Q 系臂(w36)适配进 p3_arm 框架, 同链同窗同信息面互比(p3_multiarm_opt)。
% 门槛(取 p3_opt.gates 同值, 门槛不动):
%   G-P0 全臂完成窗口且能量有限
%   G-P1 双口径排序一致 + top 赢面漂移 <=1pp(赢面=sweepcal-vs-openloop, 同 P3 定义)
%   G-P2 因果门: 策略信息面仅白名单字段(逐调用断言, 结构强制)
%   G-P3 RERUN 同会话逐位(覆盖扩到全部臂, 低成本扩展)
%   G-P4 |s1|<=3% 或 |s2|<=0.7 档 sweepcal 赢面磨损 <=1pp(其余档=探针报告;
%         新臂门内档加报磨损行, 不设门——openloop/known/purerl_off 不读 P̂ 免跑)
% 结果交付(不设门): 排序/MOE/赢面、试飞预训练账(额外试飞预算声明)、v 轨迹。
root = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(root));
addpath(root); addpath(fullfile(repo,'models','px4_x8'));
resDir = fullfile(root,'results');
if ~exist(resDir,'dir'), mkdir(resDir); end
if nargin < 1, estMode = 'vi'; end
if nargin < 2, smoke = false; end
po = quad_sim.p3_multiarm_opt(); m = po.mission;
p0 = quad_sim.p3_opt(); g = p0.gates; sN = p0.sens;
ro = quad_sim.realism_opt();
deg = ro.cells(strcmp({ro.cells.id},'TYP')).deg;
fn = fieldnames(deg); args = cell(1,2*numel(fn));
for k = 1:numel(fn), args{2*k-1} = fn{k}; args{2*k} = deg.(fn{k}); end
c = quad_sim.config(quad_sim.baseline('b40'),args{:},'est_model',estMode);
fails = {};
if smoke
    % ---- 冒烟: 新臂 60 s 小窗(静风), 完成/有限/白名单 ----
    W = quad_sim.p3_warmup(c,struct('T_s',120,'seed',m.seed+17));
    for name = {'hybrid','rl','purerl','purerl_on','purerl_off'}
        pol0 = local_armpol(name{1},po,[],W);
        pol = @(info) local_chk(info,pol0,g.policyFields);
        runopt = struct('profile','window','maxTime_s',60,'seed',m.seed, ...
            'wind_profile','phases','windPhases_mps',0, ...
            'phaseBounds_s',[0 60],'vref_policy',pol);
        R = quad_sim.realism_run(c,runopt);
        fprintf('smoke %-10s done=%d E=%.3f Wh\n',name{1},R.completed,R.E_wh);
        if ~R.completed || ~isfinite(R.E_wh)
            fails{end+1} = sprintf('smoke %s incomplete/nonfinite',name{1}); %#ok<AGROW>
        end
    end
    result = struct('pass',isempty(fails),'tier','smoke','failures',{fails});
    if ~result.pass
        error('quad:P3Multiarm','MULTIARM SMOKE FAIL: %s',strjoin(fails,'; '));
    end
    fprintf('multiarm smoke PASS\n');
    return;
end
% ---- 真值扫描: 3 风相位 x vGrid(60 s 定速窗, 尾 30 s 均值) ----
nPh = numel(m.windPhases_mps); nV = numel(m.vGrid_mps);
Ptrue = zeros(nPh,nV); Phest = zeros(nPh,nV); vStar = zeros(1,nPh);
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
    [~,ivs] = min(Ptrue(p,:));
    vStar(p) = m.vGrid_mps(ivs);
    fprintf('phase %d (wind %+0.1f): v*=%.0f m/s Pmin=%.1f W\n', ...
        p, m.windPhases_mps(p), vStar(p), min(Ptrue(p,:)));
end
map = struct('bounds_s',m.phaseBounds_s,'vStar',vStar);
% ---- 试飞预训练(purerl_on/off 共用; 额外试飞预算, 不占任务窗) ----
W = quad_sim.p3_warmup(c,struct('T_s',po.warmup.T_s, ...
    'seed',m.seed+po.warmup.seedOffset,'dwell_s',po.warmup.dwell_s, ...
    'tail_s',po.warmup.tail_s));
% ---- 8 臂 240 s 窗 ----
armNames = po.arms; nA = numel(armNames);
E = zeros(1,nA); Ehat = zeros(1,nA); done = false(1,nA); sat = zeros(1,nA);
vTraces = cell(1,nA); tTraces = cell(1,nA);
for ia = 1:nA
    pol0 = local_armpol(armNames{ia},po,map,W);
    pol = @(info) local_chk(info,pol0,g.policyFields);
    runopt = struct('profile','window','maxTime_s',m.T_s,'seed',m.seed, ...
        'wind_profile','phases','windPhases_mps',m.windPhases_mps, ...
        'phaseBounds_s',m.phaseBounds_s,'vref_policy',pol);
    R = quad_sim.realism_run(c,runopt);
    E(ia) = R.E_wh; Ehat(ia) = R.Ehat_wh; done(ia) = R.completed;
    sat(ia) = R.satDuty; vTraces{ia} = R.vLog; tTraces{ia} = R.tLog;
    fprintf('arm %-10s E=%7.3f Wh Ehat=%7.3f Wh done=%d\n', ...
        armNames{ia},E(ia),Ehat(ia),done(ia));
end
iSweep = find(strcmp(armNames,'sweepcal'),1);
iOpen = find(strcmp(armNames,'openloop'),1);
iKnown = find(strcmp(armNames,'known'),1);
Emin = E(iKnown); Ehmin = Ehat(iKnown);
excess = 100*(E/Emin-1); excessHat = 100*(Ehat/Ehmin-1);
MOE = Emin./E; MOEhat = Ehmin./Ehat;
marginTrue = excess(iOpen)-excess(iSweep);
marginHat = excessHat(iOpen)-excessHat(iSweep);
drift = abs(marginTrue-marginHat);
% ---- G-P0 ----
if ~all(done) || ~all(isfinite(E)) || ~all(isfinite(Ehat))
    fails{end+1} = sprintf('G-P0: incomplete/nonfinite arms (done=%s)',mat2str(done));
end
% ---- G-P1 双口径排序 ----
[~,rTrue] = sort(E); [~,rHat] = sort(Ehat);
if ~isequal(rTrue,rHat)
    fails{end+1} = sprintf('G-P1: ranking differs true %s vs hat %s', ...
        mat2str(rTrue),mat2str(rHat));
end
if drift > g.driftMax_pp
    fails{end+1} = sprintf('G-P1: margin drift %.3f pp > %.1f pp',drift,g.driftMax_pp);
end
% ---- G-P3 RERUN(全部臂, 同会话逐位) ----
detOK = true;
for ia = 1:nA
    pol0 = local_armpol(armNames{ia},po,map,W);
    pol = @(info) local_chk(info,pol0,g.policyFields);
    runopt = struct('profile','window','maxTime_s',m.T_s,'seed',m.seed, ...
        'wind_profile','phases','windPhases_mps',m.windPhases_mps, ...
        'phaseBounds_s',m.phaseBounds_s,'vref_policy',pol);
    R = quad_sim.realism_run(c,runopt);
    if ~isequal(R.E_wh,E(ia)) || ~isequal(R.Ehat_wh,Ehat(ia)), detOK = false; end
end
if ~detOK, fails{end+1} = 'G-P3: RERUN not bitwise equal'; end
% ---- G-P4 敏感性(P̂ 叠差 P̂'=P̂*(1+(s1+s2*v)/100), 对地速) ----
% sweepcal: 全 8 档(预注册套件, 门=|s1|<=3 或 |s2|<=0.7);
% 新臂(读 P̂ 的 hybrid/rl/purerl/purerl_on): 门内 4 档加报, 不设门。
sensRows = cell(0,7); wearGated = []; sensLabels = cell(0,1);
sensArms = [{'sweepcal'}, armNames(strcmp(armNames,'hybrid') | ...
    strcmp(armNames,'rl') | strcmp(armNames,'purerl') | strcmp(armNames,'purerl_on'))];
for ia = 1:numel(sensArms)
    nm = sensArms{ia};
    if strcmp(nm,'sweepcal'), lv1 = sN.s1_pct; lv2 = sN.s2_pct_mps;
    else
        lv1 = sN.s1_pct(abs(sN.s1_pct) <= sN.gate_s1_pct);
        lv2 = sN.s2_pct_mps(abs(sN.s2_pct_mps) <= sN.gate_s2_pct_mps);
    end
    for kind = {'s1','s2'}
        if strcmp(kind{1},'s1'), lv = lv1; else, lv = lv2; end
        for l = lv
            if strcmp(kind{1},'s1'), s1 = l; s2 = 0; else, s1 = 0; s2 = l; end
            pol0 = local_armpol(nm,po,map,W);
            pol = @(info) local_chk(info,pol0,g.policyFields,sN_overlay(s1,s2));
            runopt = struct('profile','window','maxTime_s',m.T_s,'seed',m.seed, ...
                'wind_profile','phases','windPhases_mps',m.windPhases_mps, ...
                'phaseBounds_s',m.phaseBounds_s,'vref_policy',pol);
            R = quad_sim.realism_run(c,runopt);
            margS = excess(iOpen) - 100*(R.E_wh/Emin-1);
            iArm = find(strcmp(armNames,nm),1);
            wear = abs(margS-(excess(iOpen)-excess(iArm)));
            gated = strcmp(nm,'sweepcal') && ...
                ((strcmp(kind{1},'s1') && abs(l) <= sN.gate_s1_pct) || ...
                 (strcmp(kind{1},'s2') && abs(l) <= sN.gate_s2_pct_mps));
            if gated, wearGated(end+1) = wear; end %#ok<AGROW>
            sensRows(end+1,:) = {nm, kind{1}, s1, s2, margS, wear, double(gated)}; %#ok<AGROW>
            sensLabels{end+1} = sprintf('%s %s%+g',nm,kind{1},l); %#ok<AGROW>
            fprintf('sens %-10s %s=%+0.2f: margin %+.3f pp, wear %.3f pp%s\n', ...
                nm,kind{1},l,margS,wear,tern(gated,' [gated]',''));
        end
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
sfx = ['_' estMode];
csv1 = fullfile(resDir,['quad_p3_ma_sweep' sfx '.csv']); writetable(Tsw,csv1,'Encoding','UTF-8');
Ta = cell2table([armNames(:), num2cell(E(:)), num2cell(Ehat(:)), ...
    num2cell(excess(:)), num2cell(excessHat(:)), num2cell(MOE(:)), ...
    num2cell(MOEhat(:)), num2cell(sat(:)), num2cell(double(done(:)))], ...
    'VariableNames',{'arm','E_wh','Ehat_wh','excess_true_pp','excess_hat_pp', ...
    'MOE_true','MOE_hat','sat_duty','completed'});
csv2 = fullfile(resDir,['quad_p3_ma_arms' sfx '.csv']); writetable(Ta,csv2,'Encoding','UTF-8');
Ts = cell2table(sensRows,'VariableNames',{'arm','kind','s1_pct','s2_pct_mps', ...
    'margin_pp','wear_pp','gated'});
csv3 = fullfile(resDir,['quad_p3_ma_sens' sfx '.csv']); writetable(Ts,csv3,'Encoding','UTF-8');
Tw = cell2table({W.mu,W.bBase,W.sigma,W.kStep,W.T_s,W.E_wh,double(W.completed), ...
    po.warmup.windPhases_mps}, 'VariableNames',{'mu','bBase','sigma','kStep', ...
    'warmT_s','warmE_wh','completed','warmWind_mps'});
csv4 = fullfile(resDir,['quad_p3_ma_warm' sfx '.csv']); writetable(Tw,csv4,'Encoding','UTF-8');
% ---- 图 ----
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
subplot(2,2,2); bar(E); set(gca,'XTick',1:nA,'XTickLabel',armNames,'XTickLabelRotation',45);
ylabel('E_{240s} (Wh)'); title(sprintf('arms (margin sweep-vs-open %+.2f pp)',marginTrue));
grid on;
subplot(2,2,3); hold on;
for ia = 1:nA, plot(tTraces{ia},vTraces{ia},'DisplayName',armNames{ia}); end
grid on; xlabel('t (s)'); ylabel('v (m/s)'); title('achieved speed');
legend('Location','best');
subplot(2,2,4);
bar([sensRows{:,6}]); hold on;
plot([0 size(sensRows,1)+1],[g.sensWearMax_pp g.sensWearMax_pp],'r--');
set(gca,'XTick',1:size(sensRows,1),'XTickLabel',sensLabels);
xtickangle(45); ylabel('margin wear (pp)'); title('estimator-error sensitivity'); grid on;
png = fullfile(resDir,['quad_p3_ma_fig' sfx '.png']); saveas(fig,png); close(fig);
gates = struct('vStar',vStar,'marginTrue_pp',marginTrue,'marginHat_pp',marginHat, ...
    'drift_pp',drift,'detOK',detOK,'wearGatedMax_pp',max([wearGated 0]), ...
    'rankTrue',rTrue,'rankHat',rHat);
result = struct('pass',isempty(fails),'tier','multiarm', ...
    'csv',csv1,'armsCsv',csv2,'sensCsv',csv3,'warmCsv',csv4,'png',png, ...
    'arms',{armNames},'E',E,'Ehat',Ehat,'warm',W,'gates',gates,'failures',{fails});
if ~result.pass
    error('quad:P3Multiarm','MULTIARM FAIL (%d): %s | archive: %s', ...
        numel(fails),strjoin(fails,'; '),csv2);
end
fprintf('MULTIARM PASS (%s): E = %s Wh | margin %+.3f pp (drift %.3f) | gated wear max %.3f pp | det %d -> %s\n', ...
    estMode,sprintf('%.2f ',E),marginTrue,drift, ...
    max([wearGated 0]),detOK,csv2);
end
function pol = local_armpol(nm,po,map,W)
switch nm
    case 'openloop', pol = quad_sim.p3_arm('openloop',8);   % p3_opt.arms.openloop_v(先验)
    case 'sweepcal', pol = quad_sim.p3_arm('sweepcal',p3_opt_sweepcal());
    case 'hybrid',   pol = quad_sim.p3_arm('hybrid',po.hybrid);
    case 'rl',       pol = quad_sim.p3_arm('rl',po.rl);
    case 'purerl',   pol = quad_sim.p3_arm('purerl',po.purerl);
    case 'purerl_on', pol = quad_sim.p3_arm('purerl_on',W);
    case 'purerl_off', pol = quad_sim.p3_arm('purerl_off',W);
    case 'known',    pol = quad_sim.p3_arm('known',map);
    otherwise, error('quad:P3Multiarm','Unknown arm %s',nm);
end
end
function o = p3_opt_sweepcal()
p0 = quad_sim.p3_opt(); o = p0.arms.sweepcal;   % 原 P3 冻结参数, 不动
end
function v = local_chk(info,pol,fields,ov)
assert(isequal(sort(fieldnames(info)),sort(fields(:))), ...
    'quad:P3Multiarm','policy info face has non-whitelist fields.');
if nargin >= 4 && ~isempty(ov)
    info.Phat = info.Phat*(1+(ov(1)+ov(2)*info.v)/100);
end
v = pol(info);
end
function ov = sN_overlay(s1,s2), ov = [s1 s2]; end
function s = tern(c,a,b), if c, s = a; else, s = b; end, end
