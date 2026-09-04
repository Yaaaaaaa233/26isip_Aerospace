function ok = verify_m3_round3_closure(stage, stagedDir)
%VERIFY_M3_ROUND3_CLOSURE Round-3 closure evidence for the M3 acceptance
%   chain (round-2 independent report M3_REACCEPT_ROUND2_CODEX_20260904
%   findings F2/F3/F4/F6). Stages (run each in a FRESH MATLAB process per
%   the heap discipline; the driver tools/run_m3_batch.ps1 stages them):
%     'vunit'      -- the three unit suites (m3 incl. new B7/B8, m0c, m2);
%     'vnegative'  -- PRODUCTION-PATH negatives and controls:
%                     * the five real nominal arms + both B2 arms of the
%                       frozen batch re-graded through m3_eval_arm
%                       (kernel-replay centers, replayDiff must be 0);
%                     * kernel-DRIVEN fixtures (the replay itself generates
%                       the candidate, so the logs are self-consistent):
%                       constant-center positive control, an OUTWARD-
%                       walking center whose slot mean stays inside 0.01
%                       while the period-end regression breaches 5e-3
%                       (the false-pass shape), and an INWARD-walking
%                       center that must PASS (the false-reject shape);
%                     * tampered-candidate / dead-search fixtures -> the
%                       replay fidelity gate (air:M3EvalArm:ReplayMismatch);
%                     * NaN applied-v, dead v participation, replay-
%                       consistent 4 s bit1/2 and bit-3 (attitude) events;
%                     * the caller-global restore matrix, now the FULL
%                       cartesian cover: {trials x 4 states x 5 exits} +
%                       {boundary x 4 states x 2 exits} = 28 executed rows;
%     'vaggregate' -- tamper negatives against COPIES of the real batch
%                     segments + staged evidence (25 cases with exact ids:
%                     commit/batchId/dirty/fingerprint/segment-verdict/
%                     manifest-content/attempt six-class/contract four-
%                     class/repro session+time-grid+length), a positive
%                     control, and an ALTERNATIVE 3-segment layout that
%                     must aggregate PASS (the segmentation is
%                     parameterized, not hardcoded to five);
%     'vreport'    -- prints the closure checklist mapping.
%   stagedDir: the batch's staged directory (manifest + done stamps +
%   markers). Required by vnegative/vaggregate (they read the real batch);
%   when given, every stage bumps its persistent attempt counter and
%   writes a done stamp (rules v1.7 section 2 rule 7). Fixture copies go
%   to results/m3_round3_neg/<stamp>/ -- timestamped, never deleting any
%   earlier diagnostic directory (the round-2 verifier wiped its neg root
%   and the independent audit refused to run it for exactly that reason).
if nargin < 1
    stage = 'vunit';
end
if nargin < 2
    stagedDir = '';
end
valid = {'vunit', 'vnegative', 'vaggregate', 'vreport'};
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

attempts = [];
if ~isempty(stagedDir)
    S = load(fullfile(stagedDir, 'manifest.mat'), 'manifest');
    attempts = m3_stage_attempt(stagedDir, stage, S.manifest.maxAttempts);
end
switch stage
    case 'vunit'
        ok = runUnit();
    case 'vnegative'
        ok = runNegative(stagedDir);
    case 'vaggregate'
        ok = runAggregate(stagedDir, wsRoot);
    case 'vreport'
        printReport();
        ok = true;
end
if ~isempty(stagedDir)
    m3_stage_done(stagedDir, stage, struct('attempts', attempts));
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
fprintf('unit: 3 suites PASS (m3 coordination incl. B7/B8, m0c, m2)\n');
ok = true;
end

% ---------------------------------------------------------------------------
function ok = runNegative(stagedDir)
assert(~isempty(stagedDir), 'air:M3Verify:NoStaged', ...
    'vnegative needs the batch staged dir (real arms of the frozen batch)');
ok = true;
ok = ok && prodPathNegatives(stagedDir);
ok = ok && entryRestoreMatrix();
end

function ok = prodPathNegatives(stagedDir)
%PRODPATHNEGATIVES the formal per-arm decision path must reject each
%   defect class and pass each control. Round-3 classes: candidate-vs-
%   center semantics (F2), attitude gating (F3) plus the round-2 classes
%   rebuilt replay-consistently.
segDirs = segDirsFromStaged(stagedDir);
loadArm = @(id) loadRealArm(segDirs, id);
win = {[144, 240], [192, 240], [20, 30]};
arb = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 64.0, 'slotV', 32.0);
pvB = struct('mode', 'm3', 'center0', 9.0, 'lower', 6.0, 'upper', 12.0, ...
    'amplitude', 0.3, 'frequency', 0.25, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 6e-3, 'rateLimit', 2.0);
peM3 = struct('mode', 'm3', 'center0', 1.0, 'lower', 0.75, 'upper', 1.25, ...
    'amplitude', 0.02, 'frequency', 0.25, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 2e-4, 'rateLimit', 0.05);
peM2 = peM3;
peM2.gain = 1e-4;
ok = true;

% ---- R3-P0: the five real nominal arms + both B2 arms re-graded through
% the production path: replay fidelity must be EXACTLY 0 and every gate
% must pass (the round-2 independent audit's replay oracle, now in the
% formal path)
plan = { ...
    'M3-N1', 1, 'm3', 'm3', 7.0, 0.8; ...
    'M3-N2', 1, 'm3', 'm3', 7.0, 1.2; ...
    'M3-N3', 1, 'm3', 'm3', 11.0, 0.8; ...
    'M3-N4', 1, 'm3', 'm3', 11.0, 1.2; ...
    'M3-N5', 1, 'm3', 'm3', 9.0, 1.0; ...
    'B2-N1', 1, 'fixed', 'esc', 9.0, 0.8; ...
    'B2-N2', 1, 'fixed', 'esc', 9.0, 1.2};
for k = 1:size(plan, 1)
    id = plan{k, 1};
    rec = loadArm(id);
    pe = peM3;
    if strcmp(plan{k, 4}, 'esc')
        pe = peM2;
    end
    pe.center0 = plan{k, 6};
    pv = pvB;
    pv.mode = plan{k, 3};
    pv.center0 = plan{k, 5};
    r = m3_eval_arm(id, plan{k, 2} == 1, plan{k, 3}, plan{k, 4}, ...
        plan{k, 5}, plan{k, 6}, arb, pv, pe, struct(), rec.logs, ...
        win{:}, 240.0);
    assert(r.ok && r.etaReplayDiff == 0, ...
        'R3-P0 %s: ok %d replayDiff %.3g', id, r.ok, r.etaReplayDiff);
    if plan{k, 2} == 1
        assert(r.etaConv.converged && r.etaConv.monotonic, ...
            'R3-P0 %s: conv %d mono %d', id, r.etaConv.converged, ...
            r.etaConv.monotonic);
    end
    fprintf('R3-P0  real %-6s center %.6f replayDiff %.3g           PASS\n', ...
        id, r.etaCenter, r.etaReplayDiff);
end

% ---- kernel-driven fixtures: the replay generates the candidate, so the
% fixture logs are self-consistent by construction (F2 closure classes)
n5 = loadArm('M3-N5');
% constant-center positive control
[lgC, shC] = walkFixture(n5.logs, peM3, 1.0, @(t, r) 200 + 0 * t + 0 * r);
rC = m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, pvB, peM3, ...
    struct(), lgC, win{:}, 240.0);
assert(rC.ok && rC.etaReplayDiff == 0 && shC.maxReg == 0, ...
    'R3-C1 constant-center control failed (ok %d diff %.3g maxReg %.3g)', ...
    rC.ok, rC.etaReplayDiff, shC.maxReg);
fprintf('R3-C1  kernel-driven constant center (real dither)     PASS\n');

% outward-walking center: slot MEAN stays inside 0.01 but the period-end
% regression breaches 5e-3 -- the converged-looking departure the old
% candidate-based judgement could pass (false-pass shape); the graded
% center must now reject it
[lgO, shO] = walkFixture(n5.logs, peM3, 1.0, ...
    @(t, r) 200 + (t >= 220) .* 10 .* (r - 1.0));
rO = m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, pvB, peM3, ...
    struct(), lgO, win{:}, 240.0);
assert(~rO.ok && rO.etaConv.converged && ~rO.etaConv.monotonic, ...
    ['R3-N1 outward walk: expected converged-but-departing rejection ' ...
    '(ok %d conv %d mono %d maxReg %.4g)'], rO.ok, ...
    rO.etaConv.converged, rO.etaConv.monotonic, shO.maxReg);
assert(shO.maxReg > 5.5e-3 && abs(rO.etaCenter - 1.0) < 0.009, ...
    'R3-N1 fixture shape drifted (maxReg %.4g mean %.5f) -- recalibrate', ...
    shO.maxReg, rO.etaCenter);
fprintf(['R3-N1  outward walk (mean ok, maxReg %.4f > 5e-3)     ' ...
    'rejected\n'], shO.maxReg);

% inward-walking center: approaches 1.0 through the whole window -- the
% shape the old candidate-based judgement could reject on dither phase
% (false-reject shape); the graded center must pass it
[lgI, shI] = walkFixture(n5.logs, peM3, 1.0, ...
    @(t, r) 200 + (t < 192) .* 150 .* (r - 1.011).^2 + ...
    (t >= 192) .* 1.4 .* (r - 1.0));
rI = m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, pvB, peM3, ...
    struct(), lgI, win{:}, 240.0);
assert(rI.ok && rI.etaConv.converged && rI.etaConv.monotonic, ...
    'R3-N2 inward walk: expected pass (ok %d conv %d mono %d)', ...
    rI.ok, rI.etaConv.converged, rI.etaConv.monotonic);
assert(shI.endDist < 0.002 && shI.maxReg == 0, ...
    'R3-N2 fixture shape drifted (endDist %.4g maxReg %.4g)', ...
    shI.endDist, shI.maxReg);
fprintf('R3-N2  inward walk (0.011 -> %.4f, no regression)      PASS\n', ...
    shI.endDist);

% ---- R3-N3: Codex's round-2 phase fixture -- the candidate (and actual)
% replaced by center + a phase-shifted synthetic dither over the window:
% the kernel cannot replay it, so the evidence is not self-consistent
lg = n5.logs;
idx = lg.te2 >= 192;
t = lg.te2(idx);
fake = 1.0 + 0.02 * sin(2 * pi * 0.25 * (t - 192) - pi / 2);
lg.el(idx, 1) = fake;
lg.el(idx, 2) = fake;
got = catchId(@() m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, ...
    pvB, peM3, struct(), lg, win{:}, 240.0));
assert(strcmp(got, 'air:M3EvalArm:ReplayMismatch'), ...
    'R3-N3 tampered candidate: expected ReplayMismatch got %s', got);
fprintf('R3-N3  phase-shifted synthetic dither candidate         rejected\n');

% dead eta search (candidate constant everywhere): same fidelity class --
% the kernel always dithers during valid search, so a constant candidate
% on valid search samples is never replayable
lg = n5.logs;
lg.el(:, 1) = 1.0;
lg.el(:, 2) = 1.0;
got = catchId(@() m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, ...
    pvB, peM3, struct(), lg, win{:}, 240.0));
assert(strcmp(got, 'air:M3EvalArm:ReplayMismatch'), ...
    'R3-N3b dead search: expected ReplayMismatch got %s', got);
fprintf('R3-N3b dead eta search (constant candidate)            rejected\n');

% ---- R3-N4: NaN stretch in the APPLIED v channel (the eta replay is not
% involved): the checker's finiteness gate must fail fast
lg = n5.logs;
sel = lg.tb >= 50 & lg.tb < 60;
lg.Mb(sel, 1) = NaN;
r = m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, pvB, peM3, ...
    struct(), lg, win{:}, 240.0);
assert(~r.ok && any(strcmp(r.exe.chk.failFields, 'nonFiniteV')), ...
    'R3-N4 NaN applied v not rejected (%s)', ...
    strjoin(r.exe.chk.failFields, ','));
fprintf('R3-N4  NaN applied v                                   rejected\n');

% ---- R3-N5: dead v participation -- the applied v held constant through
% a whole v-search slot must fail searchParticipationV (the v candidate is
% not logged and the eta replay does not cover the v channel, so the
% participation check remains the v-side defense)
lg = n5.logs;
sel = lg.tb >= 64 & lg.tb < 96;
lg.Mb(sel, 1) = 9.0;
r = m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, pvB, peM3, ...
    struct(), lg, win{:}, 240.0);
assert(~r.ok && any(strcmp(r.exe.chk.failFields, 'searchParticipationV')), ...
    'R3-N5 dead v search not rejected (%s)', ...
    strjoin(r.exe.chk.failFields, ','));
fprintf('R3-N5  dead v search (applied constant in slot)        rejected\n');

% ---- R3-N6: bits 1/2 continuously hot for 4 s, REPLAY-CONSISTENT: the
% kernel sees the modified hard flags (holds through them), so the
% regenerated candidate keeps the logs self-consistent and the rejection
% comes from the 2 s cap alone
lg = n5.logs;
lg.A(lg.ta >= 210 & lg.ta < 214, 27) = 1;
lg = regenerateCandidate(lg, peM3, 1.0);
r = m3_eval_arm('M3-N5', true, 'm3', 'm3', 9.0, 1.0, arb, pvB, peM3, ...
    struct(), lg, win{:}, 240.0);
assert(~r.ok && ~r.hard12OK && abs(r.hard12RunMax - 4.0) < 0.2, ...
    'R3-N6 4 s bit1/2 run not rejected (runMax %.2f)', r.hard12RunMax);
fprintf('R3-N6  4 s continuous bit1/2 (cap 2 s, consistent)     rejected\n');

% ---- R3-N7: attitude bit 3 hot for 4 s on the DISTURBED arm D1,
% replay-consistent: the contract's 姿态限幅内 now gates every arm
d1 = loadArm('M3-D1');
lg = d1.logs;
lg.A(lg.ta >= 210 & lg.ta < 214, 29) = 1;
peD1 = peM3;
peD1.center0 = 0.8;
lg = regenerateCandidate(lg, peD1, 0.8);
r = m3_eval_arm('M3-D1', false, 'm3', 'm3', 9.0, 0.8, arb, pvB, peD1, ...
    struct(), lg, win{:}, 240.0);
assert(~r.ok && r.attLimitMax == 1, ...
    'R3-N7 disturbed attitude breach not rejected (att %d)', r.attLimitMax);
fprintf('R3-N7  attitude bit3 4 s on disturbed arm              rejected\n');
end

function [lg, shape] = walkFixture(realLogs, pe, eta0, surface)
%WALKFIXTURE build a kernel-driven synthetic arm: the surface is evaluated
%   at the PREVIOUS candidate (one-step actuation lag) and the replayed
%   kernel generates the candidate, so the fixture logs are exactly what
%   the production replay will reproduce. shape reports the fixture's
%   graded trajectory (period-end distances of the last slot).
lg = realLogs;
te2 = lg.te2;
n = numel(te2);
arb = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 64.0, 'slotV', 32.0);
searchE = planSearch(te2, arb);
hard = any(lg.A(:, [27 28 29 30 32 33]) > 0.5, 2);
hardEi = interp1(lg.ta, double(hard), te2, 'previous', 0) > 0.5;
sat = lg.el(:, 3) > 0.5;
Ts = 0.05;
cfg = ratioesc.config('Ts', Ts, 'lower', pe.lower, 'upper', pe.upper, ...
    'amplitude', pe.amplitude, 'frequency', pe.frequency, ...
    'hpOmega', pe.hpOmega, 'lpOmega', pe.lpOmega, 'gain', pe.gain, ...
    'rateLimit', pe.rateLimit, 'initialRatio', eta0, ...
    'fixedReference', eta0, 'optimalRatio', eta0, ...
    'shiftedOptimalRatio', eta0, 'stage', 'esc', 'duration', 600);
cp = ratioesc.controller_config(cfg);
st = ratioesc.esc_reset(cp, eta0, surface(te2(1), eta0));
warm = ceil(1 / (pe.frequency * Ts));
cand = zeros(n, 1);
PeE = zeros(n, 1);
prev = eta0;
for i = 1:n
    PeE(i) = surface(te2(i), prev);
    valid = ~hardEi(i) && isfinite(PeE(i)) && ~sat(i) && prev > 0;
    if ~searchE(i)
        cand(i) = st.center;
        st.lastReference = st.center;
        st.reinitialize = true;
        st.warmup = warm;
    else
        [cand(i), st] = ratioesc.esc_step(st, PeE(i), prev, valid, cp);
    end
    prev = cand(i);
end
lg.PeE = PeE;
lg.el(:, 1) = cand;
lg.el(:, 2) = cand;
% graded shape on the last slot (what m3_eval_arm will compute)
c = stCenterTrace(lg, pe, eta0, searchE, hardEi, sat);
idx = te2 >= 192 & te2 < 240 & searchE;
cc = c(idx);
per = round((1 / pe.frequency) / Ts);
npe = floor(numel(cc) / per);
dist = abs(cc(per:per:end).' - 1.0);
shape = struct('maxReg', max([0, diff(dist)]), ...
    'endDist', dist(end), 'meanDist', mean(mean(reshape(cc(1:npe * per), ...
    per, npe), 1) - 1.0));
end

function lg = regenerateCandidate(lg, pe, eta0)
%REGENERATECANDIDATE after tampering the PHYSICAL inputs (hard flags, sat,
%   PeE): re-run the replay on the modified inputs and store its
%   candidate/actual so the tampered logs stay self-consistent -- the
%   rejection must then come from the tampered defect itself, not from a
%   replay mismatch (esc_step's actualRatio only gates validity, so
%   storing el(:,2)=cand keeps the production replay bit-identical).
te2 = lg.te2;
n = numel(te2);
arb = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 64.0, 'slotV', 32.0);
searchE = planSearch(te2, arb);
hard = any(lg.A(:, [27 28 29 30 32 33]) > 0.5, 2);
hardEi = interp1(lg.ta, double(hard), te2, 'previous', 0) > 0.5;
sat = lg.el(:, 3) > 0.5;
[~, cand, ~] = m3_replay_eta_center(te2, lg.PeE, ones(n, 1), sat, ...
    hardEi, searchE, 'm3', eta0, pe, []);
lg.el(:, 1) = cand;
lg.el(:, 2) = cand;
end

function c = stCenterTrace(lg, pe, eta0, searchE, hardEi, sat)
[c, ~, ~] = m3_replay_eta_center(lg.te2, lg.PeE, lg.el(:, 2), sat, ...
    hardEi, searchE, 'm3', eta0, pe, lg.el(:, 1));
end

function searchE = planSearch(te2, arb)
n = numel(te2);
searchE = false(n, 1);
for k = 1:n
    searchE(k) = strcmp(m3_schedule(te2(k), arb).eta, 'search');
end
end

% ---------------------------------------------------------------------------
function ok = entryRestoreMatrix()
%ENTRYRESTOREMATRIX the FULL cartesian caller-state x exit matrix (rules
%   3.5/4.3): {finite,empty,NaN,Inf} x every exit of each global-writing
%   entry -- trials (pre-write hook, cfgmismatch, savefail, postwrite,
%   subset success) and boundary (postwrite, success). 28 rows, all
%   executed, all restored exactly-as-found (isequaln).
ok = true;
states = {'finite', 'empty', 'NaN', 'Inf'};
for s = 1:numel(states)
    st = states{s};
    for ex = {'trials', 'cfgmismatch', 'savefail', 'postwrite', ''}
        ok = ok && entryRow(st, ex{1});
    end
end
for s = 1:numel(states)
    for ex = {'postwrite', ''}
        ok = ok && boundaryRow(states{s}, ex{1});
    end
end
fprintf('restore matrix: 28 rows executed (trials 4x5 + boundary 4x2)\n');
end

function ok = entryRow(stateName, hook, wantId)
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
if nargin < 3
    if isempty(hook)
        wantId = 'air:None';
    elseif strcmp(hook, 'cfgmismatch')
        wantId = 'air:M3Trials:ConfigDrift';
    elseif any(strcmp(hook, {'savefail', 'postwrite'}))
        wantId = ['air:M3Trials:Injected' hook];
    else
        wantId = 'air:None';
    end
end
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
    fprintf('R3-M   trials entry    %-6s x success(subset)         restored\n', ...
        stateName);
elseif strcmp(hook, 'trials')
    fprintf('R3-M   trials entry    %-6s x pre-write return        restored\n', ...
        stateName);
elseif strcmp(hook, 'cfgmismatch')
    fprintf('R3-M   trials entry    %-6s x cfgmismatch(post-cfg)   restored\n', ...
        stateName);
else
    fprintf('R3-M   trials entry    %-6s x %s (after-write) restored\n', ...
        stateName, hook);
end
m3v_clear();
ok = true;
end

function ok = boundaryRow(stateName, hook)
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
m3v_clear();
setState(stateName);
expState = snapshotGlobals();
gotErr = 'air:None';
try
    if strcmp(hook, 'postwrite')
        run_air_m3_boundary('postwrite');
        error('air:M3Verify:HookSilent', 'boundary postwrite did not throw');
    else
        res = run_air_m3_boundary('');
        assert(res.pass, 'air:M3Verify:BoundaryFailed', ...
            'boundary success exit unexpectedly failed');
    end
catch err
    if ~strcmp(err.identifier, 'air:M3Verify:HookSilent') && ...
            ~strcmp(err.identifier, 'air:M3Verify:BoundaryFailed')
        gotErr = err.identifier;
    else
        rethrow(err);
    end
end
if strcmp(hook, 'postwrite')
    assert(strcmp(gotErr, 'air:M3Boundary:InjectedPostWrite'), ...
        'boundary row: expected InjectedPostWrite got %s', gotErr);
    fprintf('R3-M   boundary entry  %-6s x postwrite (after-write) restored\n', ...
        stateName);
else
    assert(strcmp(gotErr, 'air:None'), ...
        'boundary success row: unexpected error %s', gotErr);
    fprintf('R3-M   boundary entry  %-6s x success (2 runs)        restored\n', ...
        stateName);
end
assertRestored(stateName, expState);
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
function ok = runAggregate(stagedDir, wsRoot)
%RUNAGGREGATE tamper negatives on ISOLATED COPIES of the real batch
%   segments + staged evidence (rules section 2 rules 4-8). The fixture
%   root is TIMESTAMPED -- earlier diagnostic directories are never
%   touched. Arm archives are hardlinked (read-only for the aggregate);
%   files a case MODIFIES are real copies, so the originals are safe.
assert(~isempty(stagedDir), 'air:M3Verify:NoStaged', ...
    'vaggregate needs the batch staged dir');
segDirs = segDirsFromStaged(stagedDir);
negRoot = fullfile(wsRoot, 'results', 'm3_round3_neg', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
mkdir(negRoot);

cases = { ...
    'SourceMismatch',  'air:M3Agg:SourceMismatch',      @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @(r) setfieldlocal(r, 'binding.gitCommit', repmat('0', 1, 40))); ...
    'BatchId',         'air:M3Agg:BatchIdMismatch',     @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @(r) setfieldlocal(r, 'batchId', 'OLD-UNRELATED-BATCH')); ...
    'DirtyArchive',    'air:M3Agg:DirtyArchive',        @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @(r) setfieldlocal(r, 'binding.dirty', 1)); ...
    'ShaZero',         'air:M3Agg:FingerprintMismatch', @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @(r) setfieldlocal(r, 'binding.sha.model', repmat('0', 1, 64))); ...
    'ShaDelete',       'air:M3Agg:FingerprintMismatch', @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @stripBindingSha); ...
    'SegmentFailed',   'air:M3Agg:SegmentFailed',       @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @(r) setfieldlocal(r, 'pass', false)); ...
    'ArmFailed',       'air:M3Agg:ArmFailed',           @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @(r) setfieldlocal(r, 'runs.M3_N2.ok', false)); ...
    'SegmentTwice',    'air:M3Agg:SegmentTwice',        @() cSegTwice(negRoot, segDirs, stagedDir); ...
    'SegmentUnknown',  'air:M3Agg:SegmentUnknown',      @() cSegUnknown(negRoot, segDirs, stagedDir); ...
    'SegmentMissing',  'air:M3Agg:SegmentMissing',      @() cSegMissing(negRoot, segDirs, stagedDir); ...
    'ManifestArms',    'air:M3Agg:ManifestMismatch',    @() cManifestArms(negRoot, segDirs, stagedDir); ...
    'ArchiveMissing',  'air:M3Agg:ArchiveMissing',      @() cArchiveMissing(negRoot, segDirs, stagedDir); ...
    'ReproSession',    'air:M3Agg:ReproSession',        @() cReproSession(negRoot, segDirs, stagedDir); ...
    'ReproTimeGrid',   'air:M3Agg:ReproGrid',           @() cReproTime(negRoot, segDirs, stagedDir); ...
    'ReproGridLen',    'air:M3Agg:ReproGrid',           @() cReproLen(negRoot, segDirs, stagedDir); ...
    'AttemptMissing',  'air:M3Agg:BadAttempts',         @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @(r) rmfield(r, 'attempts')); ...
    'AttemptZero',     'air:M3Agg:BadAttempts',         @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @(r) setfieldlocal(r, 'attempts', 0)); ...
    'AttemptNaN',      'air:M3Agg:BadAttempts',         @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @(r) setfieldlocal(r, 'attempts', NaN)); ...
    'AttemptFrac',     'air:M3Agg:BadAttempts',         @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @(r) setfieldlocal(r, 'attempts', 1.5)); ...
    'AttemptOver',     'air:M3Agg:BadAttempts',         @() withEditedResult(negRoot, segDirs, stagedDir, 'M3-N2', @(r) setfieldlocal(r, 'attempts', 4)); ...
    'AttemptMarker',   'air:M3Agg:BadAttempts',         @() cAttemptMarker(negRoot, segDirs, stagedDir); ...
    'CapRaiseSynced',  'air:M3Batch:ContractMismatch',  @() cCapRaise(negRoot, segDirs, stagedDir); ...
    'SegRemove',       'air:M3Batch:ContractMismatch',  @() cSegRemove(negRoot, segDirs, stagedDir); ...
    'SegDuplicate',    'air:M3Batch:ContractMismatch',  @() cSegDuplicate(negRoot, segDirs, stagedDir); ...
    'ManifestSha',     'air:M3Agg:ContractMismatch',    @() cManifestSha(negRoot, segDirs, stagedDir)};

% positive controls first: the untouched copies must aggregate PASS, and
% an ALTERNATIVE 3-segment layout of the same 14 arms must aggregate PASS
% (the segmentation is parameterized per the contract, not hardcoded to
% five segments)
[dirs0, staged0] = copyBatch(negRoot, 'pos', segDirs, stagedDir, {});
res0 = m3_aggregate_batch(dirs0, staged0);
assert(res0.pass, 'positive control: untouched copies must aggregate PASS');
fprintf('R3-A   m3_aggregate   positive control (copies)         PASS\n');
[dirsA, stagedA] = altLayout(negRoot, segDirs, stagedDir);
resA = m3_aggregate_batch(dirsA, stagedA);
assert(resA.pass, 'alternative 3-segment layout must aggregate PASS');
fprintf('R3-A   m3_aggregate   alternative 3-segment layout      PASS\n');

ok = true;
for j = 1:size(cases, 1)
    [dirs, stg] = cases{j, 3}();
    got = catchId(@() m3_aggregate_batch(dirs, stg));
    assert(strcmp(got, cases{j, 2}), ...
        'aggregate negative %s: expected %s got %s', ...
        cases{j, 1}, cases{j, 2}, got);
    fprintf('R3-A   m3_aggregate   %-15s tamper -> rejected (%s)\n', ...
        cases{j, 1}, cases{j, 2});
end
fprintf('aggregate negatives: %d/%d rejected with exact ids + 2 positives\n', ...
    size(cases, 1), size(cases, 1));
end

function [dirs, stg] = copyBatch(negRoot, tag, segDirs, stagedDir, modifySegs)
%COPYBATCH isolated fixture: copies result.mat + markers + manifest,
%   HARDLINKS the per-arm archives (read-only for the aggregate) except
%   files listed in modifySegs {segName, fileName} which are real copies.
fx = fullfile(negRoot, tag);
mkdir(fx);
stg = fullfile(fx, 'staged');
mkdir(stg);
copyfile(fullfile(stagedDir, 'manifest.mat'), stg);
S = load(fullfile(stagedDir, 'manifest.mat'), 'manifest');
for k = 1:numel(S.manifest.segments)
    nm = S.manifest.segments(k).name;
    mk = fullfile(stagedDir, [nm '.attempts']);
    if exist(mk, 'file')
        copyfile(mk, fullfile(stg, [nm '.attempts']));
    end
end
dirs = {};
for d = 1:numel(segDirs)
    nm = S.manifest.segments(d).name;
    dst = fullfile(fx, nm);
    mkdir(dst);
    copyfile(fullfile(segDirs{d}, 'result.mat'), dst);
    listing = dir(segDirs{d});
    for f = 1:numel(listing)
        if ~listing(f).isdir && ~strcmp(listing(f).name, 'result.mat')
            src = fullfile(segDirs{d}, listing(f).name);
            wantCopy = ~isempty(modifySegs) && ...
                any(strcmp(modifySegs(:, 1), nm) & ...
                strcmp(modifySegs(:, 2), listing(f).name));
            if wantCopy
                copyfile(src, fullfile(dst, listing(f).name));
            else
                hardlinkOrCopy(src, fullfile(dst, listing(f).name));
            end
        end
    end
    dirs{end + 1} = dst; %#ok<AGROW>
end
end

function hardlinkOrCopy(src, dst)
%HARDLINKORCOPY hardlink (instant, same volume, the aggregate only reads
%   arm archives) with a copy fallback.
cmd = sprintf('cmd /c mklink /H "%s" "%s" >nul 2>&1', dst, src);
[st, ~] = system(cmd);
if st ~= 0
    copyfile(src, dst);
end
end

function [dirs, stg] = withEditedResult(negRoot, segDirs, stagedDir, arm, edit)
%WITHEDITEDRESULT base fixture + one edit applied to the result.mat of
%   the segment that ran ARM (deterministic per-run fixture tag).
persistent ctr
if isempty(ctr)
    ctr = 0;
end
ctr = ctr + 1;
[dirs, stg] = copyBatch(negRoot, sprintf('edit%d', ctr), segDirs, stagedDir, {});
d = findSegByArm(dirs, arm);
f = fullfile(d, 'result.mat');
S = load(f, 'result');
result = edit(S.result);
save(f, 'result');
end

function [dirs, stg] = cSegTwice(negRoot, segDirs, stagedDir)
[dirs, stg] = copyBatch(negRoot, 'segtwice', segDirs, stagedDir, {});
dirs{end + 1} = dirs{1};
end

function [dirs, stg] = cSegUnknown(negRoot, segDirs, stagedDir)
% a mini segment whose segName is not in the manifest (files complete)
[dirs, stg] = copyBatch(negRoot, 'segunknown', segDirs, stagedDir, {});
d = findSegByArm(dirs, 'M3-N2');
mini = fullfile(negRoot, 'segunknown', 'sZZ');
mkdir(mini);
copyfile(fullfile(d, 'M3-N2.mat'), mini);
S = load(fullfile(d, 'result.mat'), 'result');
result = S.result;
result.runs = struct('M3_N2', result.runs.M3_N2);
result.segName = 'sZZ';
save(fullfile(mini, 'result.mat'), 'result');
dirs{end + 1} = mini;
end

function [dirs, stg] = cSegMissing(negRoot, segDirs, stagedDir)
% manifest keeps all five segments; the s3 archive dir is simply absent
[dirs, stg] = copyBatch(negRoot, 'segmissing', segDirs, stagedDir, {});
keep = true(1, numel(dirs));
for d = 1:numel(dirs)
    S = load(fullfile(dirs{d}, 'result.mat'), 'result');
    keep(d) = ~strcmp(S.result.segName, 's3');
end
dirs = dirs(keep);
assert(numel(dirs) == numel(segDirs) - 1, 'fixture: one dir dropped');
end

function [dirs, stg] = cManifestArms(negRoot, segDirs, stagedDir)
% manifest declares a different arm list than the segment actually ran
% (all files present: the rejection must come from the content check)
[dirs, stg] = copyBatch(negRoot, 'manifestarms', segDirs, stagedDir, {});
f = fullfile(stg, 'manifest.mat');
S = load(f, 'manifest');
manifest = S.manifest;
hit = 0;
for k = 1:numel(manifest.segments)
    if any(strcmp(manifest.segments(k).arms, 'M3-N1'))
        hit = k;
        break
    end
end
manifest.segments(hit).arms = regexprep(manifest.segments(hit).arms, ...
    '^M3-N1$', 'M3-ZZ');
save(f, 'manifest');
end

function [dirs, stg] = cArchiveMissing(negRoot, segDirs, stagedDir)
[dirs, stg] = copyBatch(negRoot, 'archivemissing', segDirs, stagedDir, {});
delete(fullfile(findSegByArm(dirs, 'M3-N1'), 'M3-N1.mat'));
end

function [dirs, stg] = cReproSession(negRoot, segDirs, stagedDir)
% M3-R1 split into its own manifest segment (manifest edited
% consistently; all files present) -> the repro pair is cross-session
[dirs, stg] = copyBatch(negRoot, 'reprosession', segDirs, stagedDir, {});
r1dir = findSegByArm(dirs, 'M3-R1');
S = load(fullfile(r1dir, 'result.mat'), 'result');
full = S.result;
mini = fullfile(negRoot, 'reprosession', 's6');
mkdir(mini);
copyfile(fullfile(r1dir, 'M3-R1.mat'), mini);
result = full;
result.runs = struct('M3_R1', full.runs.M3_R1);
result.segName = 's6';
result.binding.runId = 'fab-run-id';
save(fullfile(mini, 'result.mat'), 'result');
fid = fopen(fullfile(stg, 's6.attempts'), 'w');
fprintf(fid, '1\n');
fclose(fid);
result = full;
result.runs = rmfield(result.runs, 'M3_R1');
save(fullfile(r1dir, 'result.mat'), 'result');
mf = fullfile(stg, 'manifest.mat');
M = load(mf, 'manifest');
manifest = M.manifest;
for k = 1:numel(manifest.segments)
    if any(strcmp(manifest.segments(k).arms, 'M3-R1'))
        manifest.segments(k).arms = 'M3-N5';
        break
    end
end
manifest.segments(end + 1) = struct('name', 's6', ...
    'arms', {{'M3-R1'}});
save(mf, 'manifest');
dirs{end + 1} = mini;
end

function [dirs, stg] = cReproTime(negRoot, segDirs, stagedDir)
% R1's time axes shifted (lengths and values preserved): the aggregate
% must compare the TIME VECTORS, not only lengths and values. The file
% under edit is force-COPIED (a hardlink edit would reach the real
% archive -- the originals must stay untouched).
mod = {segNameOfArm(stagedDir, 'M3-R1'), 'M3-R1.mat'};
[dirs, stg] = copyBatch(negRoot, 'reprotime', segDirs, stagedDir, mod);
f = fullfile(findSegByArm(dirs, 'M3-R1'), 'M3-R1.mat');
S = load(f, 'r');
r = S.r;
r.logs.te2 = r.logs.te2 + 0.025;
r.logs.tb = r.logs.tb + 0.0005;
save(f, 'r');
end

function [dirs, stg] = cReproLen(negRoot, segDirs, stagedDir)
mod = {segNameOfArm(stagedDir, 'M3-R1'), 'M3-R1.mat'};
[dirs, stg] = copyBatch(negRoot, 'reprolen', segDirs, stagedDir, mod);
f = fullfile(findSegByArm(dirs, 'M3-R1'), 'M3-R1.mat');
S = load(f, 'r');
r = S.r;
r.logs.el = r.logs.el(1:4000, :);
save(f, 'r');
end

function [dirs, stg] = cAttemptMarker(negRoot, segDirs, stagedDir)
% result.attempts (2) inconsistent with the persistent marker (1)
[dirs, stg] = copyBatch(negRoot, 'attemptmarker', segDirs, stagedDir, {});
d = findSegByArm(dirs, 'M3-N2');
S = load(fullfile(d, 'result.mat'), 'result');
result = S.result;
result.attempts = 2;
save(fullfile(d, 'result.mat'), 'result');
end

function [dirs, stg] = cCapRaise(negRoot, segDirs, stagedDir)
% the round-9 M2 probe: raise manifest.maxAttempts 3->4 AND sync the
% result/stamps to 4 -- the contract check must still die on the cap
[dirs, stg] = copyBatch(negRoot, 'capraise', segDirs, stagedDir, {});
mf = fullfile(stg, 'manifest.mat');
M = load(mf, 'manifest');
manifest = M.manifest;
manifest.maxAttempts = 4;
save(mf, 'manifest');
for d = 1:numel(dirs)
    f = fullfile(dirs{d}, 'result.mat');
    S = load(f, 'result');
    result = S.result;
    result.attempts = 4;
    save(f, 'result');
    fid = fopen(fullfile(stg, [result.segName '.attempts']), 'w');
    fprintf(fid, '4\n');
    fclose(fid);
end
end

function [dirs, stg] = cSegRemove(negRoot, segDirs, stagedDir)
% remove a segment AND its declared arms from the manifest (the M2
% round-9 probe): the contract's exact-cover check must reject
[dirs, stg] = copyBatch(negRoot, 'segremove', segDirs, stagedDir, {});
mf = fullfile(stg, 'manifest.mat');
M = load(mf, 'manifest');
manifest = M.manifest;
keep = ~strcmp({manifest.segments.name}, 's3');
manifest.segments = manifest.segments(keep);
save(mf, 'manifest');
dirs = dirs(keep);
end

function [dirs, stg] = cSegDuplicate(negRoot, segDirs, stagedDir)
% add a DUPLICATE segment with all files present (copy of s2): the
% rejection must come from the contract check, not from missing files
[dirs, stg] = copyBatch(negRoot, 'segdup', segDirs, stagedDir, {});
s2 = dirs{2};
dup = fullfile(negRoot, 'segdup', 's6');
mkdir(dup);
copyfile(fullfile(s2, 'result.mat'), dup);
listing = dir(s2);
for f = 1:numel(listing)
    if ~listing(f).isdir && ~strcmp(listing(f).name, 'result.mat')
        hardlinkOrCopy(fullfile(s2, listing(f).name), ...
            fullfile(dup, listing(f).name));
    end
end
mf = fullfile(stg, 'manifest.mat');
M = load(mf, 'manifest');
manifest = M.manifest;
manifest.segments(end + 1) = struct('name', 's6', ...
    'arms', {manifest.segments(2).arms});
save(mf, 'manifest');
fid = fopen(fullfile(stg, 's6.attempts'), 'w');
fprintf(fid, '1\n');
fclose(fid);
dirs{end + 1} = dup;
end

function [dirs, stg] = cManifestSha(negRoot, segDirs, stagedDir)
% tamper the manifest's own sha block: the aggregate live-recomputes
% every declared fingerprint and must reject the stale manifest
[dirs, stg] = copyBatch(negRoot, 'manifestsha', segDirs, stagedDir, {});
mf = fullfile(stg, 'manifest.mat');
M = load(mf, 'manifest');
manifest = M.manifest;
manifest.sha.model = repmat('1', 1, 64);
save(mf, 'manifest');
end

function [dirs, stg] = altLayout(negRoot, segDirs, stagedDir)
%ALTLAYOUT an ALTERNATIVE valid layout of the same 14 arms: three
%   segments (baselines+N1/N2 | N3/N4/D1/D2 | N5/R1). Every segment dir
%   is rebuilt from the real archives (result runs = subset, own segName);
%   the manifest is regenerated for the layout; markers synthesized. The
%   aggregate must PASS: layout is a manifest-declared fact, not a
%   hardcoded five-segment requirement.
fx = fullfile(negRoot, 'altlayout');
mkdir(fx);
stg = fullfile(fx, 'staged');
mkdir(stg);
groups = { {'B0-N','B0-D','B1-N1','B1-N2','B2-N1','B2-N2','M3-N1','M3-N2'}; ...
    {'M3-N3','M3-N4','M3-D1','M3-D2'}; ...
    {'M3-N5','M3-R1'} };
dirs = {};
manifest = struct('batchId', '', 'gitCommit', '', 'created', datetime('now'), ...
    'maxAttempts', 3, 'segments', struct('name', {}, 'arms', {{}}), ...
    'sha', struct());
S0 = load(fullfile(stagedDir, 'manifest.mat'), 'manifest');
manifest.batchId = S0.manifest.batchId;
manifest.gitCommit = S0.manifest.gitCommit;
manifest.maxAttempts = S0.manifest.maxAttempts;
manifest.sha = S0.manifest.sha;
for g = 1:numel(groups)
    nm = sprintf('a%d', g);
    dst = fullfile(fx, nm);
    mkdir(dst);
    srcDir = findSegByArm(segDirs, groups{g}{1});
    S = load(fullfile(srcDir, 'result.mat'), 'result');
    result = S.result;
    runs = struct();
    for a = 1:numel(groups{g})
        arm = groups{g}{a};
        fn = strrep(arm, '-', '_');
        armDir = findSegByArm(segDirs, arm);
        Sa = load(fullfile(armDir, 'result.mat'), 'result');
        runs.(fn) = Sa.result.runs.(fn);
        hardlinkOrCopy(fullfile(armDir, [arm '.mat']), fullfile(dst, [arm '.mat']));
    end
    result.runs = runs;
    result.segName = nm;
    result.scenarioSet = groups{g};
    save(fullfile(dst, 'result.mat'), 'result');
    fid = fopen(fullfile(stg, [nm '.attempts']), 'w');
    fprintf(fid, '1\n');
    fclose(fid);
    manifest.segments(g) = struct('name', nm, 'arms', {groups{g}});
    dirs{end + 1} = dst; %#ok<AGROW>
end
save(fullfile(stg, 'manifest.mat'), 'manifest');
end

function nm = segNameOfArm(stagedDir, arm)
%SEGNAMEOFARM manifest segment name that declares the arm.
S = load(fullfile(stagedDir, 'manifest.mat'), 'manifest');
[segs, ~] = m3_batch_validate(S.manifest);
[idx, ~] = m3_batch_locate(segs, arm);
nm = segs(idx).name;
end

function d = findSegByArm(dirs, arm)
fn = strrep(arm, '-', '_');
for j = 1:numel(dirs)
    S = load(fullfile(dirs{j}, 'result.mat'), 'result');
    if isfield(S.result.runs, fn)
        d = dirs{j};
        return;
    end
end
error('air:M3Verify:Internal', 'arm %s not found in any segment', arm);
end

function segDirs = segDirsFromStaged(stagedDir)
%SEGDIRSFROMSTAGED resolve the real segment archive dirs from the staged
%   done stamps (every manifest segment must have completed).
S = load(fullfile(stagedDir, 'manifest.mat'), 'manifest');
[segs, ~] = m3_batch_validate(S.manifest);
segDirs = {};
for k = 1:numel(segs)
    f = fullfile(stagedDir, [segs(k).name '.done.mat']);
    assert(exist(f, 'file'), 'air:M3Verify:SegmentNotDone', ...
        'segment %s has no done stamp -- run the batch first', segs(k).name);
    D = load(f, 'done');
    assert(strcmp(D.done.batchId, S.manifest.batchId), ...
        'air:M3Verify:StampBatchId', ...
        'done stamp of %s carries a foreign batchId', segs(k).name);
    assert(isfolder(char(D.done.archiveDir)), ...
        'air:M3Verify:ArchiveGone', ...
        'archive %s of segment %s no longer exists', ...
        D.done.archiveDir, segs(k).name);
    segDirs{end + 1} = char(D.done.archiveDir); %#ok<AGROW>
end
end

function rec = loadRealArm(segDirs, id)
d = findSegByArm(segDirs, id);
S = load(fullfile(d, [id '.mat']), 'r');
rec = S.r;
end

% ---------------------------------------------------------------------------
function printReport()
fprintf(['closure mapping: F2 verifiable center via kernel replay + ' ...
    'unified [192,240) (R3-P0 real arms, R3-C1/N1/N2 kernel-driven ' ...
    'phase fixtures, R3-N3 fidelity gate, unit B8);\n' ...
    'F3 attitude gate on every arm (R3-N7 + zero hard bits on the ' ...
    'real 14-arm batch);\n' ...
    'F4 batch governance: batchId manifest + sha/dirty/segment-verdict/' ...
    'attempt/contract negatives (R3-A 25 + altLayout positive), ' ...
    'in-repo bounded-retry driver + driver tests, full-cartesian ' ...
    'restore matrix (R3-M 28 rows);\n' ...
    'F6 errata + honest counting in the round-3 evidence report.\n' ...
    'batch verdict = m3_aggregate_batch over the staged segments\n']);
end

% ---------------------------------------------------------------------------
function id = catchId(fn)
id = 'air:None';
try
    fn();
    id = 'air:NoError';
catch e
    id = e.identifier;
end
end

function s = stripBindingSha(s)
%STRIPBINDINGSHA remove the sha block from a segment's entry binding.
s.binding = rmfield(s.binding, 'sha');
end

function s = setfieldlocal(s, name, value)
%SETFIELDLOCAL dotted-name field setter for the tamper fixtures.
parts = strsplit(name, '.');
switch numel(parts)
    case 1
        s.(parts{1}) = value;
    case 2
        s.(parts{1}).(parts{2}) = value;
    case 3
        s.(parts{1}).(parts{2}).(parts{3}) = value;
    otherwise
        error('air:M3Verify:Internal', 'unsupported depth for %s', name);
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
