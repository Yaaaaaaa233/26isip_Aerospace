function result = m3_aggregate_batch(segDirs, stagedDir)
%M3_AGGREGATE_BATCH The M3 batch verdict: aggregate every trial segment
%   under the frozen manifest contract (round-1 M3-R1-F4 + round-2
%   M3-R2-F4 hardening; rules v1.7 section 2 rules 4-8). A segment result
%   alone can never again be presented as the batch verdict. This entry
%     1. re-captures the LIVE source identity and requires a clean tree
%        and the same commit as the manifest and every segment (entry AND
%        exit bindings; no 'unknown', no mixing, no mid-run drift);
%     2. validates the staged manifest against the SOURCE contract
%        (m3_batch_contract via m3_batch_validate): attempt cap, arm-set
%        exact cover, repro co-segmentation -- a manifest edited in the
%        staged copy dies here whatever else was synced;
%     3. checks the SEGMENT and ROW verdict layers BOTH: every segment's
%        result.pass AND every arm's runs.ok must be PASS (a FAIL row can
%        never aggregate into a batch PASS);
%     4. binds every segment to the ONE batch: binding.batchId equals the
%        manifest batchId (a foreign/old-batch segment is rejected), the
%        archived tree was clean at entry AND exit, and the archived
%        SHA-256 fingerprints (entry/model/m0c/m2 plus the trials entry
%        file) match the LIVE files -- a zeroed or deleted fingerprint is
%        a hard failure;
%     5. hard-asserts the attempt accounting per segment: result.attempts
%        must exist, be a finite positive integer, be within the frozen
%        cap and equal the persistent <seg>.attempts marker (missing / 0 /
%        NaN / non-integer / over-budget / marker-mismatch all reject);
%     6. requires M3-N5 and M3-R1 from the SAME segment and session with
%        EQUAL TIME VECTORS (te2 and tb, exact) and equal values, then
%        re-checks the sample-exact reproducibility difference;
%     7. recomputes the paired gates from the archived arms (dual-track
%        energy with coverage, v tracking on all four same-v0 pairs, eta
%        convergence on the replayed centers) and fails on any breach.
%   segDirs: cell array of segment archive dirs (each holds result.mat).
%   stagedDir: the batch's staged directory (manifest.mat + markers).
c = m3_batch_contract();
assert(iscellstr(segDirs) && ~isempty(segDirs), 'air:M3Agg:BadInput', ...
    'segDirs must be a non-empty cell array of segment directories');
assert(isfolder(stagedDir), 'air:M3Agg:BadInput', ...
    'staged directory %s does not exist', stagedDir);

% ---- 1. live source binding: clean tree
live = m3_source_binding([mfilename('fullpath') '.m']);
assert(~live.dirty, 'air:M3Agg:DirtyTree', ...
    ['batch aggregation requires a clean working tree; uncommitted ' ...
    'changes:\n%s'], strjoin(live.dirtyLines, newline));

% ---- 2. manifest vs source contract (the manifest is evidence, not
% authority: cap, exact cover, repro co-segmentation)
S = load(fullfile(stagedDir, 'manifest.mat'), 'manifest');
[segs, info] = m3_batch_validate(S.manifest);
% The batch identity is the MANIFEST's commit: every segment must have run
% at exactly that commit (checked per segment below). The LIVE tree may be
% a later commit (e.g. documentation after the batch) as long as every
% fingerprinted source file is byte-identical to what the manifest
% recorded -- the sha block below is live-recomputed, so a changed source
% still dies there. Requiring HEAD == batch commit would wrongly void
% batch evidence after any later docs-only commit.
% live recompute of every fingerprint the manifest declares (rule 5:
% never trust a copied hash)
here = fileparts(mfilename('fullpath'));
liveSha = struct( ...
    'aggregate', sha256file(fullfile(here, 'm3_aggregate_batch.m')), ...
    'trials', sha256file(fullfile(here, 'run_air_m3_trials.m')), ...
    'contract', sha256file(fullfile(here, 'm3_batch_contract.m')), ...
    'evalArm', sha256file(fullfile(here, 'm3_eval_arm.m')), ...
    'model', sha256file(fullfile(here, 'air_spare.slx')), ...
    'm0c', sha256file(fullfile(here, 'm0c_vref_esc.m')), ...
    'm2', sha256file(fullfile(here, 'm2_eta_esc.m')));
fnS = fieldnames(liveSha);
for j = 1:numel(fnS)
    assert(isfield(S.manifest.sha, fnS{j}) && ...
        strcmp(S.manifest.sha.(fnS{j}), liveSha.(fnS{j})), ...
        'air:M3Agg:ContractMismatch', ...
        'manifest sha.%s differs from the live file -- the staged manifest does not describe this source', ...
        fnS{j});
end

% ---- 3/4/5. per-segment: binding, verdicts, fingerprints, attempts.
% Every given dir must map to a UNIQUE manifest segment; every manifest
% segment must be covered by exactly one dir.
segsDone = struct();
segRec = struct();
for d = 1:numel(segDirs)
    f = fullfile(segDirs{d}, 'result.mat');
    assert(exist(f, 'file'), 'air:M3Agg:NoResult', ...
        'no result.mat in %s', segDirs{d});
    R = load(f, 'result');
    r = R.result;
    % NOTE: 'attempts' is deliberately NOT in this list -- a missing
    % attempts field is one of the six rule-7f accounting classes and
    % must land on BadAttempts below, not on the binding check
    assert(isfield(r, 'binding') && isfield(r.binding, 'gitCommit') && ...
        isfield(r.binding, 'runId') && isfield(r, 'bindingExit') && ...
        isfield(r, 'segName') && isfield(r, 'batchId'), ...
        'air:M3Agg:NoBinding', ...
        'result in %s carries no batch binding (pre-round-3 archive?)', ...
        segDirs{d});
    if ~isfield(r, 'attempts')
        r.attempts = NaN;   % route the missing field onto BadAttempts
    end
    % segment identity: the manifest segment this archive claims to be
    hit = find(strcmp({segs.name}, r.segName), 1);
    assert(~isempty(hit), 'air:M3Agg:SegmentUnknown', ...
        'segment %s in %s is not a manifest segment', r.segName, segDirs{d});
    assert(~isfield(segsDone, ['x' r.segName]), 'air:M3Agg:SegmentTwice', ...
        'segment %s appears in more than one given dir', r.segName);
    segsDone.(['x' r.segName]) = true;
    % one batch: the common batch id (distinct from the per-session runId)
    assert(strcmp(r.batchId, info.batchId), 'air:M3Agg:BatchIdMismatch', ...
        'segment %s (dir %s) carries batchId %s, not this batch''s %s -- old-batch or foreign segment', ...
        r.segName, segDirs{d}, r.batchId, info.batchId);
    % entry AND exit live captures: same commit as this aggregate, clean
    % tree at both instants (an archive written by a dirty session or a
    % tree that changed mid-run cannot aggregate)
    assert(strcmp(r.binding.gitCommit, info.gitCommit) && ...
        strcmp(r.bindingExit.gitCommit, info.gitCommit), ...
        'air:M3Agg:SourceMismatch', ...
        'segment %s commit (%s / exit %s) differs from the batch commit %s', ...
        r.segName, r.binding.gitCommit, r.bindingExit.gitCommit, ...
        info.gitCommit);
    assert(r.binding.dirty == 0 && r.bindingExit.dirty == 0, ...
        'air:M3Agg:DirtyArchive', ...
        'segment %s was archived from a dirty tree (entry %d / exit %d)', ...
        r.segName, r.binding.dirty, r.bindingExit.dirty);
    % archived fingerprints vs the live files (zeroed/deleted sha dies):
    % a segment binding hashes its own entry file (run_air_m3_trials.m),
    % the model and both adapters -- all must match the live files
    assert(isfield(r.binding, 'sha'), 'air:M3Agg:FingerprintMismatch', ...
        'segment %s carries no source fingerprints', r.segName);
    assert(strcmp(r.binding.sha.entry, liveSha.trials), ...
        'air:M3Agg:FingerprintMismatch', ...
        'segment %s archived sha.entry does not match the live trials file -- tampered or foreign evidence', ...
        r.segName);
    assert(strcmp(r.binding.sha.model, liveSha.model) && ...
        strcmp(r.binding.sha.m0c, liveSha.m0c) && ...
        strcmp(r.binding.sha.m2, liveSha.m2), ...
        'air:M3Agg:FingerprintMismatch', ...
        'segment %s archived model/adapter fingerprints do not match the live files', ...
        r.segName);
    % sha equality entry-vs-exit (the tree cannot change mid-segment)
    assert(isequal(r.binding.sha, r.bindingExit.sha), ...
        'air:M3Agg:FingerprintMismatch', ...
        'segment %s fingerprints changed between entry and exit', ...
        r.segName);
    % manifest declared arms == the segment's actual runs (an edited
    % declared list is a contract violation even with all files present)
    fnR = fieldnames(r.runs);
    gotArms = cellfun(@(x) strrep(x, '_', '-'), fnR, ...
        'UniformOutput', false);
    assert(isequal(sort(gotArms(:)), sort(segs(hit).arms(:))), ...
        'air:M3Agg:ManifestMismatch', ...
        'segment %s declares {%s} but its runs contain {%s}', ...
        r.segName, strjoin(segs(hit).arms, ','), strjoin(sort(gotArms), ','));
    % SEGMENT verdict layer: a failed segment is not pass evidence even
    % when every arm row says ok
    assert(isscalar(r.pass) && islogical(r.pass) && r.pass, ...
        'air:M3Agg:SegmentFailed', ...
        'segment %s verdict is pass=false -- failed segments cannot aggregate', ...
        r.segName);
    % attempt accounting (rule 7f): six rejection classes share one id
    mk = readAttemptsMarker(stagedDir, r.segName);
    assert(isscalar(r.attempts) && isnumeric(r.attempts) && ...
        isfinite(r.attempts) && r.attempts > 0 && ...
        r.attempts == floor(r.attempts), ...
        'air:M3Agg:BadAttempts', ...
        'segment %s attempts field is missing/0/NaN/non-integer (got %s)', ...
        r.segName, num2str(r.attempts));
    assert(r.attempts <= info.maxAttempts, 'air:M3Agg:BadAttempts', ...
        'segment %s attempts %d exceeds the frozen cap %d', ...
        r.segName, r.attempts, info.maxAttempts);
    assert(r.attempts == mk, 'air:M3Agg:BadAttempts', ...
        'segment %s result.attempts (%s) is inconsistent with the persistent marker (%s)', ...
        r.segName, num2str(r.attempts), num2str(mk));
    segRec(hit).runs = r.runs;
    segRec(hit).dir = segDirs{d};
    segRec(hit).binding = r.binding;
    segRec(hit).attempts = r.attempts;
    segRec(hit).segName = r.segName;
    fprintf('segment %s: runId %s, attempt %d/%d, %d arms, pass\n', ...
        r.segName, r.binding.runId, r.attempts, info.maxAttempts, ...
        numel(gotArms));
end
for k = 1:numel(segs)
    assert(isfield(segsDone, ['x' segs(k).name]), ...
        'air:M3Agg:SegmentMissing', ...
        'manifest segment %s has no archive dir among the given segments', ...
        segs(k).name);
end
segs = segRec;

% ---- frozen 14-arm manifest: exact cover, no duplicates, no extras
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
    'unknown arm(s) outside the frozen contract: %s', strjoin(extra, ','));

% ---- every arm verdict is PASS and its archive file exists
getArm = @(id) getArmFromSegs(segs, id);
for j = 1:numel(c.arms)
    [segIdx, fieldName] = locateArm(segs, c.arms{j});
    vr = segs(segIdx).runs.(fieldName);
    assert(isfield(vr, 'ok') && isscalar(vr.ok) && vr.ok, ...
        'air:M3Agg:ArmFailed', ...
        'arm %s verdict is not PASS in its segment result -- FAIL rows cannot aggregate', ...
        c.arms{j});
    f = fullfile(segs(segIdx).dir, [c.arms{j} '.mat']);
    assert(exist(f, 'file'), 'air:M3Agg:ArchiveMissing', ...
        'arm archive %s is missing', f);
end

% ---- 6. reproducibility pair: SAME segment, SAME runId, EQUAL time
% vectors (te2 AND tb, exact) and equal values -- a shifted grid with
% equal lengths must be rejected (round-2 A12)
[n5s, ~] = locateArm(segs, 'M3-N5');
[r1s, ~] = locateArm(segs, 'M3-R1');
assert(n5s == r1s, 'air:M3Agg:ReproSession', ...
    'M3-N5 (segment %s) and M3-R1 (segment %s) must share one session', ...
    segs(n5s).segName, segs(r1s).segName);
assert(strcmp(segs(n5s).binding.runId, segs(r1s).binding.runId), ...
    'air:M3Agg:ReproSession', ...
    'M3-N5 and M3-R1 runIds differ -- not a same-process pair');
L5 = getArm('M3-N5').logs;
LR = getArm('M3-R1').logs;
assert(isequal(L5.te2(:), LR.te2(:)), 'air:M3Agg:ReproGrid', ...
    'M3-N5/R1 eta time vectors differ');
assert(isequal(L5.tb(:), LR.tb(:)), 'air:M3Agg:ReproGrid', ...
    'M3-N5/R1 bus time vectors differ');
assert(size(L5.el, 1) == size(LR.el, 1), 'air:M3Agg:ReproGrid', ...
    'M3-N5/R1 eta log lengths differ (%d vs %d)', ...
    size(L5.el, 1), size(LR.el, 1));
dv = max(abs(L5.el(:, 1) - LR.el(:, 1)));
dv2 = max(abs(L5.Mb(:, 1) - LR.Mb(:, 1)));
assert(max(dv, dv2) < 1e-9, 'air:M3Agg:ReproDiff', ...
    'M3-R1 vs M3-N5 not sample-exact: dEta %.3g, dV %.3g', dv, dv2);
fprintf('repro: M3-R1 vs M3-N5 same session %s: max|d eta| %.3g, max|d v| %.3g\n', ...
    segs(n5s).binding.runId, dv, dv2);

% ---- 7. recompute the paired gates from the archived arms
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
fprintf('eta convergence [192,240) on the replayed centers:\n');
for j = 1:numel(c.etaArms)
    a = getArm(c.etaArms{j});
    assert(~isempty(a.etaConv), 'air:M3Agg:ConvMissing', ...
        '%s carries no convergence record', a.id);
    fprintf('  %-7s center %.5f converged %d monotonic %d maxReg %.2g replayDiff %.3g\n', ...
        a.id, a.etaCenter, a.etaConv.converged, a.etaConv.monotonic, ...
        a.etaConv.maxRegression, a.etaReplayDiff);
    if a.nominal
        assert(a.etaConv.converged && a.etaConv.monotonic, ...
            'air:M3Agg:Conv', ...
            '%s fails the frozen convergence criterion', a.id);
    end
end

% ---- batch manifest output (machine-checkable batch summary)
wsRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
outDir = fullfile(wsRoot, 'results', 'air_m3_trials', ...
    [char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')) '_aggregate']);
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
segTable = repmat(struct('segName', '', 'dir', "", 'runId', '', ...
    'attempts', [], 'commit', ''), 1, numel(segs));
for d = 1:numel(segs)
    segTable(d).segName = segs(d).segName;
    segTable(d).dir = string(segs(d).dir);
    segTable(d).runId = segs(d).binding.runId;
    segTable(d).attempts = segs(d).attempts;
    segTable(d).commit = segs(d).binding.gitCommit;
end
result = struct('pass', true, 'batchId', info.batchId, ...
    'segments', {segTable}, 'liveBinding', live, ...
    'manifestCommit', info.gitCommit, 'pair', pair, ...
    'archiveDir', string(outDir));
save(fullfile(outDir, 'aggregate.mat'), 'result');
fprintf(['M3 AGGREGATE BATCH PASS (batchId %s, %d segments, %d arms, ' ...
    'commit %s)\n'], info.batchId, numel(segs), numel(c.arms), ...
    live.gitCommit);
end

% ---------------------------------------------------------------------------
function mk = readAttemptsMarker(stagedDir, segName)
%READATTEMPTSMARKER the persistent counter value, hard-failing on any
%   corrupted/missing marker (never rebuilt, never defaulted).
f = fullfile(stagedDir, [segName '.attempts']);
assert(exist(f, 'file'), 'air:M3Agg:BadAttempts', ...
    'persistent attempt marker for segment %s is missing', segName);
raw = strtrim(fileread(f));
mk = str2double(raw);
assert(~isempty(raw) && isfinite(mk) && mk > 0 && mk == floor(mk), ...
    'air:M3Agg:BadAttempts', ...
    'persistent attempt marker for segment %s contains "%s"', ...
    segName, raw);
end

function h = sha256file(fname)
%SHA256FILE lowercase hex SHA-256 of a file (m3_source_binding pattern).
fid = fopen(fname, 'rb');
assert(fid > 0, 'air:M3Agg:Binding', 'cannot open %s', fname);
data = fread(fid, '*uint8')';
fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
d = md.digest(data);
h = lower(sprintf('%02x', typecast(int8(d), 'uint8')));
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
