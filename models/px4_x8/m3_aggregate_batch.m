function result = m3_aggregate_batch(segDirs)
%M3_AGGREGATE_BATCH The M3 batch verdict: aggregate every trial segment
%   under a frozen manifest contract (round-1 M3-R1-F4 closure; rules
%   v1.7 section 2 rules 4-6 pattern, reusing the in-repo M2 governance
%   discipline instead of a second driver). A segment result alone can
%   never again be presented as the batch verdict: this entry
%     1. re-captures the LIVE source identity and requires a clean tree
%        and the same commit as every segment (no 'unknown', no mixing);
%     2. checks the frozen 14-arm contract: exactly the 14 scenario ids,
%        each exactly once, across the given segments (missing / duplicate
%        / extra are hard failures with dedicated ids);
%     3. hard-asserts EVERY arm verdict ok==true (a FAIL row can never
%        aggregate into a batch PASS) and that each arm archive exists;
%     4. requires M3-N5 and M3-R1 to come from the SAME segment run
%        (same runId) with equal grids, then re-checks the sample-exact
%        reproducibility difference;
%     5. recomputes the paired gates from the archived arms (dual-track
%        energy with coverage, v tracking on all four same-v0 pairs, eta
%        convergence summary) and fails on any breach.
%   segDirs: cell array of segment archive dirs (each holds result.mat).
c = expectedBatchContract();
assert(iscellstr(segDirs) && ~isempty(segDirs), 'air:M3Agg:BadInput', ...
    'segDirs must be a non-empty cell array of segment directories');

% ---- 1. live source binding: clean tree, single commit across segments
live = m3_source_binding([mfilename('fullpath') '.m']);
assert(~live.dirty, 'air:M3Agg:DirtyTree', ...
    ['batch aggregation requires a clean working tree; uncommitted ' ...
    'changes:\n%s'], strjoin(live.dirtyLines, newline));
segs = struct();
for d = 1:numel(segDirs)
    f = fullfile(segDirs{d}, 'result.mat');
    assert(exist(f, 'file'), 'air:M3Agg:NoResult', ...
        'no result.mat in %s', segDirs{d});
    S = load(f, 'result');
    r = S.result;
    assert(isfield(r, 'binding') && isfield(r.binding, 'gitCommit') && ...
        isfield(r.binding, 'runId'), 'air:M3Agg:NoBinding', ...
        'result in %s carries no source binding (pre-round-2 archive?)', ...
        segDirs{d});
    assert(strcmp(r.binding.gitCommit, live.gitCommit), ...
        'air:M3Agg:SourceMismatch', ...
        'segment %s commit %s differs from live HEAD %s -- mixed batch', ...
        segDirs{d}, r.binding.gitCommit, live.gitCommit);
    % result.runs is stored log-free by the entry (per-arm <id>.mat
    % archives keep the logs); arm data for the gates is loaded from
    % those per-arm files on demand (getArmFromSegs)
    segs(d).runs = r.runs;
    segs(d).dir = segDirs{d};
    segs(d).binding = r.binding;
    segs(d).dir = segDirs{d};
end

% ---- 2. frozen 14-arm manifest: exact cover, no duplicates, no extras
arms = {};
for d = 1:numel(segs)
    fn = fieldnames(segs(d).runs);
    for j = 1:numel(fn)
        arms{end + 1} = strrep(fn{j}, '_', '-'); %#ok<AGROW>
    end
end
uniqueArms = unique(arms);
for j = 1:numel(uniqueArms)
    n = sum(strcmp(arms, uniqueArms{j}));
    if n > 1
        error('air:M3Agg:DuplicateArm', ...
            'arm %s appears in %d segments -- a batch arm runs exactly once', ...
            uniqueArms{j}, n);
    end
end
missing = setdiff(c.arms, arms);
assert(isempty(missing), 'air:M3Agg:MissingArm', ...
    'missing batch arm(s): %s -- segments cover %d of %d frozen arms', ...
    strjoin(missing, ', '), numel(arms), numel(c.arms));
extra = setdiff(arms, c.arms);
assert(isempty(extra), 'air:M3Agg:ExtraArm', ...
    'unknown arm(s) outside the frozen contract: %s', strjoin(extra, ', '));

% ---- 3. every arm verdict is PASS and its archive file exists
getArm = @(id) getArmFromSegs(segs, id);
for j = 1:numel(c.arms)
    a = getArm(c.arms{j});
    assert(isfield(a, 'ok') && isscalar(a.ok) && a.ok, 'air:M3Agg:ArmFailed', ...
        'arm %s verdict is not PASS -- FAIL rows cannot aggregate', ...
        c.arms{j});
    [segIdx, ~] = locateArm(segs, c.arms{j});
    f = fullfile(segs(segIdx).dir, [c.arms{j} '.mat']);
    assert(exist(f, 'file'), 'air:M3Agg:ArchiveMissing', ...
        'arm archive %s is missing', f);
end

% ---- 4. reproducibility pair: SAME segment, SAME runId, equal grids
[n5s, n5i] = locateArm(segs, 'M3-N5');
[r1s, r1i] = locateArm(segs, 'M3-R1');
assert(n5s == r1s, 'air:M3Agg:ReproSession', ...
    'M3-N5 (segment %d) and M3-R1 (segment %d) must share one session', ...
    n5s, r1s);
assert(strcmp(segs(n5s).binding.runId, segs(r1s).binding.runId), ...
    'air:M3Agg:ReproSession', ...
    'M3-N5 and M3-R1 runIds differ -- not a same-process pair');
e5 = getArm('M3-N5').logs.el;
eR = getArm('M3-R1').logs.el;
assert(size(e5, 1) == size(eR, 1), 'air:M3Agg:ReproGrid', ...
    'M3-N5/R1 eta log lengths differ (%d vs %d)', ...
    size(e5, 1), size(eR, 1));
dv = max(abs(e5(:, 1) - eR(:, 1)));
dv2 = max(abs(getArm('M3-N5').logs.Mb(:, 1) - getArm('M3-R1').logs.Mb(:, 1)));
assert(max(dv, dv2) < 1e-9, 'air:M3Agg:ReproDiff', ...
    'M3-R1 vs M3-N5 not sample-exact: dEta %.3g, dV %.3g', dv, dv2);
fprintf('repro: M3-R1 vs M3-N5 same session %s: max|d eta| %.3g, max|d v| %.3g\n', ...
    segs(n5s).binding.runId, dv, dv2);

% ---- 5. recompute the paired gates from the archived arms
pair = struct();
B0N = getArm('B0-N');
for j = 1:numel(c.nominalArms)
    id = c.nominalArms{j};
    a = getArm(id);
    e = m3_eval_energy(a.logs.ta, a.logs.Pe, a.validCostMs, ...
        B0N.logs.ta, B0N.logs.Pe, B0N.validCostMs, c.gateWin, c.notWorse);
    pair.(strrep(sprintf('%s_dB0', id), '-', '_')) = e;
    fprintf(['%s vs B0-N: masked %+.5f%% (gate %.1f%%) | full %+.5f%% | ' ...
        'common %.1f%% (%d/%d)\n'], id, e.dEPct, c.notWorse, ...
        e.dEPctFull, 100 * e.maskFrac, e.nMask, e.nWin);
end
for k = 1:size(c.gateMap, 1)
    a = getArm(c.gateMap{k, 1});
    for jj = 1:2
        b = getArm(c.gateMap{k, 1 + jj});
        e = m3_eval_energy(a.logs.ta, a.logs.Pe, a.validCostMs, ...
            b.logs.ta, b.logs.Pe, b.validCostMs, c.gateWin, c.notWorse);
        pair.(strrep(sprintf('%s_d%s', c.gateMap{k, 1}, b.id), '-', '_')) = e;
        fprintf(['%s vs %s: masked %+.5f%% (gate %.1f%%) | full %+.5f%% | ' ...
            'common %.1f%% (%d/%d)\n'], a.id, b.id, e.dEPct, c.notWorse, ...
            e.dEPctFull, 100 * e.maskFrac, e.nMask, e.nWin);
        assert(e.pass, 'air:M3Agg:NotWorse', ...
            '%s vs %s masked dE %+.5f%% breaches the %.1f%% gate', ...
            a.id, b.id, e.dEPct, c.notWorse);
    end
end
for k = 1:size(c.vPairs, 1)
    a = getArm(c.vPairs{k, 1});
    b = getArm(c.vPairs{k, 2});
    dvTrk = a.vTrk - b.vTrk;
    pair.(strrep(sprintf('%s_vTrk', c.vPairs{k, 1}), '-', '_')) = ...
        struct('m3', a.vTrk, 'b1', b.vTrk, 'delta', dvTrk, ...
        'pass', dvTrk <= c.vTrkTol);
    fprintf('%s vs %s: mean|v-vref| %.5f vs %.5f (tol +%.2f)\n', ...
        a.id, b.id, a.vTrk, b.vTrk, c.vTrkTol);
    assert(dvTrk <= c.vTrkTol, 'air:M3Agg:VTrk', ...
        '%s v tracking %.5f vs B1 %.5f breaches the +%.2f tolerance', ...
        a.id, a.vTrk, b.vTrk, c.vTrkTol);
end
fprintf('eta convergence [192,240):\n');
for j = 1:numel(c.etaArms)
    a = getArm(c.etaArms{j});
    assert(~isempty(a.etaConv), 'air:M3Agg:ConvMissing', ...
        '%s carries no convergence record', a.id);
    fprintf('  %-7s mean %.5f converged %d monotonic %d maxReg %.2g\n', ...
        a.id, a.etaCenter, a.etaConv.converged, a.etaConv.monotonic, ...
        a.etaConv.maxRegression);
    if a.nominal
        assert(a.etaConv.converged && a.etaConv.monotonic, ...
            'air:M3Agg:Conv', ...
            '%s fails the frozen convergence criterion', a.id);
    end
end

wsRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
outDir = fullfile(wsRoot, 'results', 'air_m3_trials', ...
    [char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')) '_aggregate']);
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
result = struct('pass', true, 'segments', {segDirs}, 'liveBinding', live, ...
    'pair', pair, 'archiveDir', string(outDir));
save(fullfile(outDir, 'aggregate.mat'), 'result');
fprintf(['M3 AGGREGATE BATCH PASS (%d segments, %d arms, commit %s)\n'], ...
    numel(segs), numel(c.arms), live.gitCommit);
end

% ---------------------------------------------------------------------------
function c = expectedBatchContract()
%EXPECTEDEDBATCHCONTRACT the ONE fixed batch contract (rules section 2
%   rule 8 pattern): the aggregate never takes the segment set as its own
%   definition of what to validate.
c.arms = { ...
    'M3-N1', 'M3-N2', 'M3-N3', 'M3-N4', 'M3-N5', ...
    'M3-D1', 'M3-D2', 'M3-R1', ...
    'B0-N', 'B0-D', 'B1-N1', 'B1-N2', 'B2-N1', 'B2-N2'};
c.nominalArms = {'M3-N1', 'M3-N2', 'M3-N3', 'M3-N4', 'M3-N5'};
c.etaArms = {'M3-N1', 'M3-N2', 'M3-N3', 'M3-N4', 'M3-N5', ...
    'M3-D1', 'M3-D2', 'B2-N1', 'B2-N2'};
c.gateMap = {'M3-N1', 'B1-N1', 'B2-N1'; ...
    'M3-N2', 'B1-N1', 'B2-N2'; ...
    'M3-N3', 'B1-N2', 'B2-N1'; ...
    'M3-N4', 'B1-N2', 'B2-N2'};
c.vPairs = {'M3-N1', 'B1-N1'; 'M3-N2', 'B1-N1'; ...
    'M3-N3', 'B1-N2'; 'M3-N4', 'B1-N2'};
c.gateWin = [144.0, 240.0];
c.notWorse = 0.5;
c.vTrkTol = 0.05;
end

function a = getArmFromSegs(segs, id)
%GETARMFROMSEGS the FULL arm record (logs included) from the per-arm
%   archive of whichever segment ran it.
[segIdx, ~] = locateArm(segs, id);
f = fullfile(segs(segIdx).dir, [id '.mat']);
S = load(f, 'r');
a = S.r;
end

function [segIdx, fieldName] = locateArm(segs, id)
%LOCATEARM segment index and runs-field name of an arm.
fieldName = strrep(id, '-', '_');
for d = 1:numel(segs)
    if isfield(segs(d).runs, fieldName)
        segIdx = d;
        return;
    end
end
error('air:M3Agg:Internal', 'arm %s not located', id);
end
