function rows = run_q1_chunk(chunkId)
%Q39.RUN_Q1_CHUNK 执行一个预注册分块(一个场景档 x 若干臂), 结果增量写入
% results/q1_matrix.csv(%.17g 保证 M5 逐位比对可回读), 完成后写 results/chunk_<id>.done。
% ANCHOR 幕额外写 results/anchor.csv(开环/known 参照 + 真值谷底), 供后续幕计算
% margin 与 duStarFit。RERUN 幕额外执行 M5: 与 S3 行逐位比对(== 全字段)并写
% results/m5_bitwise.csv。
% 每个分块独立 MATLAB 会话调用(R6 缓解): matlab -batch "run_q1_matrix('<id>')"。
root = fileparts(fileparts(mfilename('fullpath')));
resDir = fullfile(root, 'results');
if ~exist(resDir, 'dir'), mkdir(resDir); end
[opt, c, arms] = q39.q1_opt(chunkId);
csv = fullfile(resDir, 'q1_matrix.csv');
anchorFile = fullfile(resDir, 'anchor.csv');
anchor = local_load_anchor(anchorFile);
scn = w36.scenario('static', c);
rows = cell(0, 1); armDone = {}; vStarAir = NaN;
for ia = 1:numel(arms)
    arm = arms{ia};
    if local_row_exists(csv, chunkId, arm)
        fprintf('%s %s already present, skip.\n', chunkId, arm);
        continue;
    end
    t0 = tic;
    [log, info] = q39.run_algorithm(arm, scn, c, opt);
    runS = toc(t0);
    vStarAir = info.platTruth.vStarAir;
    m = q39.q1_metrics(log, info, c, anchor);
    needHdr = exist(csv, 'file') ~= 2 || isempty(fileread(csv));
    f = fopen(csv, 'a');
    if f < 0, error('q39:RunQ1Chunk', 'cannot open %s', csv); end
    if needHdr
        fprintf(f, '%s\n', local_header());
    end
    fprintf(f, '%s,%s,%s,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%d,%.3f\n', ...
        chunkId, arm, opt.estMode, opt.s1_pct, opt.s2_pct_mps, opt.s4_vpct, ...
        opt.dwell_s, m.excess_true_pct, m.moe_true, m.margin_pp, m.bias_meas_pct, ...
        m.uOpTail, m.uStarFit, m.duStarFit, m.windErr, m.rowsN, runS);
    fclose(f);
    rows{end+1} = m; %#ok<AGROW>
    armDone{end+1} = arm; %#ok<AGROW>
    fprintf('%s %s done: excess=%.4f%% margin=%.4fpp bias=%.4f%% uStar=%.4f (%.1fs)\n', ...
        chunkId, arm, m.excess_true_pct, m.margin_pp, m.bias_meas_pct, m.uStarFit, runS);
end
if strcmpi(chunkId, 'ANCHOR') && ~isempty(rows)
    local_write_anchor(anchorFile, armDone, rows, vStarAir);
end
if strcmpi(chunkId, 'RERUN')
    local_m5_bitwise(csv, resDir);
end
fid = fopen(fullfile(resDir, ['chunk_' lower(chunkId) '.done']), 'w');
fprintf(fid, 'done\n'); fclose(fid);
end

function hdr = local_header()
hdr = ['chunk,arm,estMode,s1_pct,s2_pct_mps,s4_vpct,dwell_s,excess_true_pct,', ...
    'moe_true,margin_pp,bias_meas_pct,uOpTail,uStarFit,duStarFit,windErr,rowsN,runtime_s'];
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

function anchor = local_load_anchor(anchorFile)
anchor = struct('excessOpen', NaN, 'moeOpen', NaN, 'vStarAir', NaN);
if exist(anchorFile, 'file') == 2
    T = readtable(anchorFile, 'Delimiter', ',', 'ReadVariableNames', true);
    anchor.excessOpen = T.excessOpen(1);
    anchor.moeOpen = T.moeOpen(1);
    anchor.vStarAir = T.vStarAir(1);
end
end

function local_write_anchor(anchorFile, arms, rows, vStarAir)
exOpen = NaN; moeOpen = NaN;
for i = 1:numel(arms)
    if strcmp(arms{i}, 'openloop')
        exOpen = rows{i}.excess_true_pct;
        moeOpen = rows{i}.moe_true;
    end
end
fid = fopen(anchorFile, 'w');
fprintf(fid, 'excessOpen,moeOpen,vStarAir\n');
fprintf(fid, '%.17g,%.17g,%.17g\n', exOpen, moeOpen, vStarAir);
fclose(fid);
fprintf('anchor written: excessOpen=%.6f%% vStarAir=%.6f\n', exOpen, vStarAir);
end

function n = local_m5_bitwise(csv, resDir)
% M5: RERUN 幕与 S3 幕逐字段精确比较(%.17g 往返不丢位)
T = readtable(csv, 'Delimiter', ',', 'ReadVariableNames', true, 'ReadRowNames', false);
s3 = T(strcmp(T.chunk, 'S3'), :);
re = T(strcmp(T.chunk, 'RERUN'), :);
numCols = {'s1_pct','s2_pct_mps','s4_vpct','dwell_s','excess_true_pct','moe_true', ...
    'margin_pp','bias_meas_pct','uOpTail','uStarFit','duStarFit','windErr','rowsN'};
ok = height(s3) == height(re) && height(s3) > 0;
detail = cell(0, 1);
if ok
    for i = 1:height(s3)
        if ~strcmp(s3.arm{i}, re.arm{i}), ok = false; detail{end+1} = 'arm order mismatch'; end
        for kc = 1:numel(numCols)
            a = s3.(numCols{kc})(i); b = re.(numCols{kc})(i);
            if ~(isnan(a) && isnan(b)) && a ~= b
                ok = false;
                detail{end+1} = sprintf('%s %s %s: %.17g vs %.17g', ...
                    'RERUN', s3.arm{i}, numCols{kc}, a, b);
            end
        end
    end
end
fid = fopen(fullfile(resDir, 'm5_bitwise.csv'), 'w');
fprintf(fid, 'gate,verdict,nCompare,detail\n');
fprintf(fid, 'M5_bitwise_rerun_S3,%s,%d,"%s"\n', local_tf(ok), height(s3)*numel(numCols), ...
    strjoin(detail, '; '));
fclose(fid);
fprintf('M5 bitwise: %s (%d fields compared)\n', local_tf(ok), height(s3)*numel(numCols));
end

function s = local_tf(tf)
if tf, s = 'PASS'; else, s = 'FAIL'; end
end
