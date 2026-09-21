function rows = run_q3_smoke(chunkId)
%Q39.RUN_Q3_SMOKE Q3 集成冒烟分块(QUAD_MIGRATION_PLAN 20260921 §4-Q3/§5-M7):
% L1 估计链接入后 3600s 幕的双口径记账。臂 = {openloop, sweepcal, purerl_off,
% purerl_on}(对齐 Q1/S3 对比集 + 开环参照), estMode='l1', 其余场景口径与 Q1
% 共性一致(platform / seed 11 / 3600s / tailSteps 60 / composite B=2.5 s=0.3)。
% 对比读数(既有归档, 不重跑): Q1/S3 同臂 l0 口径 sweepcal 超额 17.92%(margin
% -11.65pp 崩溃), ANCHOR 真值口径 sweepcal 4.02%——Q3 验证 L1 接入后恢复真值
% 口径水平, 且 M7 差值列量化估计口径结论漂移。
% 增量写 results/q3_dual_caliber.csv(每臂 true/est/diff 三行, 幂等可断点续跑)与
% results/q3_anchor.csv(openloop 双口径超额参照)。独立 MATLAB 会话调用(R6 缓解):
%   matlab -batch "q39.paths_q1(); q39.run_q3_smoke('SMOKE')"
if nargin < 1, chunkId = 'SMOKE'; end
assert(strcmpi(chunkId, 'SMOKE'), 'q39:RunQ3Smoke', 'Unknown chunk id: %s', chunkId);
root = fileparts(fileparts(mfilename('fullpath')));
resDir = fullfile(root, 'results');
if ~exist(resDir, 'dir'), mkdir(resDir); end
opt = struct('estMode','l1','s1_pct',0,'s2_pct_mps',0,'s4_vpct',0,...
    'dwell_s',0,'pretrainCache',false);
opt.arms = {};   % struct() 收到空 cell 会生成 0x0 空结构体, 必须后补字段
opt.decl = [];   % L1 声明系数 = 配置自身(声明上界档)
c = w36.config('backend','platform','seed',11,'evalSeconds',3600,'tailSteps',60,...
    'windKind','composite','windBias',2.5,'windAmp',0,'windAmpY',0,'turbStd',0.3);
arms = {'openloop','sweepcal','purerl_off','purerl_on'};
csv = fullfile(resDir, 'q3_dual_caliber.csv');
anchorFile = fullfile(resDir, 'q3_anchor.csv');
scn = w36.scenario('static', c);
rows = cell(0, 1); armDone = {}; vStarAir = NaN;
for ia = 1:numel(arms)
    arm = arms{ia};
    if local_row_exists(csv, chunkId, arm)
        fprintf('%s %s already present, skip.\n', chunkId, arm);
        [m, runS] = local_row_vals(csv, chunkId, arm);
        rows{end+1} = m; armDone{end+1} = arm; %#ok<AGROW>
        continue;
    end
    t0 = tic;
    [log, info] = q39.run_algorithm(arm, scn, c, opt);
    runS = toc(t0);
    vStarAir = info.platTruth.vStarAir;
    anchor = local_load_anchor(anchorFile, csv);
    m = q39.m7_metrics(log, c, anchor);
    local_append(csv, chunkId, arm, m, runS);
    rows{end+1} = m; armDone{end+1} = arm; %#ok<AGROW>
    fprintf('%s %s done: excess true/est = %.4f/%.4f%% (d=%.4fpp) margin true/est = %.4f/%.4fpp (%.1fs)\n', ...
        chunkId, arm, m.excess_true_pct, m.excess_est_pct, m.delta_excess_pp, ...
        m.margin_true_pp, m.margin_est_pp, runS);
    if strcmpi(arm, 'openloop')
        local_write_anchor(anchorFile, m, vStarAir);
    end
end
fid = fopen(fullfile(resDir, 'chunk_q3smoke.done'), 'w');
fprintf(fid, 'done\n'); fclose(fid);
end

function hdr = local_header()
hdr = ['chunk,arm,caliber,excess_pct,moe,margin_pp,delta_excess_pp,', ...
    'delta_margin_pp,bias_meas_pct,rowsN,runtime_s'];
end

function local_append(csv, chunkId, arm, m, runS)
rf = q39.m7_rows(chunkId, arm, m, runS);
needHdr = exist(csv, 'file') ~= 2 || isempty(fileread(csv));
f = fopen(csv, 'a');
if f < 0, error('q39:RunQ3Smoke', 'cannot open %s', csv); end
if needHdr
    fprintf(f, '%s\n', local_header());
end
for i = 1:numel(rf)
    fprintf(f, '%s,%s,%s,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%d,%.17g\n', ...
        rf(i).chunk, rf(i).arm, rf(i).caliber, rf(i).excess_pct, rf(i).moe, ...
        rf(i).margin_pp, rf(i).delta_excess_pp, rf(i).delta_margin_pp, ...
        rf(i).bias_meas_pct, rf(i).rowsN, rf(i).runtime_s);
end
fclose(f);
end

function tf = local_row_exists(csv, chunkId, arm)
tf = false;
if exist(csv, 'file') ~= 2, return; end
txt = fileread(csv);
lines = regexp(txt, '\r?\n', 'split');
for i = 1:numel(lines)
    parts = strsplit(lines{i}, ',');
    if numel(parts) >= 2 && strcmp(parts{1}, chunkId) && strcmp(parts{2}, arm)
        tf = true; return;
    end
end
end

function [m, runS] = local_row_vals(csv, chunkId, arm)
% 断点续跑: 已有行回读成 metrics 结构(锚点重建用)
m = struct('excess_true_pct',NaN,'excess_est_pct',NaN,'delta_excess_pp',NaN,...
    'moe_true',NaN,'moe_est',NaN,'margin_true_pp',NaN,'margin_est_pp',NaN,...
    'delta_margin_pp',NaN,'bias_meas_pct',NaN,'rowsN',NaN);
runS = NaN;
T = readtable(csv, 'Delimiter', ',', 'ReadVariableNames', true);
sel = strcmp(T.chunk, chunkId) & strcmp(T.arm, arm);
r = T(sel, :);
if height(r) ~= 3, return; end
for i = 1:height(r)
    switch r.caliber{i}
        case 'true', m.excess_true_pct = r.excess_pct(i); m.moe_true = r.moe(i); m.margin_true_pp = r.margin_pp(i);
        case 'est',  m.excess_est_pct = r.excess_pct(i);  m.moe_est = r.moe(i);  m.margin_est_pp = r.margin_pp(i);
        case 'diff', m.delta_excess_pp = r.excess_pct(i); m.delta_margin_pp = r.margin_pp(i);
    end
end
m.bias_meas_pct = r.bias_meas_pct(1);
m.rowsN = r.rowsN(1);
runS = r.runtime_s(1);
end

function anchor = local_load_anchor(anchorFile, csv)
% 开环参照: 优先锚点文件; 缺失时从既有 CSV 的 openloop 行重建(断点续跑)
anchor = struct('excessOpenTrue', NaN, 'excessOpenEst', NaN, 'vStarAir', NaN);
if exist(anchorFile, 'file') == 2
    T = readtable(anchorFile, 'Delimiter', ',', 'ReadVariableNames', true);
    anchor.excessOpenTrue = T.excessOpenTrue(1);
    anchor.excessOpenEst = T.excessOpenEst(1);
    anchor.vStarAir = T.vStarAir(1);
elseif exist(csv, 'file') == 2
    T = readtable(csv, 'Delimiter', ',', 'ReadVariableNames', true);
    sel = strcmp(T.arm, 'openloop') & strcmp(T.caliber, 'true');
    if any(sel)
        anchor.excessOpenTrue = T.excess_pct(find(sel, 1));
    end
    sel = strcmp(T.arm, 'openloop') & strcmp(T.caliber, 'est');
    if any(sel)
        anchor.excessOpenEst = T.excess_pct(find(sel, 1));
    end
end
end

function local_write_anchor(anchorFile, m, vStarAir)
fid = fopen(anchorFile, 'w');
fprintf(fid, 'excessOpenTrue,excessOpenEst,vStarAir\n');
fprintf(fid, '%.17g,%.17g,%.17g\n', m.excess_true_pct, m.excess_est_pct, vStarAir);
fclose(fid);
fprintf('q3 anchor written: excessOpen true/est = %.6f/%.6f%% vStarAir=%.6f\n', ...
    m.excess_true_pct, m.excess_est_pct, vStarAir);
end
