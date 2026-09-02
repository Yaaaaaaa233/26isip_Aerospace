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
%     verify_m2_round4_closure('c5')          dirty double chain (~20 sims,
%                                              R6-F3 MINIMAL nominal set)
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
%   Declared matrix: 42 rows (the archived matrix.csv must match; rules
%   section 4.3 -- the declared list IS the executed list):
%     c1c2stale 6 = unit error exit x {clean, stale} (stale adds the
%                    persistent-fresh direct-probe row)
%                  + chain compare/injection/trials error exits x {stale}
%     c2clean   3 = chain compare/injection/trials error exits x {clean}
%     c3        2 = standalone trials x {controlled-failure, full success}
%     c5        4 = dirty back-to-back chains 2/2 (R6-F3 MINIMAL set:
%                    nominal S1-S3 pairs only, 4 sims per chain), h1==h2
%                    in-session determinism, gate dE within the registered
%                    +/-0.015 pp jitter. Full 9-scenario chains stay
%                    covered once per process by c2clean/c3.
%     contract 27 = 20 state-contract rows (4 entries x 4 caller states
%                    {finite, empty, NaN, Inf}; R5-F1)
%                  + R5-F3 archive-assert negative
%                  + 3 manifest negatives {oldbatch, missing, mixed}
%                    (R5-F2)
%                  + R6-F2 FAIL-verdict negative, R6-F1 verifierSha
%                    mismatch negative, R6-F1 dirty-tree negative
%   NOT covered (targeted-matrix boundary): success exits at clean entry,
%   the third entry state (post-error residue) per exit, clean-entry
%   double chains, full-9-scenario double chains (environment limit,
%   R6-F3: the R2022b heap-corruption depth is reached inside the second
%   full chain; registered as an open environment item).
%
%   SOURCE BINDING (round-6 R6-F1): 'init' records HEAD, the verifier
%   SHA-256 and a clean-tree requirement in the manifest; EVERY stage
%   independently re-captures all three live, hard-fails on 'unknown'/a
%   dirty tree/any mismatch, and stamps its OWN capture into done.mat
%   (never a copy of the manifest value). 'report' re-captures live again,
%   so an aggregate only ever certifies a single-commit clean batch whose
%   verifier file never changed mid-batch.

function ok = verify_m2_round4_closure(stage)
if nargin < 1
    stage = '';
end
if strcmp(stage, 'all')
    stage = '';
end
valid = {'', 'fail', 'init', 'c1c2stale', 'c2clean', 'c3', 'c5', ...
    'contract', 'report'};
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
if ~isempty(M2_ETA_APPLIED)
    % R5-F1: snapshot ANY non-empty value including NaN/Inf -- the
    % restore contract is exactly-as-found (rules v1.2 section 3)
    verSavedApplied = M2_ETA_APPLIED;
end
verCleanup = onCleanup(@() m2ver_restore_globals( ...
    verSavedParams, verSavedApplied));

% self-injection hook: fires EARLY (after the restore contract is set up
% and the globals were touched) so the verifier's own error-path restore
% can be live-injected cheaply (round-4 closure condition 1)
if strcmp(stage, 'fail')
    setSentinels();
    assert(false, 'air:M2Verify:InjectedFailure', ...
        'controlled internal failure after globals were touched');
end

% ---- manifest binding (round-5 R5-F2) ------------------------------------
if strcmp(stage, 'init')
    if exist(stagedDir, 'dir')
        rmdir(stagedDir, 's');   % a new run never inherits old evidence
    end
    mkdir(stagedDir);
    manifest = makeManifest();
    save(fullfile(stagedDir, 'manifest.mat'), 'manifest');
    fprintf('INIT runId=%s\ncommit=%s\nverifier=%s\ntree=clean\n', ...
        manifest.runId, manifest.gitCommit, manifest.verifierSha);
    ok = true;
    return;
end
manifest = [];
if ~isempty(stage)
    f = fullfile(stagedDir, 'manifest.mat');
    assert(exist(f, 'file'), 'air:M2Verify:NoManifest', ...
        ['no manifest in %s -- run verify_m2_round4_closure(''init'') ' ...
        'first; report never aggregates files from an unknown batch']);
    L = load(f, 'manifest');
    manifest = L.manifest;
    % R6-F1 (round-6 reacceptance): every non-init stage INDEPENDENTLY
    % re-establishes the source identity (HEAD, verifier SHA-256, dirty
    % state) and hard-fails on 'unknown', a dirty tree, or any mismatch
    % with the manifest. Stage stamps never copy manifest values.
    assertSourceBound(manifest);
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
            % R5-F3: check the FULL 'archive <path>' string, not a bare
            % literal that only coincides with the deterministic archive
            assert(contains(msg, 'archive injected'), ...
                'C2 trials/%s: message lacks the archive field', state);
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

% ---- C5: dirty session, back-to-back MINIMAL chains 2/2 + agreement ------
% R6-F3 (round-6 reacceptance): the full 9-scenario double chain reaches
% the registered R2022b heap-corruption depth inside the second chain
% (two reproducible mid-chain process exits on 2026-09-02), so C5 now
% uses the MINIMAL set that still proves what C5 exists to prove: dirty
% entry reuse, same-session-history determinism (h1==h2) and gate dE
% against the registered nominal values. The minimal trials set is the
% nominal pairs S1/S2/S3 plus their E2 fixed baseline (4 sims per chain);
% the E1/E3 surface rows, the disturbed pair and the R_esc within-run
% reproducibility remain covered once per process by c2clean/c3 full runs.
if runStage('c5')
    M2_ETA_PARAMS = dirtyParams;
    M2_ETA_APPLIED = dirtyApplied;
    clear('m2_eta_esc');
    arch = cell(1, 2);
    for c = 1:2
        fprintf('C5: dirty-session minimal chain %d of 2...\n', c);
        resC = run_m2_session_chain('', 'nominal');
        assert(resC.pass, 'C5: chain %d failed', c);
        arch{c} = char(resC.archiveDir);
    end
    h1 = sha256file(fullfile(arch{1}, 'summary.csv'));
    h2 = sha256file(fullfile(arch{2}, 'summary.csv'));
    assert(strcmp(h1, h2), ...
        'C5: chain 1/2 summary.csv hashes differ (%s vs %s)', h1, h2);
    todayGate = zeros(3, 1);
    Tk = readtable(fullfile(arch{2}, 'pairs.csv'));
    assert(height(Tk) == 3, 'C5: minimal set must yield the 3 nominal pairs');
    for k = 1:3
        todayGate(k) = Tk.delta_E_pct(k);
    end
    assert(all(abs(todayGate - round3Gate) <= 0.015), ...
        'C5: gate dE left the +/-0.015 pp jitter band');
    matrix = addRow(matrix, ...
        'C5 dirty back-to-back minimal chain 1 (nominal S1-S3)', ...
        'round-2 residue', 'success', 'PASS');
    matrix = addRow(matrix, ...
        'C5 dirty back-to-back minimal chain 2 (nominal S1-S3)', ...
        'chain-1 trials residue', 'success', 'PASS');
    matrix = addRow(matrix, 'C5 in-session CSV determinism (h1==h2)', ...
        'chain-1 trials residue', 'success', 'PASS');
    matrix = addRow(matrix, ...
        'C5 gate dE within jitter of round-3 values (nominal set)', ...
        'n/a', 'success', 'PASS');
    save(fullfile(stagedDir, 'c5.mat'), 'arch', 'h1', 'h2', 'todayGate', ...
        'round3Gate');
end

% ---- CONTRACT + negative proofs (round-5 R5-F1/F2/F3) --------------------
if runStage('contract')
    matrix = [matrix; runContract(stagedDir, manifest)];
end

% ---- stage output / aggregate --------------------------------------------
if ~isempty(stage) && ~strcmp(stage, 'report')
    assert(~isempty(manifest), 'air:M2Verify:NoManifest', ...
        'stage run without manifest');
    T = cell2table([matrix, repmat({manifest.runId}, ...
        size(matrix, 1), 1)], 'VariableNames', {'test', 'entryState', ...
        'exitPath', 'verdict', 'runId'});
    writetable(T, fullfile(stagedDir, [stage '.csv']));
    % R6-F1: re-capture the source identity at STAMP time (the stage's own
    % live fingerprint, never a copy of the manifest's init-time values);
    % the assert inside rejects a tree that got dirty mid-stage.
    fpStamp = assertSourceBound(manifest);
    done = struct('runId', manifest.runId, 'gitCommit', ...
        fpStamp.gitCommit, 'verifierSha', fpStamp.verifierSha, ...
        'finished', datetime('now'));
    save(fullfile(stagedDir, [stage '.done.mat']), 'done');
    disp(T);
    fprintf('STAGE %s PASS (%d checks)\n', stage, size(T, 1));
    ok = true;
    return;
end

if strcmp(stage, 'report')
    validateStaged(stagedDir);   % rejects stale / missing / mixed / FAIL
                                % evidence (R6-F2: every verdict row)
    n = writeAggregate(stagedDir);   % asserts the declared rows itself
    fprintf('ROUND-4/5/6 CLOSURE VERIFICATION PASS (%d checks)\n', n);
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
    assert(isequaln(M2_ETA_APPLIED, expApplied), ...
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
matrix = [matrix; {test, entryState, exitPath, verdict}];
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


function matrix2 = runContract(stagedDir, manifest)
%RUNCONTRACT round-5 closure conditions 1-3 + round-6 R6 additions:
%   exact-restore contract for finite/empty/NaN/Inf caller states on
%   success and error exits, plus the manifest, archive-assert, FAIL-row,
%   verifierSha and dirty-tree negative proofs. 27 rows.
matrix2 = {};
% text-safe state names: readtable would otherwise infer the
% entryState column as NUMERIC (NaN/Inf parse as doubles) and drop
% the finite/empty rows as incomplete -- round-5 staged run finding
states = {'finite', 0.913456789; 'empty', []; 'NaNval', NaN; 'Infval', Inf};

% unit entry: 4 states x {success, 'unit' error} (fast, pure MATLAB)
for k = 1:size(states, 1)
    setAppliedState(states{k, 2});
    okU = test_m2_eta_esc_unit();
    assert(okU);
    assertStateRestored('CT unit success', states{k, 1}, states{k, 2});
    matrix2 = [matrix2; {sprintf('CT unit success exit (%s)', ...
        states{k, 1}), states{k, 1}, 'normal return', 'PASS'}]; %#ok<AGROW>
    setAppliedState(states{k, 2});
    threw = false;
    try
        test_m2_eta_esc_unit('unit');
    catch e
        threw = strcmp(e.identifier, 'air:M2Test:InjectedFailure');
    end
    assert(threw, 'CT unit %s: injection did not fire', states{k, 1});
    assertStateRestored('CT unit error', states{k, 1}, states{k, 2});
    matrix2 = [matrix2; {sprintf('CT unit error exit (%s)', ...
        states{k, 1}), states{k, 1}, 'assert exit', 'PASS'}]; %#ok<AGROW>
end

% trials entry: 4 states x normal-return via the controlled hook (fast;
% full-success normal return at a finite state is c3's rows)
for k = 1:size(states, 1)
    setAppliedState(states{k, 2});
    resF = run_air_m2_trials('trials');
    assert(~resF.pass);
    assertStateRestored('CT trials return', states{k, 1}, states{k, 2});
    matrix2 = [matrix2; {sprintf('CT trials normal-return exit (%s)', ...
        states{k, 1}), states{k, 1}, 'normal return', 'PASS'}]; %#ok<AGROW>
end

% chain entry: 4 states x error exit via the compare injection; the full
% chain success at a finite state is c5's rows
for k = 1:size(states, 1)
    setAppliedState(states{k, 2});
    threw = false;
    try
        run_m2_session_chain('compare');
    catch e
        threw = strcmp(e.identifier, 'air:M2Session:CompareFailed');
    end
    assert(threw, 'CT chain %s: compare injection did not fire', ...
        states{k, 1});
    assertStateRestored('CT chain error', states{k, 1}, states{k, 2});
    matrix2 = [matrix2; {sprintf('CT chain error exit (%s)', ...
        states{k, 1}), states{k, 1}, 'assert exit', 'PASS'}]; %#ok<AGROW>
end

% verifier entry: 4 states x error exit via the fail hook; the verifier's
% normal-return exit is the report stage itself
for k = 1:size(states, 1)
    setAppliedState(states{k, 2});
    threw = false;
    try
        verify_m2_round4_closure('fail');
    catch e
        threw = strcmp(e.identifier, 'air:M2Verify:InjectedFailure');
    end
    assert(threw, 'CT verifier %s: fail hook did not fire', states{k, 1});
    assertStateRestored('CT verifier error', states{k, 1}, states{k, 2});
    matrix2 = [matrix2; {sprintf('CT verifier error exit (%s)', ...
        states{k, 1}), states{k, 1}, 'assert exit', 'PASS'}]; %#ok<AGROW>
end

% R5-F3 negative proof: a message WITHOUT the archive field must fail the
% same contains() check the C2 trials row uses
fired = false;
try
    assert(contains('M2 trials failed', 'archive injected'), ...
        'air:M2Verify:NegativeProof', 'no archive');
catch
    fired = true;
end
assert(fired, 'R5-F3 negative proof: check passed without archive field');
matrix2 = [matrix2; {'CT archive-assert negative proof (no-path fails)', ...
    'n/a', 'negative proof', 'PASS'}];

% R5-F2 / R6-F1 / R6-F2 negative proofs on TOY copies (the real staged
% dir is untouched). The toy manifest is trimmed to the four EARLIER
% stages: contract.csv is written only after this block returns, so it
% cannot be cloned yet.
assert(~isempty(manifest), 'contract stage needs the manifest');
toyBase = fullfile(tempdir, 'm2_r5_toy');
if exist(toyBase, 'dir'), rmdir(toyBase, 's'); end
cases = {'oldbatch', 'missing', 'mixed', 'failrow', 'shamix'};
for c = 1:numel(cases)
    toy = fullfile(toyBase, cases{c});
    cloneStaged(stagedDir, toy, true);   % exclude the contract stage
    switch cases{c}
        case 'oldbatch'   % one CSV carries a foreign runId
            tamperCsvRunId(toy, 'c3.csv');
        case 'missing'    % one stage artifact deleted
            delete(fullfile(toy, 'c3.done.mat'));
        case 'mixed'      % one done.mat carries a foreign commit
            D = load(fullfile(toy, 'c5.done.mat'));
            D.done.gitCommit = 'deadbeef';
            save(fullfile(toy, 'c5.done.mat'), '-struct', 'D');
        case 'failrow'    % R6-F2: a non-PASS verdict row must be rejected
            tamperCsvVerdict(toy, 'c3.csv');
        case 'shamix'     % R6-F1: a done.mat verifier SHA mismatch
            D = load(fullfile(toy, 'c5.done.mat'));
            D.done.verifierSha = 'deadbeefdeadbeef';
            save(fullfile(toy, 'c5.done.mat'), '-struct', 'D');
    end
    threw2 = false;
    try
        validateStaged(toy);
    catch
        threw2 = true;
    end
    assert(threw2, 'negative %s: validation did not fail', cases{c});
    matrix2 = [matrix2; {sprintf( ...
        'CT manifest/evidence negative proof (%s rejected)', cases{c}), ...
        'n/a', 'negative proof', 'PASS'}]; %#ok<AGROW>
end
rmdir(toyBase, 's');

% R6-F1 dirty-tree negative proof (live): an untracked file inside the
% repo must block stage evidence via the same assertSourceBound gate the
% stages use. The probe file is transient (onCleanup) and removed before
% the row is recorded; the clean-tree call right after is the positive
% control. NOTE .txt, not .tmp: *.tmp is gitignored, and git status
% --porcelain never lists ignored files -- the probe must be VISIBLE to
% the dirty check it is proving.
probeDirty = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), ...
    'zz_r6_dirty_probe.txt');
fid = fopen(probeDirty, 'w');
assert(fid > 0, 'R6-F1 negative: cannot create the probe file');
fclose(fid);
dirtyCleanup = onCleanup(@() delete(probeDirty));
threwD = false;
try
    assertSourceBound(manifest);   % must reject: the tree is dirty NOW
catch e
    threwD = strcmp(e.identifier, 'air:M2Verify:DirtyTree');
    assert(threwD, 'R6-F1 dirty negative: wrong error id %s', e.identifier);
end
assert(threwD, 'R6-F1 dirty negative: a dirty tree was NOT rejected');
clear dirtyCleanup   % fires the single delete of the probe file
assertSourceBound(manifest);   % clean-tree positive control
matrix2 = [matrix2; { ...
    'CT dirty-tree negative proof (untracked file blocks stage)', ...
    'n/a', 'negative proof', 'PASS'}];
end

function setAppliedState(v)
%SETAPPLIEDSTATE caller-sentinel M2_ETA_APPLIED for a contract state.
global M2_ETA_PARAMS M2_ETA_APPLIED
M2_ETA_PARAMS = struct('mode', 'esc', 'center0', 0.9134);
M2_ETA_APPLIED = v;
end

function assertStateRestored(label, stateName, v)
%ASSERTSTATERESTORED exact restore incl. non-finite (isequaln semantics).
global M2_ETA_PARAMS M2_ETA_APPLIED
assert(isequal(M2_ETA_PARAMS, struct('mode', 'esc', 'center0', 0.9134)), ...
    '%s (%s): params not restored', label, stateName);
assert(isequaln(M2_ETA_APPLIED, v), ...
    '%s (%s): applied not restored exactly (got %g)', label, stateName, ...
    M2_ETA_APPLIED);
end

function manifest = makeManifest()
%MAKEMANIFEST unique run identity for staged evidence binding (R5-F2) with
%   the round-6 R6-F1 source-fingerprint contract: the manifest records a
%   LIVE capture of HEAD, the verifier SHA-256 and the clean-tree state;
%   'unknown' placeholders and a dirty tree are hard errors (evidence that
%   cannot be bound to a commit is not evidence).
manifest = struct();
manifest.runId = char(java.util.UUID.randomUUID());
fp = srcFingerprint();
manifest.gitCommit = fp.gitCommit;
manifest.verifierSha = fp.verifierSha;
assert(~fp.dirty, 'air:M2Verify:DirtyTree', ...
    ['a staged batch must start from a clean working tree; ' ...
    'uncommitted changes:\n%s'], strjoin(fp.dirtyLines, newline));
manifest.created = datetime('now');
manifest.stages = {'c1c2stale', 'c2clean', 'c3', 'c5', 'contract'};
manifest.declaredRows = struct('c1c2stale', 6, 'c2clean', 3, 'c3', 2, ...
    'c5', 4, 'contract', 27);
end

function fp = srcFingerprint()
%SRCFINGERPRINT R6-F1: independently capture the CURRENT source identity:
%   HEAD commit, this verifier's SHA-256 and the dirty state. Called
%   separately by init, every stage and report -- no caller ever reuses
%   another capture's values. Git runs with an explicit -C <repoRoot> so
%   the capture never depends on the process working directory (quick-probe
%   finding: a driver launched outside the repo got SourceFingerprint
%   instead of the intended gate error).
repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
[st, out] = system(sprintf('git -C "%s" rev-parse HEAD', repoRoot));
assert(st == 0, 'air:M2Verify:SourceFingerprint', ...
    'git rev-parse HEAD failed (exit %d) -- cannot bind evidence', st);
fp.gitCommit = strtrim(out);
fp.verifierSha = sha256file([mfilename('fullpath') '.m']);
[st2, out2] = system(sprintf('git -C "%s" status --porcelain', repoRoot));
assert(st2 == 0, 'air:M2Verify:SourceFingerprint', ...
    'git status failed (exit %d) -- cannot establish dirty state', st2);
lines = strsplit(strtrim(out2), '\n', 'CollapseDelimiters', true);
fp.dirtyLines = lines(~cellfun(@isempty, lines));
fp.dirty = ~isempty(fp.dirtyLines);
end

function fp = assertSourceBound(manifest)
%ASSERTSOURCEBOUND R6-F1: the LIVE source identity must match the manifest
%   (same-commit single-batch binding) and the tree must be clean. Used at
%   stage entry, at done-stamp time and by report -- each call is an
%   independent capture, so a mid-batch commit, a verifier edit or an
%   uncommitted change can never hide behind copied values.
fp = srcFingerprint();
assert(~fp.dirty, 'air:M2Verify:DirtyTree', ...
    ['stage evidence requires a clean working tree; uncommitted ' ...
    'changes:\n%s'], strjoin(fp.dirtyLines, newline));
assert(strcmp(fp.gitCommit, manifest.gitCommit), ...
    'air:M2Verify:StaleEvidence', ...
    'live HEAD %s differs from manifest commit %s -- rerun the FULL batch', ...
    fp.gitCommit, manifest.gitCommit);
assert(strcmp(fp.verifierSha, manifest.verifierSha), ...
    'air:M2Verify:StaleEvidence', ...
    ['verifier SHA differs from manifest -- the verifier file changed ' ...
    'since init; rerun the FULL batch']);
end

function validateStaged(dir)
%VALIDATESTAGED R5-F2/R6-F1/R6-F2: the aggregate is only valid for ONE
%   clean single-commit batch: every expected stage file must exist, carry
%   the manifest's runId in every row, have every verdict row PASS, and
%   its done.mat must match runId, git commit AND verifier SHA. Throws on
%   any stale / missing / mixed / FAIL evidence.
f = fullfile(dir, 'manifest.mat');
assert(exist(f, 'file'), 'air:M2Verify:StaleEvidence', ...
    'no manifest in %s', dir);
S = load(f, 'manifest');
m = S.manifest;
for k = 1:numel(m.stages)
    st = m.stages{k};
    csv = fullfile(dir, [st '.csv']);
    assert(exist(csv, 'file'), 'air:M2Verify:StaleEvidence', ...
        'stage csv missing: %s', st);
    T = readtable(csv, 'TextType', 'string', 'Delimiter', ',', ...
        'VariableNamingRule', 'preserve');
    assert(height(T) == m.declaredRows.(st), ...
        'air:M2Verify:StaleEvidence', 'stage %s has %d rows, declared %d', ...
        st, height(T), m.declaredRows.(st));
    assert(all(T.verdict == "PASS"), 'air:M2Verify:StaleEvidence', ...
        'stage %s carries %d non-PASS verdict rows (R6-F2)', st, ...
        sum(T.verdict ~= "PASS"));
    assert(all(T.runId == string(m.runId)), ...
        'air:M2Verify:StaleEvidence', ...
        'stage %s csv carries a foreign runId (old/mixed batch)', st);
    dn = fullfile(dir, [st '.done.mat']);
    assert(exist(dn, 'file'), 'air:M2Verify:StaleEvidence', ...
        'stage done marker missing: %s', st);
    D = load(dn, 'done');
    assert(strcmp(D.done.runId, m.runId), ...
        'air:M2Verify:StaleEvidence', ...
        'stage %s done.mat runId differs from manifest', st);
    assert(strcmp(D.done.gitCommit, m.gitCommit), ...
        'air:M2Verify:StaleEvidence', ...
        'stage %s done.mat git commit differs from manifest', st);
    assert(isfield(D.done, 'verifierSha') && ...
        strcmp(D.done.verifierSha, m.verifierSha), ...
        'air:M2Verify:StaleEvidence', ...
        ['stage %s done.mat verifier SHA missing or differs from ' ...
        'manifest (R6-F1: pre-round-6 or tampered evidence)'], st);
end
end

function totalRows = writeAggregate(stagedDir)
%WRITEAGGREGATE manifest-validated rows + c5 evidence into the archive.
%   Returns the aggregated row count; the caller prints it (no hardcoded
%   totals -- the declared count is computed from the manifest itself,
%   R6 round: the old fixed 39 went stale the moment the matrix grew).
S = load(fullfile(stagedDir, 'manifest.mat'), 'manifest');
m = S.manifest;
rows = {};
for k = 1:numel(m.stages)
    T = readtable(fullfile(stagedDir, [m.stages{k} '.csv']), ...
        'TextType', 'string', 'Delimiter', ',', ...
        'VariableNamingRule', 'preserve');
    for j = 1:height(T)
        rows = [rows; {char(T.test{j}), char(T.entryState{j}), ...
            char(T.exitPath{j}), char(T.verdict{j}), ...
            char(T.runId{j})}]; %#ok<AGROW>
    end
end
% declaredRows is a struct of scalars -- sum its VALUES (structfun(@nnz)
% would count non-zero FIELDS, i.e. the stage count, not the row count;
% first formal batch caught this: "declared 5, aggregated 42")
totalDeclared = sum(cell2mat(struct2cell(m.declaredRows)));
assert(size(rows, 1) == totalDeclared, 'air:M2Verify:RowCountMismatch', ...
    'declared %d matrix rows, aggregated %d', totalDeclared, ...
    size(rows, 1));
totalRows = size(rows, 1);
T = cell2table(rows, 'VariableNames', {'test', 'entryState', ...
    'exitPath', 'verdict', 'runId'});
adapterDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(adapterDir));
outDir = fullfile(repoRoot, 'results', 'round4_closure', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
if ~exist(outDir, 'dir'), mkdir(outDir); end
writetable(T, fullfile(outDir, 'matrix.csv'));
C = load(fullfile(stagedDir, 'c5.mat'), 'arch', 'h1', 'h2', 'todayGate', ...
    'round3Gate');
arch = C.arch; h1 = C.h1; h2 = C.h2;
todayGate = C.todayGate; round3Gate = C.round3Gate;
save(fullfile(outDir, 'result.mat'), 'arch', 'h1', 'h2', 'todayGate', ...
    'round3Gate');
save(fullfile(outDir, 'manifest.mat'), '-struct', 'S');
disp(T);
fprintf('Archive: %s\nrunId=%s\ncommit=%s\n', outDir, m.runId, ...
    m.gitCommit);
end

function cloneStaged(src, dst, excludeContract)
%CLONESTAGED copy the real staged evidence into a toy dir for negative
%   proofs (the real dir is never modified). excludeContract skips the
%   contract stage files (not yet written when the proof runs) and trims
%   the toy manifest's stage list accordingly.
mkdir(dst);
copyfile(fullfile(src, 'manifest.mat'), dst);
sts = {'c1c2stale', 'c2clean', 'c3', 'c5'};
if nargin < 3 || ~excludeContract
    sts{end + 1} = 'contract';
else
    M = load(fullfile(dst, 'manifest.mat'), 'manifest');
    M.manifest.stages = sts;
    save(fullfile(dst, 'manifest.mat'), '-struct', 'M');
end
for k = 1:numel(sts)
    copyfile(fullfile(src, [sts{k} '.csv']), dst);
    copyfile(fullfile(src, [sts{k} '.done.mat']), dst);
end
copyfile(fullfile(src, 'c5.mat'), dst);
end

function tamperCsvRunId(dir, name)
%TAMPERCSVRUNID rewrite one stage csv with a foreign runId (old-batch toy).
f = fullfile(dir, name);
T = readtable(f, 'TextType', 'string', 'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');
T.runId(:) = "00000000-old-batch";
writetable(T, f);
end

function tamperCsvVerdict(dir, name)
%TAMPERCSVVERDICT rewrite one stage csv with a FAIL verdict row (R6-F2 toy:
%   the aggregator must hard-reject, not merely count, non-PASS rows).
f = fullfile(dir, name);
T = readtable(f, 'TextType', 'string', 'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');
T.verdict(1) = "FAIL";
writetable(T, f);
end
