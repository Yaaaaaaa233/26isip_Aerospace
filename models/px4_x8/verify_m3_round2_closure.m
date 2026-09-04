function ok = verify_m3_round2_closure(stage, segDirs)
%VERIFY_M3_ROUND2_CLOSURE Round-2 closure evidence for the M3 acceptance
%   chain (round-1 report M3_REACCEPT_CODEX_20260904 findings F1-F6).
%   Stages (run each in a FRESH MATLAB process per the heap discipline):
%     'unit'      -- the three unit suites incl. the new B7 negatives;
%     'negative'  -- PRODUCTION-PATH negatives: fabricated arm logs driven
%                    through m3_eval_arm itself (dead search, monotonicity
%                    breach, 4 s bit1/2 run, NaN trace, v-hold drift) --
%                    the formal decision path must reject each -- plus the
%                    caller-global four-state x exit targeted restore
%                    matrix for run_air_m3_trials / run_air_m3_boundary
%                    (incl. AFTER-WRITE failures, round-1 R5-R8 gap);
%     'aggregate' -- manifest tamper negatives against COPIES of the real
%                    batch segments (missing / duplicate / extra arm,
%                    mixed commit, FAIL row, missing archive, R1 split
%                    across sessions, R1 grid mismatch);
%     'report'    -- prints the closure checklist mapping.
%   segDirs: for 'aggregate', the real segment dirs of the frozen batch.
%   Every negative asserts the EXACT error id (rules section 4); the
%   executed matrix rows are printed row by row (rules section 4.3: the
%   declaration must equal what actually ran -- this is a TARGETED
%   matrix, not a cartesian cover).
if nargin < 1
    stage = 'unit';
end
if nargin < 2
    segDirs = {};
end
valid = {'unit', 'negative', 'aggregate', 'report'};
assert(any(strcmp(stage, valid)), 'air:M3Verify:BadStage', ...
    'stage must be one of %s', strjoin(valid, '|'));
adapterDir = fileparts(mfilename('fullpath'));
addpath(adapterDir);
wsRoot = fileparts(fileparts(adapterDir));

global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
% the verifier honours the contract it enforces: snapshot the CALLER's
% globals (any non-empty value incl. NaN/Inf, exactly-as-found) and
% restore on every exit
verSaved = snapshotGlobals();
verCleanup = onCleanup(@() m3v_restore(verSaved)); %#ok<NASGU>

switch stage
    case 'unit'
        ok = runUnit();
    case 'negative'
        ok = runNegative();
    case 'aggregate'
        ok = runAggregate(segDirs, wsRoot);
    case 'report'
        printReport();
        ok = true;
end
fprintf('STAGE %s %s\n', stage, ternaryStr(ok, 'PASS', 'FAIL'));
end

% ---------------------------------------------------------------------------
function ok = runUnit()
% m0c/m2 suites are LEGACY SCRIPT entries (rules section 2.1 registered
% limitation): run by name -- their internal asserts are the failure
% signal; the m3 suite is a function whose asserts fire the same way.
test_m3_coordination_unit;
test_m0c_esc_unit;
test_m2_eta_esc_unit;
fprintf('unit: 3 suites PASS (m3 coordination incl. B7, m0c, m2)\n');
ok = true;
end

% ---------------------------------------------------------------------------
function ok = runNegative()
ok = true;
ok = ok && prodPathNegatives();
ok = ok && entryRestoreMatrix();
end

function ok = prodPathNegatives()
%PRODPATHNEGATIVES the formal per-arm decision path must reject each
%   fabricated defect (round-1 negatives N5/N6/N7 + NaN + v-hold drift),
%   and a well-formed fabricated arm must PASS first (positive control:
%   rejections come from the injected defect, not a broken fixture).
ok = true;
[logs, pv, pe, arb] = fakeLogs();
win = {[144, 240], [192, 240], [20, 30]};

r0 = m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, pv, pe, ...
    struct(), logs, win{:}, 240.0);
assert(r0.ok && r0.exe.chk.pass, ...
    'R2-P0 positive control failed (chk: %s)', ...
    strjoin(r0.exe.chk.failFields, ','));
fprintf('R2-P0  m3_eval_arm    fabricated good arm            PASS (ok=1)\n');

% N5': dead eta search -- candidate constant 1.0 everywhere: convergence
% and hold both "pass" vacuously; participation must reject it
lg = logs; lg.el(:, 1) = 1.0; lg.el(:, 2) = 1.0;
r1 = m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, pv, pe, ...
    struct(), lg, win{:}, 240.0);
assert(~r1.ok && any(strcmp(r1.exe.chk.failFields, 'searchParticipationE')), ...
    'R2-N5 dead search not rejected (fields: %s)', ...
    strjoin(r1.exe.chk.failFields, ','));
assert(r1.etaConv.converged, ...
    'R2-N5 fixture sanity: constant 1.0 must stay converged');
fprintf('R2-N5  m3_eval_arm    dead eta search (cand==1.0)     rejected\n');
ok = ok && true;

% N6': period means alternate 1.000/1.009 -- mean passes, monotonicity
% breaches the frozen 5e-3 regression tolerance
lg = altConvergence(logs);
r2 = m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, pv, pe, ...
    struct(), lg, win{:}, 240.0);
assert(~r2.ok && r2.etaConv.converged && ~r2.etaConv.monotonic, ...
    'R2-N6 monotonicity breach not rejected (conv %d mono %d ok %d)', ...
    r2.etaConv.converged, r2.etaConv.monotonic, r2.ok);
fprintf('R2-N6  m3_eval_arm    mean ok, regression 0.009      rejected\n');

% N7': bits 1/2 continuously hot for 4 s on a disturbed arm (cap: 2 s)
lg = logs;
sel = lg.ta >= 210 & lg.ta < 214;
lg.A(sel, 27) = 1;
r3 = m3_eval_arm('M3-D1', false, 'm3', 'm3', 9.0, 0.8, arb, pv, pe, ...
    struct(), lg, win{:}, 240.0);
assert(~r3.ok && ~r3.hard12OK && abs(r3.hard12RunMax - 4.0) < 0.2, ...
    'R2-N7 4 s bit1/2 run not rejected (runMax %.2f)', r3.hard12RunMax);
fprintf('R2-N7  m3_eval_arm    4 s continuous bit1/2 (cap 2 s) rejected\n');

% N4': NaN stretch in the eta candidate -- finiteness gate
lg = logs;
lg.el(lg.te2 >= 50 & lg.te2 < 60, 1) = NaN;
lg.el(lg.te2 >= 50 & lg.te2 < 60, 2) = NaN;
r4 = m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, pv, pe, ...
    struct(), lg, win{:}, 240.0);
assert(~r4.ok && any(strcmp(r4.exe.chk.failFields, 'nonFiniteE')), ...
    'R2-N4 NaN candidate not rejected (fields: %s)', ...
    strjoin(r4.exe.chk.failFields, ','));
fprintf('R2-N4  m3_eval_arm    NaN eta candidate              rejected\n');

% v-hold drift: applied v drifts inside an eta slot past the transition
lg = logs;
k = find(lg.tb >= 210, 1):find(lg.tb >= 239.9, 1);
ramp = 0.01 * (0:numel(k) - 1)' / max(1, numel(k) - 1);
lg.Mb(k, 1) = lg.Mb(k, 1) + ramp;
r5 = m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, pv, pe, ...
    struct(), lg, win{:}, 240.0);
assert(~r5.ok && any(strcmp(r5.exe.chk.failFields, 'holdConstancyV')), ...
    'R2-N8 v-hold drift not rejected (fields: %s)', ...
    strjoin(r5.exe.chk.failFields, ','));
fprintf('R2-N8  m3_eval_arm    v applied drift in hold slot   rejected\n');
end

function lg = altConvergence(logs)
%ALTCONVERGENCE last-slot period constants alternating 1.000/1.009 (the
%   round-1 N6 fixture: mean 1.0045 passes, adjacent regression 0.009
%   breaches 5e-3).
lg = logs;
idx = find(lg.te2 >= 192);
per = round(4.0 / 0.05);
c = lg.el(idx, 1);
f0 = 0.25;
for j = 1:numel(idx)
    p = floor((j - 1) / per);
    if mod(p, 2) == 1
        c(j) = 1.009 + 0.02 * sin(2 * pi * f0 * lg.te2(idx(j)));
    end
end
lg.el(idx, 1) = c;
lg.el(idx, 2) = c;
end

function [logs, pv, pe, arb] = fakeLogs()
%FAKELOGS a well-formed synthetic M3-N5 arm: eta searches slots
%   [0,64)/[96,160)/[192,240) with a slow center approach to 1.0 and a
%   pass-through allocator (steps always within the slew limit), v holds
%   during eta slots at 9.0 with dither only while searching. Every gate
%   of m3_eval_arm passes on this base (positive control R2-P0).
Ts2 = 0.05;
te2 = (0:Ts2:240)';
ta = (0:0.001:240)';
nE = numel(te2);
arb = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 64.0, ...
    'slotV', 32.0);
searchE = false(nE, 1); searchV = false(nE, 1);
for k = 1:nE
    ro = m3_schedule(te2(k), arb);
    searchE(k) = strcmp(ro.eta, 'search');
    searchV(k) = strcmp(ro.v, 'search');
end
% eta center: 0.25% approach per SEARCH sample, frozen in hold runs; the
% step stays below the eta slew budget so the applied pass-through is
% exact (no constructed lag)
cE = zeros(nE, 1);
center = 0.8;
dithE = 0.02 * sin(2 * pi * 0.25 * te2);
for k = 1:nE
    if searchE(k)
        center = center + (1.0 - center) * 0.0025;
    end
    cE(k) = center;
end
candE = cE + dithE .* searchE;
% v: constant center 9.0, dither only in its own slots
dithV = 0.3 * sin(2 * pi * 0.25 * te2);
candV = 9.0 + dithV .* searchV;
% rate-limited applied traces (pass-through within limits, ramps at the
% hold->search transitions): eta limit 0.05*Ts, v limit 2.0*Ts
applE = zeros(nE, 1); applV = zeros(nE, 1);
applE(1) = candE(1); applV(1) = candV(1);
for k = 2:nE
    applE(k) = applE(k - 1) + max(-0.05 * Ts2, min(0.05 * Ts2, ...
        candE(k) - applE(k - 1)));
    applV(k) = applV(k - 1) + max(-2.0 * Ts2, min(2.0 * Ts2, ...
        candV(k) - applV(k - 1)));
end
el = [candE, applE, zeros(nE, 1), zeros(nE, 1)];
% 1 ms buses: status 2 from t>=0.005, v ref/v meas follow the applied v
nA = numel(ta);
Mb = zeros(nA, 7);
Mb(:, 1) = interp1(te2, applV, ta, 'previous', applV(1));
Mb(:, 4) = double(ta >= 0.005) * 2;
Mb(:, 7) = Mb(:, 1);
A = zeros(nA, 35);
A(:, 10) = 0;          % yaw rate
A(:, 11:18) = 1500;    % pwm
logs = struct('Mb', Mb, 'tb', ta, 'A', A, 'ta', ta, ...
    'Pe', 200 * ones(nA, 1), 'PeE', 200 * ones(nE, 1), ...
    'el', el, 'te2', te2);
pv = struct('mode', 'm3', 'center0', 9.0, 'lower', 6.0, 'upper', 12.0, ...
    'amplitude', 0.3, 'frequency', 0.25, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 6e-3, 'rateLimit', 2.0);
pe = struct('mode', 'm3', 'center0', 1.0, 'lower', 0.75, 'upper', 1.25, ...
    'amplitude', 0.02, 'frequency', 0.25, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 2e-4, 'rateLimit', 0.05);
end

% ---------------------------------------------------------------------------
function ok = entryRestoreMatrix()
%ENTRYRESTOREMATRIX targeted caller-state x exit matrix (rules 3.5/4.3).
%   Rows actually executed, printed row by row:
%     states {finite, empty, NaN, Inf} x pre-write exits {'trials',
%     'cfgmismatch'}; {finite, NaN} x after-write exits {'savefail',
%     'postwrite'}; {finite} x success exit (subset segment); and the
%     boundary entry {finite} x after-write. NOT covered here: empty/NaN/
%     Inf x after-write/success for the boundary entry, and the state
%     matrix of m3_aggregate_batch (it writes no globals).
ok = true;
ok = ok && entryRow('finite', 'trials', 'air:None');
ok = ok && entryRow('empty', 'trials', 'air:None');
ok = ok && entryRow('NaN', 'trials', 'air:None');
ok = ok && entryRow('Inf', 'trials', 'air:None');
ok = ok && entryRow('finite', 'cfgmismatch', 'air:M3Trials:ConfigDrift');
ok = ok && entryRow('NaN', 'cfgmismatch', 'air:M3Trials:ConfigDrift');
ok = ok && entryRow('finite', 'savefail', 'air:M3Trials:InjectedSaveFail');
ok = ok && entryRow('finite', 'postwrite', 'air:M3Trials:InjectedPostWrite');
ok = ok && entryRow('NaN', 'postwrite', 'air:M3Trials:InjectedPostWrite');
ok = ok && entryRow('finite', '', 'air:None');
ok = ok && boundaryRow('finite');
end

function ok = entryRow(stateName, hook, wantId)
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
m3v_clear();
setState(stateName);
expState = snapshotGlobals();
gotErr = 'air:None';
res = [];
try
    if isempty(hook)
        res = run_air_m3_trials('', {'B0-N'}, '');
        assert(res.pass, 'air:M3Verify:SubsetFailed', ...
            'success-exit subset segment unexpectedly failed');
    elseif any(strcmp(hook, {'trials', 'cfgmismatch'}))
        res = run_air_m3_trials(hook, 'full', '');
        if strcmp(hook, 'trials')
            assert(~res.pass, 'air:M3Verify:HookSilent', ...
                'trials hook must return pass=false');
        end
    else
        run_air_m3_trials(hook, {'B0-N'}, '');
        error('air:M3Verify:HookSilent', 'hook %s did not throw', hook);
    end
catch err
    if ~strcmp(err.identifier, 'air:M3Verify:SubsetFailed') && ...
            ~strcmp(err.identifier, 'air:M3Verify:HookSilent')
        gotErr = err.identifier;
    else
        rethrow(err);
    end
end
assert(strcmp(gotErr, wantId), ...
    'row %s x %s: expected %s got %s', stateName, hook, wantId, gotErr);
assertRestored(stateName, expState);
if isempty(hook)
    fprintf('R2-M   trials entry    %-6s x success(subset)         restored\n', ...
        stateName);
elseif strcmp(hook, 'trials')
    fprintf('R2-M   trials entry    %-6s x pre-write return        restored\n', ...
        stateName);
elseif strcmp(hook, 'cfgmismatch')
    fprintf('R2-M   trials entry    %-6s x cfgmismatch(post-cfg)   restored\n', ...
        stateName);
else
    fprintf('R2-M   trials entry    %-6s x %s (after-write) restored\n', ...
        stateName, hook);
end
m3v_clear();
ok = true;
end

function ok = boundaryRow(stateName)
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
m3v_clear();
setState(stateName);
expState = snapshotGlobals();
gotErr = 'air:None';
try
    run_air_m3_boundary('postwrite');
    error('air:M3Verify:HookSilent', 'boundary postwrite did not throw');
catch err
    if ~strcmp(err.identifier, 'air:M3Verify:HookSilent')
        gotErr = err.identifier;
    else
        rethrow(err);
    end
end
assert(strcmp(gotErr, 'air:M3Boundary:InjectedPostWrite'), ...
    'boundary row: expected InjectedPostWrite got %s', gotErr);
assertRestored(stateName, expState);
fprintf('R2-M   boundary entry  %-6s x postwrite (after-write) restored\n', ...
    stateName);
m3v_clear();
ok = true;
end

function setState(name)
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
switch name
    case 'finite'
        M0C_ESC_PARAMS = struct('mode', 'esc', 'center0', 7.7);
        M2_ETA_PARAMS = struct('mode', 'esc', 'center0', 0.91);
        M2_ETA_APPLIED = 0.9134;
        M3_ARB_PARAMS = struct('enable', 'off');
    case 'empty'
        M0C_ESC_PARAMS = []; M2_ETA_PARAMS = [];
        M2_ETA_APPLIED = []; M3_ARB_PARAMS = [];
    case 'NaN'
        M0C_ESC_PARAMS = struct('mode', 'esc', 'center0', NaN);
        M2_ETA_PARAMS = struct('mode', 'esc', 'center0', NaN);
        M2_ETA_APPLIED = NaN;
        M3_ARB_PARAMS = struct('enable', 'off', 'slotEta', NaN);
    case 'Inf'
        M0C_ESC_PARAMS = struct('mode', 'esc', 'center0', Inf);
        M2_ETA_PARAMS = struct('mode', 'esc', 'center0', Inf);
        M2_ETA_APPLIED = Inf;
        M3_ARB_PARAMS = struct('enable', 'off', 'slotEta', Inf);
end
end

function assertRestored(stateName, expState)
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
got = snapshotGlobals();
assert(isequaln(got.M0C, expState.M0C) && ...
    isequaln(got.M2P, expState.M2P) && ...
    isequaln(got.M2A, expState.M2A) && ...
    isequaln(got.M3A, expState.M3A), ...
    'air:M3Verify:Restore', ...
    'caller state (%s) not restored exactly-as-found', stateName);
end

% ---------------------------------------------------------------------------
function ok = runAggregate(segDirs, wsRoot)
%RUNAGGREGATE manifest tamper negatives on COPIES of the real batch
%   segments (rules section 2 rules 4/5/6: old-batch/mixed-source,
%   missing/duplicate stages, FAIL rows). The copies live under
%   results/m3_round2_neg/ (gitignored); the real archives are read-only.
assert(numel(segDirs) >= 3, 'air:M3Verify:NoBatch', ...
    'pass the real segment dirs (at least 3) for the aggregate negatives');
negRoot = fullfile(wsRoot, 'results', 'm3_round2_neg');
if exist(negRoot, 'dir')
    rmdir(negRoot, 's');
end
mkdir(negRoot);
cases = { ...
    'SourceMismatch', @() cSourceMismatch(negRoot, segDirs); ...
    'DuplicateArm',   @() cDuplicateArm(negRoot, segDirs); ...
    'MissingArm',     @() cMissingArm(negRoot, segDirs); ...
    'ExtraArm',       @() cExtraArm(negRoot, segDirs); ...
    'ArmFailed',      @() cArmFailed(negRoot, segDirs); ...
    'ArchiveMissing', @() cArchiveMissing(negRoot, segDirs); ...
    'ReproSession',   @() cReproSession(negRoot, segDirs); ...
    'ReproGrid',      @() cReproGrid(negRoot, segDirs)};
want = { ...
    'air:M3Agg:SourceMismatch', 'air:M3Agg:DuplicateArm', ...
    'air:M3Agg:MissingArm', 'air:M3Agg:ExtraArm', 'air:M3Agg:ArmFailed', ...
    'air:M3Agg:ArchiveMissing', 'air:M3Agg:ReproSession', ...
    'air:M3Agg:ReproGrid'};
ok = true;
for j = 1:size(cases, 1)
    dirs = cases{j, 2}();
    got = catchId(@() m3_aggregate_batch(dirs));
    assert(strcmp(got, want{j}), ...
        'aggregate negative %s: expected %s got %s', ...
        cases{j, 1}, want{j}, got);
    fprintf('R2-A   m3_aggregate   %-15s tamper -> rejected (%s)\n', ...
        cases{j, 1}, want{j});
end
fprintf('aggregate negatives: %d/%d rejected with exact ids\n', ...
    size(cases, 1), size(cases, 1));
end

function saveResult(dirName, result)
f = fullfile(dirName, 'result.mat');
save(f, 'result');
end

function dirs = copySegs(negRoot, segDirs)
for d = 1:numel(segDirs)
    dst = fullfile(negRoot, sprintf('seg%d', d));
    copyfile(segDirs{d}, dst);
    dirs{d} = dst; %#ok<AGROW>
end
end

function dirs = cSourceMismatch(negRoot, segDirs)
dirs = copySegs(negRoot, segDirs);
f = fullfile(findArmSeg(dirs, 'M3_N2'), 'result.mat');
S = load(f, 'result');
result = S.result;
result.binding.gitCommit = repmat('0', 1, 40);
save(f, 'result');
end

function dirs = cDuplicateArm(negRoot, segDirs)
dirs = copySegs(negRoot, segDirs);
dirs{end + 1} = dirs{1};
end

function dirs = cMissingArm(negRoot, segDirs)
dirs = copySegs(negRoot, segDirs);
f = fullfile(findArmSeg(dirs, 'M3_N1'), 'result.mat');
S = load(f, 'result');
result = S.result;
result.runs = rmfield(result.runs, 'M3_N1');
save(f, 'result');
end

function dirs = cExtraArm(negRoot, segDirs)
dirs = copySegs(negRoot, segDirs);
f = fullfile(findArmSeg(dirs, 'M3_N1'), 'result.mat');
S = load(f, 'result');
result = S.result;
result.runs.M3_ZZ = result.runs.M3_N1;
save(f, 'result');
end

function dirs = cArmFailed(negRoot, segDirs)
dirs = copySegs(negRoot, segDirs);
f = fullfile(findArmSeg(dirs, 'M3_N2'), 'result.mat');
S = load(f, 'result');
result = S.result;
result.runs.M3_N2.ok = false;
save(f, 'result');
end

function dirs = cArchiveMissing(negRoot, segDirs)
dirs = copySegs(negRoot, segDirs);
delete(fullfile(findArmSeg(dirs, 'M3_N1'), 'M3-N1.mat'));
end

function dirs = cReproSession(negRoot, segDirs)
% split M3-R1 into its own fabricated segment with a DIFFERENT runId:
% all 14 arms appear exactly once, but the repro pair is cross-session
% (the segment holding M3-R1 is LOCATED dynamically -- the batch layout
% may use any segmentation)
dirs = copySegs(negRoot, segDirs);
r1dir = findArmSeg(dirs, 'M3_R1');
f = fullfile(r1dir, 'result.mat');
S = load(f, 'result');
full = S.result;
result = full;
result.runs = rmfield(result.runs, 'M3_R1');
save(f, 'result');
mini = fullfile(negRoot, 'segMini');
mkdir(mini);
copyfile(fullfile(r1dir, 'M3-R1.mat'), mini);
result = full;
result.runs = struct('M3_R1', full.runs.M3_R1);
result.binding.runId = 'fab-run-id';
save(fullfile(mini, 'result.mat'), 'result');
dirs{end + 1} = mini;
end

function dirs = cReproGrid(negRoot, segDirs)
dirs = copySegs(negRoot, segDirs);
% result.mat carries no logs (log-free segment results): tamper the
% per-arm archive so the repro pair grids mismatch
f = fullfile(findArmSeg(dirs, 'M3_R1'), 'M3-R1.mat');
S = load(f, 'r');
r = S.r;
r.logs.el = r.logs.el(1:4000, :);
save(f, 'r');
end

function d = findArmSeg(dirs, fieldName)
%FINDARMSEG the copied segment dir whose result contains the arm.
for j = 1:numel(dirs)
    S = load(fullfile(dirs{j}, 'result.mat'), 'result');
    if isfield(S.result.runs, fieldName)
        d = dirs{j};
        return;
    end
end
error('air:M3Verify:Internal', 'arm %s not found in any segment', fieldName);
end

% ---------------------------------------------------------------------------
function printReport()
fprintf(['closure mapping: F1 assertFrozenConfig + per-arm sets ' ...
    '(unit B1 legality, R2 hook cfgmismatch);\n' ...
    'F2/F3 single m3_eval_arm path (R2-P0/N4/N5/N6/N7/N8 + B7);\n' ...
    'F4 binding + aggregate contract (R2-A x8) + after-write restores ' ...
    '(R2-M) + R1/vTrk hard gates;\n' ...
    'F5 dual-track energy prints (unit B7 coverage fixtures + batch ' ...
    'prints);\nF6 docs/registry sync (see evidence report).\n' ...
    'batch verdict = m3_aggregate_batch over the frozen segments\n']);
end

% ---------------------------------------------------------------------------
function id = catchId(fn)
id = 'air:None';
try
    fn();
catch e
    id = e.identifier;
end
end

function s = snapshotGlobals()
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
s = struct('M0C', M0C_ESC_PARAMS, 'M2P', M2_ETA_PARAMS, ...
    'M2A', M2_ETA_APPLIED, 'M3A', M3_ARB_PARAMS);
end

function m3v_restore(s)
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
M0C_ESC_PARAMS = s.M0C; M2_ETA_PARAMS = s.M2P;
M2_ETA_APPLIED = s.M2A; M3_ARB_PARAMS = s.M3A;
clear('m0c_vref_esc'); clear('m2_eta_esc');
end

function m3v_clear()
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
M0C_ESC_PARAMS = []; M2_ETA_PARAMS = [];
M2_ETA_APPLIED = []; M3_ARB_PARAMS = [];
end

function s = ternaryStr(c, a, b)
if c
    s = a;
else
    s = b;
end
end
