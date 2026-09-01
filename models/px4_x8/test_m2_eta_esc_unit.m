%TEST_M2_ETA_ESC_UNIT M2 unit tests, pure MATLAB, no model (plan §6).
%   U1 allocator pure function: eta=1 identity, pair-sum preservation
%      (checked AFTER the model-identical uint16 quantization, matching
%      the Simulink 'M2 Pwm Uint16' DataTypeConversion), clamping/sat,
%      dmz analytic agreement (balanced => exactly 0)
%   U2 analytic bowl convergence through the full adapter: P(eta) =
%      251 * g(eta)/g(1), g = (1+eta^3)/(1+eta^2)^1.5, first-order
%      actuator tau = 1 s; esc from center0 = 0.8 and 1.2 must settle at
%      1.00 +/- 0.02 within 30 s with eta_ref in [0.73,1.27]
%   U3 fixed mode: eta_ref identically center0
%   U4 invalid-sample semantics: saturation/heavy flags freeze the
%      reference (no jumps), learning resumes after recovery
%   Gain calibration: smallest gain on the sweep meeting U2 for both
%   starts; the chosen value is printed for backfill into
%   docs/interfaces/M2_ETA_ALLOCATOR.md section 4.2.
%
%   SESSION ISOLATION (reacceptance F2/Z1, R3-F2): the test snapshots
%   M2_ETA_PARAMS / M2_ETA_APPLIED on entry and restores them on exit --
%   success AND error paths -- and clears the m2_eta_esc persistent state,
%   so running the platform regression chain in the same MATLAB session
%   right after this test needs no manual `clear global`. FUNCTION ENTRY
%   (ACCEPTANCE_AUTOMATION_RULES.md rules 2.1/4.2): the function frame
%   makes the onCleanup restore reliable on the error path, and
%   injectError = 'unit' triggers one controlled internal assertion
%   failure (after the globals were touched) to exercise that path.

function ok = test_m2_eta_esc_unit(injectError)
if nargin < 1
    injectError = '';
end

adapterDir = fileparts(mfilename('fullpath'));
addpath(adapterDir);
wsRoot = fileparts(fileparts(adapterDir));
ratioRoot = fullfile(wsRoot, 'modules', 'ratio_esc');
if ~isfolder(ratioRoot)
    ratioRoot = fullfile(wsRoot, '26isip_Aerospace', 'modules', 'ratio_esc');
end
assert(isfolder(ratioRoot), 'm2test:KernelMissing', ...
    'ratio_esc module not found relative to %s', adapterDir);
addpath(ratioRoot);

global M2_ETA_PARAMS M2_ETA_APPLIED
% snapshot for restoration (empty global in a fresh session restores to
% the safe identity default, not to stale numbers)
savedParams = [];
savedApplied = [];
if ~isempty(M2_ETA_PARAMS), savedParams = M2_ETA_PARAMS; end
if ~isempty(M2_ETA_APPLIED) && isfinite(M2_ETA_APPLIED)
    savedApplied = M2_ETA_APPLIED;
end
% R2-F3/R3-F2: ONE unified cleanup restores the globals AND clears the
% adapter persistent state on the success path AND on any error/assert
% path (function frame: the onCleanup runs on error unwinding too)
restoreGlobals = onCleanup(@() m2test_cleanup( ...
    savedParams, savedApplied)); %#ok<NASGU>

PASS = true;
fprintf('=== U1 allocator pure function ===\n');
pwmIn0 = [1500; 1490; 1510; 1495; 1505; 1480; 1520; 1490];
M2_ETA_APPLIED = 1.0;
pwm1 = m2_eta_allocator(pwmIn0);
sd1 = m2_alloc_diag(pwmIn0);
% controlled-failure hook (round-4 closure condition 1): fires after the
% globals were touched so the error-path restore is genuinely exercised
if strcmp(injectError, 'unit')
    assert(false, 'air:M2Test:InjectedFailure', ...
        'controlled failure injection after globals were touched');
end
assert(isequal(pwm1, double([1500; 1490; 1510; 1495; 1505; 1480; ...
    1520; 1490])), 'U1 identity failed');
assert(sd1(1) == 0 && sd1(2) == 0, 'U1 identity sat/dmz not zero');
M2_ETA_APPLIED = 1.0;
pwmL = m2_eta_allocator(1000 * ones(8, 1));
sdL = m2_alloc_diag(1000 * ones(8, 1));
assert(all(pwmL == 1000) && sdL(1) == 0 && sdL(2) == 0, ...
    'U1 min-rail identity');
pwmH = m2_eta_allocator(2000 * ones(8, 1));
assert(all(pwmH == 2000), 'U1 max-rail identity');

% pair-sum preservation at eta = 0.8 and 1.2, checked AFTER the uint16
% quantization the Simulink 'M2 Pwm Uint16' conversion applies (1-us pwm
% grid): <= 0.3% per pair (reacceptance F3/Z3 -- the raw allocator output
% preserves pair sums to floating-point exactness; the quantizer is what
% the acceptance bound covers)
for etaTest = [0.8, 1.2]
    pwmIn = [1500; 1490; 1510; 1495; 1505; 1480; 1520; 1490];
    M2_ETA_APPLIED = etaTest;
    pwmOut = m2_eta_allocator(pwmIn);
    satOut = m2_alloc_diag(pwmIn);
    pwmOutQ = double(uint16(pwmOut));   % model-identical quantizer
    omIn = double(pwmIn) - 1000;
    omOut = pwmOutQ - 1000;
    for kk = 1:4
        cB = omIn(kk)^2 + omIn(kk + 4)^2;
        cA = omOut(kk)^2 + omOut(kk + 4)^2;
        rel = abs(cA - cB) / cB;
        fprintf('  eta %.1f pair %d: sum-c rel err %.5f%%\n', ...
            etaTest, kk, 100 * rel);
        assert(rel <= 0.003, 'U1 pair-sum quantization bound');
    end
    assert(satOut(1) == 0, 'U1 unexpected sat');
end

% clamping
M2_ETA_APPLIED = 2.0;
sC = m2_alloc_diag(1500 * ones(8, 1));
assert(sC(1) == 1, 'U1 eta upper clamp not flagged');
M2_ETA_APPLIED = 0.5;
sC2 = m2_alloc_diag(1500 * ones(8, 1));
assert(sC2(1) == 1, 'U1 eta lower clamp not flagged');

% dmz: balanced commands => exactly 0; unbalanced => analytic agreement
M2_ETA_APPLIED = 0.8;
dB = m2_alloc_diag(1500 * ones(8, 1));
assert(abs(dB(2)) < 1e-12, 'U1 balanced dmz not zero (%g)', dB(2));
pwmU = [1500; 1490; 1510; 1495; 1505; 1480; 1520; 1490];
dU = m2_alloc_diag(pwmU);
omU = double(pwmU) - 1000;
etaA = 0.8;
cLo = omU(1:4).^2; cUp = omU(5:8).^2;
cSum = cLo + cUp;
cLo2 = cSum / (1 + etaA^2); cUp2 = etaA^2 * cLo2;
dirL = [-1; 1; -1; 1];
dExp = 2.51e-7 * sum(dirL .* ((cUp2 - cLo2) - (cUp - cLo)));
fprintf('  dmz unbalanced: block %.6e vs analytic %.6e\n', dU(2), dExp);
assert(abs(dU(2) - dExp) <= 1e-12 * max(1, abs(dExp)), 'U1 dmz analytic');

fprintf('=== U2/U3/U4 adapter tests ===\n');
% gain calibration sweep: smallest gain meeting U2 for both starts
gainSweep = [2e-4, 4e-4, 8e-4, 1.6e-3, 3.2e-3, 6.4e-3, 1.28e-2];
chosen = NaN;
for gi = 1:numel(gainSweep)
    g = gainSweep(gi);
    r1 = bowlRun('esc', 0.8, g, 30.0);
    r2 = bowlRun('esc', 1.2, g, 30.0);
    okG = r1.converged && r2.converged && r1.inBand && r2.inBand;
    fprintf('  gain %.0e: c0=0.8 center %.4f (conv %d), c0=1.2 center %.4f (conv %d)\n', ...
        g, r1.finalCenter, r1.converged, r2.finalCenter, r2.converged);
    if okG
        chosen = g;
        break;
    end
end
assert(~isnan(chosen), 'U2 no gain on the sweep met the criteria');
M2_ETA_PARAMS = struct('mode', 'esc', 'center0', 1.0, 'gain', chosen);
fprintf('  chosen gain = %g (backfill doc section 4.2)\n', chosen);

r1 = bowlRun('esc', 0.8, chosen, 30.0);
r2 = bowlRun('esc', 1.2, chosen, 30.0);
assert(r1.converged && r2.converged, 'U2 convergence failed');
assert(r1.finalCenter <= 1.02 && r1.finalCenter >= 0.98, 'U2 center 0.8 start');
assert(r2.finalCenter <= 1.02 && r2.finalCenter >= 0.98, 'U2 center 1.2 start');
assert(r1.inBand && r2.inBand, 'U2 eta_ref left [0.73,1.27]');

% U3 fixed mode identity
M2_ETA_PARAMS = struct('mode', 'fixed', 'center0', 0.95);
rf = bowlRun('fixed', 0.95, chosen, 10.0);
assert(all(rf.etaRefTrace == 0.95), 'U3 fixed mode not constant');

% U4 invalid semantics: saturation on for [8,16) s freezes the reference
M2_ETA_PARAMS = struct('mode', 'esc', 'center0', 0.8, 'gain', chosen);
r4 = bowlRun('esc', 0.8, chosen, 40.0, [8.0, 16.0]);
assert(r4.heldDuringInvalid, 'U4 reference moved during invalid window');
assert(r4.converged, 'U4 no convergence after recovery');
fprintf('  U4: held during invalid window, converged after recovery\n');

% Z1/R2-F3 session isolation (success path fires the onCleanup immediately;
% the onCleanup object covers error/assert paths with the same cleanup):
% restore the entry-time globals and wipe the adapter persistent state so
% the platform regression chain can run in this session without a manual
% `clear global`
restoreGlobals = [];   % fire the onCleanup now (removes it from scope exit)

ok = true;
fprintf('M2 UNIT TESTS PASS (gain = %g)\n', chosen);
end

% ---------------------------------------------------------------------------
function r = bowlRun(mode, center0, gain, stopT, invalidWin)
%BOWLRUN drive the full m2_eta_esc adapter against the analytic bowl with a
%   first-order actuator (tau = 1 s). invalidWin = [a,b] forces allocator
%   saturation on that window (U4).
global M2_ETA_PARAMS
if nargin < 5
    invalidWin = [];
end
M2_ETA_PARAMS = struct('mode', mode, 'center0', center0, 'gain', gain);
Ts = 0.05;
tau = 1.0;
etaA = center0;          % allocator applies the ratio immediately
n = round(stopT / Ts);
etaRefTrace = zeros(1, n);
actTrace = zeros(1, n);
held = true;
refAtStart = NaN;
for k = 1:n
    t = (k - 1) * Ts;
    satBit = ~isempty(invalidWin) && t >= invalidWin(1) && t < invalidWin(2);
    % plant: omLo = 500 rad/s, omUp = 500 * etaA; rpm = om * 60 / 2pi
    rpmLo = 500 * 60 / (2 * pi);
    rpmUp = 500 * etaA * 60 / (2 * pi);
    u = [t; 9.0; bowlPower(etaA); 0.0; zeros(6, 1); ...
        1000 + 500 * ones(8, 1); ...
        [rpmLo * ones(4, 1); rpmUp * ones(4, 1)]; zeros(8, 1); satBit];
    u = u(:);
    eo = m2_eta_esc(u);
    etaRef = eo(1);
    etaAct = eo(2);
    etaRefTrace(k) = etaRef;
    actTrace(k) = etaAct;
    % first-order actuator toward the reference
    etaA = etaA + Ts / tau * (etaRef - etaA);
    if satBit
        if isnan(refAtStart)
            refAtStart = etaRefTrace(max(k - 1, 1));
        end
        if abs(etaRefTrace(k) - refAtStart) > 1e-9
            held = false;
        end
    end
end
% period means of eta_ref (0.25 Hz => 4 s); settled when all remaining
% period means stay inside 0.02
pLen = round(4.0 / Ts);
nP = floor(n / pLen);
pm = arrayfun(@(j) mean(etaRefTrace((j - 1) * pLen + 1:j * pLen)), 1:nP);
convT = NaN;
for j = 1:nP
    if max(pm(j:end)) - min(pm(j:end)) <= 0.02
        convT = (j - 1) * 4.0;
        break;
    end
end
r = struct('mode', mode, 'center0', center0, ...
    'finalCenter', pm(end), 'convT', convT, ...
    'converged', ~isnan(convT) && abs(pm(end) - 1.0) <= 0.02, ...
    'inBand', all(etaRefTrace >= 0.73 & etaRefTrace <= 1.27), ...
    'etaRefTrace', etaRefTrace, 'actTrace', actTrace, ...
    'heldDuringInvalid', held);
end

function P = bowlPower(eta)
%BOWLPOWER analytic proxy power at fixed total thrust: 251 W nominal,
%   g(eta) = (1 + eta^3)/(1 + eta^2)^(3/2), g(1) is the minimum.
g = @(x) (1 + x^3) / (1 + x^2)^1.5;
P = 251.0 * g(eta) / g(1.0);
end

function m2test_cleanup(savedParams, savedApplied)
%M2TEST_CLEANUP R2-F3: put M2 globals back to their entry-time values
%   (empty stays empty -- the safe identity default for every consumer) and
%   clear the m2_eta_esc persistent state. Runs on success AND on any
%   error/assert path (single onCleanup callback).
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
clear('m2_eta_esc');   % function-form clear: wipes persistent state
end
