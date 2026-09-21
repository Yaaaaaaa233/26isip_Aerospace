function rows = run_q4_formal(chunkId, pass)
%Q39.RUN_Q4_FORMAL Q4 正式验收批分块执行(预注册定义见 q39.q4_opt)。
% 每臂经 q39.m7_metrics/m7_rows 记账(每臂 true/est/diff 三行), 增量写入
% results/q4_formal.csv(SMOKE 分块写 results/q4_smoke.csv, 不入门)。openloop 幕
% 另写批锚点 results/q4_anchor_l1.csv / q4_anchor_truth.csv(双口径开环超额)。
% 幂等键 = (chunk, pass, arm), 已存在则跳过(断点续跑)。每分块独立 MATLAB 会话
% 调用(R6 缓解):
%   matlab -batch "q39.paths_q1(); q39.run_q4_formal('F1A',1)"
if nargin < 2, pass = 1; end
[opt, c, arms] = q39.q4_opt(chunkId, pass);
isSmoke = strcmpi(chunkId, 'SMOKE');
root = fileparts(fileparts(mfilename('fullpath')));
resDir = fullfile(root, 'results');
if ~exist(resDir, 'dir'), mkdir(resDir); end
if isSmoke
    csv = fullfile(resDir, 'q4_smoke.csv');
else
    csv = fullfile(resDir, 'q4_formal.csv');
end
scn = w36.scenario('static', c);
rows = cell(0, 1);
for ia = 1:numel(arms)
    arm = arms{ia};
    if local_row_exists(csv, chunkId, pass, arm)
        fprintf('%s p%d %s already present, skip.\n', chunkId, pass, arm);
        continue;
    end
    t0 = tic;
    [log, info] = q39.run_algorithm(arm, scn, c, opt);
    runS = toc(t0);
    if isSmoke
        anchor = struct('excessOpenTrue', NaN, 'excessOpenEst', NaN, 'vStarAir', NaN);
    else
        anchor = local_load_anchor(resDir, csv, opt.estMode);
    end
    m = q39.m7_metrics(log, c, anchor);
    local_append(csv, chunkId, pass, arm, opt.estMode, m, runS);
    rows{end+1} = m; %#ok<AGROW>
    fprintf('%s p%d %s(%s) done: excess true/est = %.4f/%.4f%% (d=%.4fpp) rows=%d (%.1fs)\n', ...
        chunkId, pass, arm, opt.estMode, m.excess_true_pct, m.excess_est_pct, ...
        m.delta_excess_pp, m.rowsN, runS);
    if ~isSmoke && strcmpi(arm, 'openloop')
        local_write_anchor(resDir, opt.estMode, m, info.platTruth.vStarAir);
    end
end
if ~isSmoke
    fid = fopen(fullfile(resDir, ['chunk_q4_' lower(chunkId) '_p' num2str(pass) '.done']), 'w');
    fprintf(fid, 'done\n'); fclose(fid);
end
end

function hdr = local_header()
hdr = ['chunk,pass,arm,estMode,caliber,excess_pct,moe,margin_pp,delta_excess_pp,', ...
    'delta_margin_pp,bias_meas_pct,rowsN,runtime_s'];
end

function local_append(csv, chunkId, pass, arm, estMode, m, runS)
rf = q39.m7_rows(chunkId, arm, m, runS);
needHdr = exist(csv, 'file') ~= 2 || isempty(fileread(csv));
f = fopen(csv, 'a');
if f < 0, error('q39:RunQ4Formal', 'cannot open %s', csv); end
if needHdr
    fprintf(f, '%s\n', local_header());
end
for i = 1:numel(rf)
    fprintf(f, '%s,%d,%s,%s,%s,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%d,%.17g\n', ...
        chunkId, pass, arm, estMode, rf(i).caliber, rf(i).excess_pct, rf(i).moe, ...
        rf(i).margin_pp, rf(i).delta_excess_pp, rf(i).delta_margin_pp, ...
        rf(i).bias_meas_pct, rf(i).rowsN, rf(i).runtime_s);
end
fclose(f);
end

function tf = local_row_exists(csv, chunkId, pass, arm)
tf = false;
if exist(csv, 'file') ~= 2, return; end
txt = fileread(csv);
lines = regexp(txt, '\r?\n', 'split');
for i = 1:numel(lines)
    parts = strsplit(lines{i}, ',');
    if numel(parts) >= 5 && strcmp(parts{1}, chunkId) && ...
            str2double(parts{2}) == pass && strcmp(parts{3}, arm)
        tf = true; return;
    end
end
end

function anchor = local_load_anchor(resDir, csv, estMode)
% 开环参照: 优先批锚点文件; 缺失时从既有 CSV 的 openloop 行重建(断点续跑;
% 两遍逐位, 跨 pass 取值等价, 不等价会被 G4 逐位门拦住)
anchor = struct('excessOpenTrue', NaN, 'excessOpenEst', NaN, 'vStarAir', NaN);
if strcmp(estMode, 'l1')
    anchorFile = fullfile(resDir, 'q4_anchor_l1.csv');
else
    anchorFile = fullfile(resDir, 'q4_anchor_truth.csv');
end
if exist(anchorFile, 'file') == 2
    T = readtable(anchorFile, 'Delimiter', ',', 'ReadVariableNames', true);
    anchor.excessOpenTrue = T.excessOpenTrue(1);
    anchor.excessOpenEst = T.excessOpenEst(1);
    anchor.vStarAir = T.vStarAir(1);
elseif exist(csv, 'file') == 2
    T = readtable(csv, 'Delimiter', ',', 'ReadVariableNames', true);
    sel = strcmp(T.arm, 'openloop') & strcmp(T.estMode, estMode) & strcmp(T.caliber, 'true');
    if any(sel)
        anchor.excessOpenTrue = T.excess_pct(find(sel, 1));
    end
    sel = strcmp(T.arm, 'openloop') & strcmp(T.estMode, estMode) & strcmp(T.caliber, 'est');
    if any(sel)
        anchor.excessOpenEst = T.excess_pct(find(sel, 1));
    end
end
end

function local_write_anchor(resDir, estMode, m, vStarAir)
if strcmp(estMode, 'l1')
    anchorFile = fullfile(resDir, 'q4_anchor_l1.csv');
else
    anchorFile = fullfile(resDir, 'q4_anchor_truth.csv');
end
fid = fopen(anchorFile, 'w');
fprintf(fid, 'excessOpenTrue,excessOpenEst,vStarAir\n');
fprintf(fid, '%.17g,%.17g,%.17g\n', m.excess_true_pct, m.excess_est_pct, vStarAir);
fclose(fid);
fprintf('q4 anchor(%s) written: excessOpen true/est = %.6f/%.6f%% vStarAir=%.6f\n', ...
    estMode, m.excess_true_pct, m.excess_est_pct, vStarAir);
end
