function ok = q4_gates()
%Q39.Q4_GATES Q4 正式批门评估(QUAD_MIGRATION_PLAN 20260921 §5-M6/M7, 预注册
% 判据见 q39.q4_opt 头注)。读 results/q4_formal.csv, 写 results/q4_gates.csv,
% 返回总体 PASS/FAIL。判据:
%   G1 openloop 跨批逐位: openloop 真值超额在 l1 批与 truth 批相等(逐位,
%      每遍分别成立) —— 不读功率指令臂的植物冻结复核点;
%   G2 学习臂全优于开环: sweepcal/purerl_off/purerl_on 真值口径超额 <
%      开环真值超额(l1 批, 两遍各自); truth 批同判据作参照行;
%   G3 赢面损耗 ≤1pp/臂: wear = margin_truth批 − margin_l1批(真值口径,
%      两遍各自); 前置 G1;
%   G4 ×2 逐位: pass1/pass2 仿真派生量逐位一致(NaN==NaN)。预注册修正(2026-09-21,
%      首次评估后、复评前登记; 批数据零改动):
%      a) runtime_s(挂钟簿记)逐出逐位集——M6"逐位确定"指仿真派生量, 先例 Q1/M5
%         的逐位集也不含 runtime;
%      b) 锚点臂(openloop)的 margin_pp/delta_margin_pp 逐出逐位集——pass1 冷启动
%         时锚点文件尚不存在记 NaN、pass2 记 0, 是簿记而非测量; openloop 的超额
%         已由 G1 钉住逐位;
%      c) G6 结构门补 estMode 过滤(评估器缺陷: 同臂在 l1/truth 两批各一份)。
%   G5 rows 契约: 全部 rowsN ∈ [9000, 11250);
%   G6 M7 结构: 每遍每臂恰 true/est/diff 三行, diff 行超额 = delta 列。
root = fileparts(fileparts(mfilename('fullpath')));
csv = fullfile(root, 'results', 'q4_formal.csv');
assert(exist(csv, 'file') == 2, 'q39:Q4Gates', '缺少 %s, 先跑 run_q4_formal。', csv);
T = readtable(csv, 'Delimiter', ',', 'ReadVariableNames', true);
g = {};   % gate,verdict,detail
getv = @(pass, mode, arm, cal, col) local_cell_val(T, pass, mode, arm, cal, col);

% ---- G1 ----
d1 = local_maxabs(getv(1,'l1','openloop','true','excess_pct'), ...
                  getv(1,'truth','openloop','true','excess_pct'));
d2 = local_maxabs(getv(2,'l1','openloop','true','excess_pct'), ...
                  getv(2,'truth','openloop','true','excess_pct'));
g = [g; {'G1_openloop_crossbatch_bitwise', local_tf(isfinite(d1) && isfinite(d2) && d1==0 && d2==0), ...
    sprintf('pass1 |d|=%.17g pass2 |d|=%.17g', d1, d2)}];

% ---- G2 + G3 ----
learners = {'sweepcal','purerl_off','purerl_on'};
g2ok = true; g3ok = true; det2 = {}; det3 = {};
for p = 1:2
    exOpen = getv(p,'l1','openloop','true','excess_pct');
    for ia = 1:numel(learners)
        arm = learners{ia};
        exL = getv(p,'l1',arm,'true','excess_pct');
        exT = getv(p,'truth',arm,'true','excess_pct');
        mT = exOpen - exT;           % 真值批赢面
        mL = exOpen - exL;           % l1 批赢面(真值口径)
        g2ok = g2ok && isfinite(exL) && exL < exOpen;
        det2{end+1} = sprintf('p%d %s: %.4f < %.4f', p, arm, exL, exOpen); %#ok<AGROW>
        wear = mT - mL;              % = exL - exT (开环逐位相等时)
        g3ok = g3ok && isfinite(wear) && wear <= 1.0;
        det3{end+1} = sprintf('p%d %s: wear=%.4fpp (truth margin %.4f / l1 margin %.4f)', ...
            p, arm, wear, mT, mL); %#ok<AGROW>
    end
end
g = [g; {'G2_learning_beat_openloop', local_tf(g2ok), strjoin(det2, '; ')}];
g = [g; {'G3_margin_wear_le_1pp', local_tf(g3ok), strjoin(det3, '; ')}];

% ---- G4: pass1 vs pass2 逐位(按 chunk,pass,arm,estMode,caliber 对齐) ----
% 逐位集 = 仿真派生量; runtime_s 与锚点臂 margin 列簿记排除(见头注修正 a/b)
bitCols = {'excess_pct','moe','delta_excess_pp','bias_meas_pct','rowsN'};
g4ok = height(T) > 0; detail4 = {};
rows1 = T(T.pass == 1, :); rows2 = T(T.pass == 2, :);
if height(rows1) ~= height(rows2)
    g4ok = false;
    detail4{end+1} = sprintf('row count pass1=%d pass2=%d', height(rows1), height(rows2));
else
    for i = 1:height(rows1)
        key1 = {rows1.chunk{i}, rows1.arm{i}, rows1.estMode{i}, rows1.caliber{i}};
        key2 = {rows2.chunk{i}, rows2.arm{i}, rows2.estMode{i}, rows2.caliber{i}};
        if ~isequal(key1, key2)
            g4ok = false;
            detail4{end+1} = sprintf('row %d key mismatch', i);
            continue;
        end
        cols = bitCols;
        if ~strcmp(rows1.arm{i}, 'openloop')
            cols = [cols, {'margin_pp','delta_margin_pp'}];
        end
        for kc = 1:numel(cols)
            a = rows1.(cols{kc})(i); b = rows2.(cols{kc})(i);
            if ~(isnan(a) && isnan(b)) && a ~= b
                g4ok = false;
                detail4{end+1} = sprintf('%s %s %s %s: %.17g vs %.17g', ...
                    rows1.chunk{i}, rows1.arm{i}, rows1.estMode{i}, cols{kc}, a, b);
            end
        end
    end
end
g = [g; {'G4_bitwise_pass1_pass2', local_tf(g4ok), strjoin(unique(detail4), '; ')}];

% ---- G5: rows 契约 ----
rn = T.rowsN;
g5ok = all(rn >= 9000 & rn < 11250);
g = [g; {'G5_rows_contract_9000', local_tf(g5ok), ...
    sprintf('rowsN min=%d max=%d (n=%d)', min(rn), max(rn), numel(rn))}];

% ---- G6: M7 结构(每 pass x 每批 estMode x 每臂 恰 true/est/diff 三行) ----
g6ok = true; detail6 = {};
modes = {'l1','truth'};
for p = 1:2
    for im = 1:numel(modes)
        for a = {'openloop','known','sweepcal','purerl_off','purerl_on'}
            sel = T.pass == p & strcmp(T.estMode, modes{im}) & strcmp(T.arm, a{1});
            cals = sort(T.caliber(sel));
            if numel(cals) ~= 3 || ~isequal(cals, {'diff','est','true'}')
                g6ok = false;
                detail6{end+1} = sprintf('p%d %s %s rows=%d', p, modes{im}, a{1}, numel(cals));
            elseif any(abs(T.delta_excess_pp(sel & strcmp(T.caliber,'diff')) - ...
                           T.excess_pct(sel & strcmp(T.caliber,'diff'))) > 0)
                g6ok = false;
                detail6{end+1} = sprintf('p%d %s %s diff-row != delta', p, modes{im}, a{1});
            end
        end
    end
end
g = [g; {'G6_m7_three_row_structure', local_tf(g6ok), ...
    strjoin([detail6, {sprintf('rows=%d', height(T))}], '; ')}];

% ---- 落盘 ----
fid = fopen(fullfile(root, 'results', 'q4_gates.csv'), 'w');
fprintf(fid, 'gate,verdict,detail\n');
for i = 1:size(g, 1)
    fprintf(fid, '%s,%s,"%s"\n', g{i,1}, g{i,2}, g{i,3});
end
fclose(fid);
ok = all(strcmp(g(:,2), 'PASS'));
for i = 1:size(g, 1)
    fprintf('%-36s %s  %s\n', g{i,1}, g{i,2}, g{i,3});
end
fprintf('Q4 GATES: %s\n', local_tf(ok));
end

function v = local_cell_val(T, pass, mode, arm, cal, col)
sel = T.pass == pass & strcmp(T.estMode, mode) & strcmp(T.arm, arm) & strcmp(T.caliber, cal);
assert(any(sel), 'q39:Q4Gates', '缺少行 pass=%d %s %s %s', pass, mode, arm, cal);
v = T.(col)(find(sel, 1));
end

function d = local_maxabs(a, b)
if isnan(a) && isnan(b)
    d = NaN;
else
    d = abs(a - b);
end
end

function s = local_tf(tf)
if tf, s = 'PASS'; else, s = 'FAIL'; end
end
