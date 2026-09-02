%VERIFY_M2_ROUND4_CLOSURE Round-4 closure verification (round-3 report §9,
%   amended by the round-4 report §6), STAGED execution.
%   Runs the TARGETED acceptance-automation matrix (rules §4.3: all
%   combinations RELEVANT to the fixed defect class, with the executed case
%   list declared below) against the M2 acceptance entries:
%     C1 unit-test controlled failure, TWO entry states (clean + stale
%        sentinel), globals restored exactly AND persistent-fresh proven
%        DIRECTLY by a FORWARD-time probe (warm the esc center far from
%        center0, inject the failure, then call at t = warm end + Ts: a
%        worked cleanup re-initializes, a missed clear CONTINUES the
%        drifted state; R4-F2)
%     C2 chain error exits compare/injection/trials, TWO entry states
%        (clean + stale sentinel; R4-F3 extension)
%     C3 run_air_m2_trials standalone: controlled failure + full success
%        from a stale-sentinel state
%     C4 chain tail throws air:M2Session:TrialsFailed with archive path
%     C5 dirty-session back-to-back chains 2/2 PASS, in-session CSV
%        determinism (h1==h2) and gate values within the registered
%        +/-0.015 pp jitter of the round-3/4 values
%
%   STAGES (why: R2022b accumulates heap corruption inside ONE process
%   beyond roughly 40-50 model re-simulations -- three crashes at the same
%   depth on 2026-09-02, with and without a concurrent GUI session and a
%   private codegen cache; recorded as an environment limitation). Each
%   sim-bearing stage runs in its OWN MATLAB process and stays far below
%   that depth; C5's two chains stay in one process because the h1==h2
%   determinism claim is a SAME-session-history claim:
%     verify_m2_round4_closure('fail')        self error-path (fast)
%     verify_m2_round4_closure('c1c2stale')   C1a/C1b + C2 stale (14 sims)
%     verify_m2_round4_closure('c2clean')     C2 clean (14 sims)
%     verify_m2_round4_closure('c3')          standalone trials (9 sims)
%     verify_m2_round4_closure('c5')          dirty double chain (30 sims)
%     verify_m2_round4_closure('report')      aggregate + verdict (0 sims)
%   '' or 'all' runs the whole matrix in one process (GUI convenience;
%   batch drivers must use the staged form).
%   Stage rows land in <repo>/results/round4_closure_staged/<stage>.csv;
%   'report' aggregates them into a timestamped archive and checks the
%   declared row count.
%
%   SELF-COMPLIANCE (round-4 R4-F1): every entry (including this verifier)
%   snapshots the caller's M2_ETA_PARAMS / M2_ETA_APPLIED and restores them
%   on exit (success AND error, function-frame onCleanup).
%
%   Declared matrix: 15 rows --
%     unit error exit     x {clean, stale}                          = 3 rows
%       (stale adds the persistent-fresh direct probe row)
%     chain compare-err   x {clean, stale}                          = 2 rows
%     chain injection-err x {clean, stale}                          = 2 rows
%     chain trials-err    x {clean, stale}                          = 2 rows
%     trials standalone   x {stale} x {controlled-failure, success}  = 2 rows
%     chain success       x {round-2 residue, chain-1 residue}      = 2 rows
%     C5 determinism + jitter invariants                            = 2 rows
%   NOT covered (targeted-matrix boundary): success exits at clean entry,
%   the third entry state (post-error residue) per exit, clean-entry
%   double chains.

function ok = verify_m2_round4_closure(stage)
if nargin < 1
    stage = '';
end
if strcmp(stage, 'all')
    stage = '';
end
valid = {'', 'fail', 'c1c2stale', 'c2clean', 'c3', 'c5', 'report'};
assert(any(strcmp(stage, valid)), 'air:M2Verify:BadStage', ...
    'stage must be one of %s', strjoin(valid, '|'));

adapterDir = fileparts(mfilename('fullpath'));
addpath(adapterDir);
stagedDir = fullfile(fileparts(fileparts(adapterDir)), 'results', ...
    'round4_closure_staged');
if ~exist(stagedDir, 'dir')
    mkdir(stagedDir);
end

global M2_ETA_PARAMS M2_ETA_APPLIED
% R4-F1: snapshot the CALLER's globals and restore them on exit (success
% and error). The verifier honours the contract it enforces.
verSavedParams = [];
verSavedApplied = [];
if ~isempty(M2_ETA_PARAMS), verSavedParams = M2_ETA_PARAMS; end
if ~isempty(M2_ETA_APPLIED) && isfinite(M2_ETA_APPLIED)
    verSavedApplied = M2_ETA_APPLIED;
end
verCleanup = onCleanup(@() m2ver_restore_globals( ...
    verSavedParams, verSavedApplied)); %#ok<NASGU>

% self-injection hook: fires EARLY (after the restore contract is set up
% and the globals were touched) so the verifier's own error-path restore
% can be live-injected cheaply (round-4 closure condition 1)
if strcmp(stage, 'fail')
    setSentinels();
    assert(false, 'air:M2Verify:InjectedFailure', ...
        'controlled internal failure after globals were touched');
end

sentinelParams = struct('mode', 'esc', 'center0', 0.9134);
sentinelApplied = 0.913456789;
dirtyParams = struct('mode', 'esc', 'center0', 1.0);
dirtyApplied = 0.99914776890319873;   % exact round-2 report residue
round3Gate = [-0.2598475888; -0.2921145534; -0.2261741040];

matrix = {};
runStage = @(name) isempty(stage) || strcmp(stage, name);

% ---- C1a: unit controlled failure from a CLEAN entry state --------------
if runStage('c1c2stale')
    clearGlobals();
    fired = false; errId = '<none>';
    try
        test_m2_eta_esc_unit('unit');
    catch e
        fired = true; errId = e.identifier;
    end
    assert(fired && strcmp(errId, 'air:M2Test:InjectedFailure'), ...
        'C1a: injected unit failure did not fire (%s)', errId);
    checkRestored('C1a unit-failure (clean)', [], []);
    matrix = addRow(matrix, 'C1a unit controlled failure', 'clean', ...
        'assert exit', 'PASS');

    % ---- C1b: stale entry state + direct persistent-fresh probe ----------
    clear('m2_eta_esc');
    warmProbePersistent();
    setSentinels();
    fired = false; errId = '<none>';
    try
        test_m2_eta_esc_unit('unit');
    catch e
        fired = true; errId = e.identifier;
    end
    assert(fired && strcmp(errId, 'air:M2Test:InjectedFailure'), ...
        'C1b: injected unit failure did not fire (%s)', errId);
    checkRestored('C1b unit-failure (stale)', sentinelParams, sentinelApplied);
    outErr = probeCallForward(false);
    clear('m2_eta_esc');
    outFresh = probeCallForward(false);
    maxDiffFresh = max(abs(outErr - outFresh));
    assert(maxDiffFresh == 0, ...
        'C1b: post-error persistent state differs from fresh (%g)', ...
        maxDiffFresh);
    outDrift = probeCallForward(true);
    assert(max(abs(outDrift - outFresh)) > 1e-6, ...
        'C1b: probe is vacuous (drifted state not distinguishable)');
    matrix = addRow(matrix, 'C1b unit controlled failure', ...
        'stale sentinel', 'assert exit', 'PASS');
    matrix = addRow(matrix, sprintf( ...
        'C1b persistent-fresh direct probe (maxDiff %.3g)', maxDiffFresh), ...
        'stale sentinel', 'assert exit', 'PASS');
end

% ---- C2: chain error exits, clean and stale variants ---------------------
for st = {'stale', 'clean'}
    state = st{1};
    if ~runStage('c1c2stale') && strcmp(state, 'stale')
        continue
    end
    if ~runStage('c2clean') && strcmp(state, 'clean')
        continue
    end
    if strcmp(state, 'clean')
        clearGlobals();
        expParams = [];
        expApplied = [];
    else
        setSentinels();
        expParams = sentinelParams;
        expApplied = sentinelApplied;
    end
    exits = {'compare', 'air:M2Session:CompareFailed'; ...
        'injection', 'air:M2Session:InjectionFailed'; ...
        'trials', 'air:M2Session:TrialsFailed'};
    for k = 1:size(exits, 1)
        threw = false; errId = '<none>'; msg = '';
        try
            run_m2_session_chain(exits{k, 1});
        catch e
            threw = true; errId = e.identifier; msg = e.message;
        end
        assert(threw, 'C2 %s/%s: chain did not throw', exits{k, 1}, state);
        assert(strcmp(errId, exits{k, 2}), ...
            'C2 %s/%s: unexpected error id %s', exits{k, 1}, state, errId);
        if strcmp(exits{k, 1}, 'trials')
            assert(contains(msg, 'injected'), ...
                'C2 trials/%s: archive path missing from message', state);
        end
        checkRestored(sprintf('C2 %s-failure (%s)', exits{k, 1}, state), ...
            expParams, expApplied);
        matrix = addRow(matrix, ...
            sprintf('C2 chain %s error exit', exits{k, 1}), state, ...
            'assert exit', 'PASS');
    end
end

% ---- C3: standalone trials, controlled failure + success ----------------
if runStage('c3')
    setSentinels();
    resF = run_air_m2_trials('trials');
    assert(~resF.pass, 'C3: injected trials run did not fail');
    checkRestored('C3 trials controlled failure', sentinelParams, ...
        sentinelApplied);
    matrix = addRow(matrix, 'C3 trials standalone controlled failure', ...
        'stale sentinel', 'normal return', 'PASS');

    fprintf('C3: running one full standalone trials pass (several minutes)...\n');
    setSentinels();
    resOK = run_air_m2_trials();
    assert(resOK.pass, 'C3: full trials run failed');
    checkRestored('C3 trials full success', sentinelParams, sentinelApplied);
    matrix = addRow(matrix, 'C3 trials standalone full success', ...
        'stale sentinel', 'normal return', 'PASS');
end

% ---- C5: dirty session, back-to-back chains 2/2 + value agreement --------
if runStage('c5')
    M2_ETA_PARAMS = dirtyParams;
    M2_ETA_APPLIED = dirtyApplied;
    clear('m2_eta_esc');
    arch = cell(1, 2);
    for c = 1:2
        fprintf('C5: dirty-session chain %d of 2...\n', c);
        resC = run_m2_session_chain();
        assert(resC.pass, 'C5: chain %d failed', c);
        arch{c} = char(resC.archiveDir);
    end
    h1 = sha256file(fullfile(arch{1}, 'summary.csv'));
    h2 = sha256file(fullfile(arch{2}, 'summary.csv'));
    assert(strcmp(h1, h2), ...
        'C5: chain 1/2 summary.csv hashes differ (%s vs %s)', h1, h2);
    todayGate = zeros(3, 1);
    Tk = readtable(fullfile(arch{2}, 'pairs.csv'));
    for k = 1:3
        todayGate(k) = Tk.delta_E_pct(k);
    end
    assert(all(abs(todayGate - round3Gate) <= 0.015), ...
        'C5: gate dE left the +/-0.015 pp jitter band');
    matrix = addRow(matrix, 'C5 dirty back-to-back chain 1', ...
        'round-2 residue', 'success', 'PASS');
    matrix = addRow(matrix, 'C5 dirty back-to-back chain 2', ...
        'chain-1 trials residue', 'success', 'PASS');
    matrix = addRow(matrix, 'C5 in-session CSV determinism (h1==h2)', ...
        'chain-1 trials residue', 'success', 'PASS');
    matrix = addRow(matrix, 'C5 gate dE within jitter of round-3 values', ...
        'n/a', 'success', 'PASS');
    save(fullfile(stagedDir, 'c5.mat'), 'arch', 'h1', 'h2', 'todayGate', ...
        'round3Gate');
end

% ---- stage output / aggregate --------------------------------------------
if ~isempty(stage) && ~strcmp(stage, 'report')
    T = cell2table(matrix, 'VariableNames', {'test', 'entryState', ...
        'exitPath', 'verdict'});
    writetable(T, fullfile(stagedDir, [stage '.csv']));
    disp(T);
    fprintf('STAGE %s PASS (%d checks)\n', stage, size(T, 1));
    ok = true;
    return;
end

if strcmp(stage, 'report')
    stageFiles = {'c1c2stale', 'c2clean', 'c3', 'c5'};
    rows = {};
    for k = 1:numel(stageFiles)
        f = fullfile(stagedDir, [stageFiles{k} '.csv']);
        assert(exist(f, 'file'), 'air:M2Verify:StageMissing', ...
            'stage output missing: %s', f);
        Ts = readtable(f, 'TextType', 'string', 'Delimiter', ',', ...
            'VariableNamingRule', 'preserve');
        assert(all(Ts.verdict == "PASS"), ...
            'air:M2Verify:StageFailed', 'stage %s has non-PASS rows', ...
            stageFiles{k});
        for j = 1:height(Ts)
            rows = [rows; {char(Ts.test{j}), char(Ts.entryState{j}), ...
                char(Ts.exitPath{j}), char(Ts.verdict{j})}]; %#ok<AGROW>
        end
    end
    assert(size(rows, 1) == 15, 'air:M2Verify:RowCountMismatch', ...
        'declared 15 matrix rows, aggregated %d', size(rows, 1));
    T = cell2table(rows, 'VariableNames', {'test', 'entryState', ...
        'exitPath', 'verdict'});
    S = load(fullfile(stagedDir, 'c5.mat'));
    outDir = fullfile(fileparts(fileparts(adapterDir)), 'results', ...
        'round4_closure', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    writetable(T, fullfile(outDir, 'matrix.csv'));
    save(fullfile(outDir, 'result.mat'), '-struct', 'S');
    disp(T);
    fprintf('ROUND-4 CLOSURE VERIFICATION PASS (%d checks)\n', size(T, 1));
    fprintf('Archive: %s\n', outDir);
    ok = true;
    return;
end

% monolithic '' path (GUI convenience)
T = cell2table(matrix, 'VariableNames', {'test', 'entryState', ...
    'exitPath', 'verdict'});
disp(T);
outDir = fullfile(fileparts(fileparts(adapterDir)), 'results', ...
    'round4_closure', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
if ~exist(outDir, 'dir'), mkdir(outDir); end
writetable(T, fullfile(outDir, 'matrix.csv'));
save(fullfile(outDir, 'result.mat'), 'arch', 'h1', 'h2', 'todayGate', ...
    'round3Gate', 'maxDiffFresh');
fprintf('ROUND-4 CLOSURE VERIFICATION PASS (%d checks)\n', size(T, 1));
fprintf('Archive: %s\n', outDir);
ok = true;
end

% ---------------------------------------------------------------------------
function clearGlobals()
%CLEARGLOBALS clean-entry variant: empty = safe identity default.
global M2_ETA_PARAMS M2_ETA_APPLIED
M2_ETA_PARAMS = [];
M2_ETA_APPLIED = [];
clear('m2_eta_esc');
end

function setSentinels()
%SETSENTINELS distinct non-identity entry values for restore checking.
global M2_ETA_PARAMS M2_ETA_APPLIED
M2_ETA_PARAMS = struct('mode', 'esc', 'center0', 0.9134);
M2_ETA_APPLIED = 0.913456789;
end

function checkRestored(label, expParams, expApplied)
%CHECKRESTORED exact-equality check of the caller entry state (empty
%   expected = empty restored).
global M2_ETA_PARAMS M2_ETA_APPLIED
assert(isequal(M2_ETA_PARAMS, expParams), ...
    '%s: M2_ETA_PARAMS not restored exactly', label);
if isempty(expApplied)
    assert(isempty(M2_ETA_APPLIED), ...
        '%s: M2_ETA_APPLIED not restored to empty (%g)', label, ...
        M2_ETA_APPLIED);
else
    assert(M2_ETA_APPLIED == expApplied, ...
        '%s: M2_ETA_APPLIED not restored exactly (%g)', label, ...
        M2_ETA_APPLIED);
end
end

function warmProbePersistent()
%WARMPROBEPERSISTENT drive m2_eta_esc with a large gain so the esc center
%   drifts far from center0 -- a later missed clear is then observable via
%   a forward-time probe call (continuation vs re-initialization).
global M2_ETA_PARAMS M2_ETA_APPLIED
M2_ETA_PARAMS = struct('mode', 'esc', 'center0', 0.9, 'gain', 0.5);
M2_ETA_APPLIED = 1.0;
etaA = 0.9;
for k = 1:20
    u = probeInput(k * 0.05, bowlP(etaA));
    out = m2_eta_esc(u);
    etaA = out(1);
end
end

function out = probeCallForward(drifted)
%PROBECALLFORWARD one m2_eta_esc call at t = 1.05 (FORWARD of the warm
%   end 1.00). drifted = false -> fresh/re-init semantics under test;
%   drifted = true -> re-warm first so the call CONTINUES the drifted
%   state (sensitivity self-check).
global M2_ETA_PARAMS
M2_ETA_PARAMS = struct('mode', 'esc', 'center0', 0.9, 'gain', 0.5);
if drifted
    warmProbePersistent();
end
u = probeInput(1.05, bowlP(0.9));
out = m2_eta_esc(u);
end

function u = probeInput(t, P)
%PROBEINPUT 35-element m2_eta_esc input vector (healthy, eta_act = 1).
rpm = 500 * 60 / (2 * pi);
u = [t; 9.0; P; 0.0; zeros(6, 1); 1500 * ones(8, 1); ...
    [rpm * ones(4, 1); rpm * ones(4, 1)]; zeros(8, 1); 0];
u = u(:);
end

function P = bowlP(eta)
%BOWLP analytic bowl power, g(1) is the minimum (mirrors the unit test).
g = @(x) (1 + x^3) / (1 + x^2)^1.5;
P = 251.0 * g(eta) / g(1.0);
end

function matrix = addRow(matrix, test, entryState, exitPath, verdict)
matrix = [matrix; {test, entryState, exitPath, verdict}]; %#ok<AGROW>
end

function m2ver_restore_globals(savedParams, savedApplied)
%M2VER_RESTORE_GLOBALS R4-F1: put the M2 globals back to the CALLER's
%   entry-time values (empty stays empty -- the safe identity default), on
%   success and on any error/assert path. Persistent state is cleared by
%   the entries under test; clearing persistent is NOT a substitute for
%   restoring the caller's globals and vice versa.
global M2_ETA_PARAMS M2_ETA_APPLIED
if isempty(savedParams)
    M2_ETA_PARAMS = [];
else
    M2_ETA_PARAMS = savedParams;
end
if isempty(savedApplied)
    M2_ETA_APPLIED = [];
else
    M2_ETA_APPLIED = savedApplied;
end
end

function h = sha256file(fname)
%SHA256FILE lowercase hex SHA-256 of a file.
fid = fopen(fname, 'rb');
assert(fid > 0, 'cannot open %s', fname);
data = fread(fid, '*uint8')';
fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
d = md.digest(data);
h = lower(sprintf('%02x', typecast(int8(d), 'uint8')));
end
