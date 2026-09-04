function r = m3_check_execution(t, searchV, searchE, candV, candE, ...
    applV, applE, prmV, prmE, varargin)
%M3_CHECK_EXECUTION Execution-evidence checker (M3 doc sections 2.3/5).
%   The role inputs are the EXPECTATION (plan, reconstructed from
%   m3_schedule offline); the predicates below run on the archived
%   candidate (adapter) and applied (selector/allocator) signals, which
%   are produced independently of the schedule. A traitor adapter that
%   keeps searching while the plan says hold fails on holdConstancy; a
%   correctly rate-limited application must NOT fail (no false alarm).
%
%   Inputs (per 0.05 s sample, columns = samples):
%     t        time vector (uniform grid, only used for validation)
%     searchV  logical, true where the PLAN says the v channel searches
%     searchE  logical, true where the PLAN says the eta channel searches
%     candV/candE   adapter candidate outputs (v_ref / eta_ref)
%     applV/applE   applied outputs after the selector / allocator path
%     prmV/prmE     struct('amplitude',...,'rateLimit',...,'Ts',...)
%
%   Options (round-1 findings M3-R1-F3/M3-R1-F4 closure):
%     'vViaApplied' (default false) -- V1 logs no v CANDIDATE: hold
%       constancy for the v channel is checked on the APPLIED trace after
%       the rate-limit transition length of each hold run (tol 1e-9), and
%       appliedLagV/resumeJumpV are skipped (slew still enforced; the v
%       candidate comparison would compare the applied trace with itself).
%     'requireParticipation' (default false) -- every planned search run
%       must show dither-scale movement of the candidate (range >= half
%       the dither amplitude). A fully constant channel (stopped search
%       masquerading as convergence) then FAILS instead of passing
%       vacuously; when false the ranges are still measured and reported.
%     'etaAppliedIsActual' (default false) -- V1 logs the PHYSICAL actual
%       ratio (m2_eta_log col 2), not the allocator's rate-limited
%       reference: measured steps reach ~0.8 at rotor spin-up, so
%       slew/lag predicates on it are category errors. With this flag the
%       appliedSlew/appliedLag checks are replaced by a physical
%       TRACKING bound: from t = 10 s on, |actual - candidate| must stay
%       within half the dither amplitude (real arms: max 0.0035 vs
%       0.01 bound at amplitude 0.02).
%     'vHoldMask' (default [] = all true) -- logical column marking
%       samples where the v APPLIED channel is under normal supervision
%       (status==2 & hard bits quiet). The M0-B selector legitimately
%       moves v_ref outside that set, so the vViaApplied hold-constancy
%       check only grades masked samples (75/3521 hold samples on the
%       real M3-N1 arm; masked dev is exactly 0).
%   Finiteness of all four traces is ALWAYS a hard check: NaN traces make
%   every comparison below silently false, so they are rejected up front
%   (negative N4 of the round-1 report).
%
%   Output r: machine-checkable struct (pass, failFields, diagnostics).
%   NOTE: the check helpers return the (possibly updated) result struct --
%   MATLAB passes structs by value, so in-place mutation would be lost.
opt = struct('vViaApplied', false, 'requireParticipation', false, ...
    'etaAppliedIsActual', false, 'vHoldMask', []);
for a = 1:2:numel(varargin)
    opt.(varargin{a}) = varargin{a + 1};
end
if isempty(opt.vHoldMask)
    opt.vHoldMask = true(numel(t), 1);
end
n = numel(t);
r = struct('pass', false, 'failFields', {{}}, 'n', n, ...
    'nHoldRunsV', 0, 'nHoldRunsE', 0, 'maxHoldDevV', 0.0, ...
    'maxHoldDevE', 0.0, 'maxAppliedLagV', 0.0, 'maxAppliedLagE', 0.0, ...
    'minSearchRangeV', Inf, 'minSearchRangeE', Inf, ...
    'vViaApplied', opt.vViaApplied, ...
    'requireParticipation', opt.requireParticipation);
if numel(searchV) ~= n || numel(searchE) ~= n || numel(candV) ~= n || ...
        numel(candE) ~= n || numel(applV) ~= n || numel(applE) ~= n
    error('air:M3:CheckLength', ...
        'execution-evidence inputs must be equal-length columns');
end

% 0. finiteness first: NaN/Inf traces void every comparison below
if ~all(isfinite(candV(:))) || ~all(isfinite(applV(:)))
    r = addFailField(r, 'nonFiniteV');
end
if ~all(isfinite(candE(:))) || ~all(isfinite(applE(:)))
    r = addFailField(r, 'nonFiniteE');
end
if ~isempty(r.failFields)
    r.pass = false;
    return;
end

% 1. plan sanity: exactly one channel searches at any sample
if any(searchV & searchE) || ~all(searchV | searchE)
    r = addFailField(r, 'planNotExclusive');
end

% 2. hold constancy: within every planned hold run the held signal must
%    be constant -- the CANDIDATE exactly (hold outputs the clean center;
%    the kernel state that would move it is never stepped; this is the
%    traitor detector), or for a vViaApplied channel the APPLIED trace
%    after the rate-limit transition of each run.
r = checkHold(r, candE, applE, searchE, prmE, 'E', false, true(n, 1));
r = checkHold(r, candV, applV, searchV, prmV, 'V', opt.vViaApplied, ...
    opt.vHoldMask);

% 3. applied slew must respect the channel rate limit everywhere (for a
%    channel whose "applied" input is the PHYSICAL ACTUAL the bound is a
%    tracking check instead -- see etaAppliedIsActual)
r = checkSlew(r, applV, prmV, 'V');
if opt.etaAppliedIsActual
    r = checkTracking(r, applE, candE, t, prmE, 'E');
else
    r = checkSlew(r, applE, prmE, 'E');
end

% 4. applied must track the candidate once past the transition length
%    L = ceil(amplitude/rateLimit/Ts) samples after any role change
%    (skipped for a vViaApplied channel: its candidate is not logged)
if ~opt.vViaApplied
    r = checkLag(r, candV, applV, searchV, prmV, 'V');
end
if ~opt.etaAppliedIsActual
    r = checkLag(r, candE, applE, searchE, prmE, 'E');
end

% 5. role-change transient bound: the candidate may move by at most one
%    dither amplitude at any planned hold <-> search transition (for a
%    vViaApplied channel the slew check above already bounds the applied
%    ramp, so the candidate-form bound is skipped)
if ~opt.vViaApplied
    r = checkResume(r, candV, searchV, prmV, 'V');
end
r = checkResume(r, candE, searchE, prmE, 'E');

% 6. search participation: every planned search run must actually move
%    (dither in loop). A constant candidate through its search slots is a
%    stopped search, not a converged one (negative N3/N5).
r = checkParticipation(r, candV, searchV, prmV, 'V', ...
    opt.requireParticipation);
r = checkParticipation(r, candE, searchE, prmE, 'E', ...
    opt.requireParticipation);

r.pass = isempty(r.failFields);
end

function r = addFailField(r, name)
%ADDFAILFIELD append a failure field name, deduplicated, order preserved.
for j = 1:numel(r.failFields)
    if strcmp(r.failFields{j}, name)
        return;
    end
end
r.failFields{end + 1} = name; %#ok<AGROW>
end

function r = checkHold(r, cand, appl, search, prm, ch, viaApplied, mask)
%CHECKHOLD the held signal must be constant in every planned hold run.
%   Candidate mode: exact to 1e-12. vViaApplied mode: the applied trace
%   after the first Lm samples of each run (the rate limiter needs up to
%   Lm = ceil(amplitude/rateLimit/Ts) steps to settle onto the frozen
%   center) AND only on supervised samples (mask; the selector moves
%   v_ref legitimately outside supervision), tolerance 1e-9.
runs = holdRuns(~search);
Lm = ceil(prm.amplitude / (prm.rateLimit * prm.Ts));
for j = 1:size(runs, 1)
    i0 = runs(j, 1); i1 = runs(j, 2);
    if viaApplied
        segIdx = (i0 + Lm):i1;
        segIdx = segIdx(mask(segIdx));
        if numel(segIdx) < 2
            continue;
        end
        seg = appl(segIdx);
        tol = 1e-9;
    else
        seg = cand(i0:i1);
        tol = 1e-12;
    end
    dev = max(abs(seg - seg(1)));
    if strcmp(ch, 'V')
        r.nHoldRunsV = r.nHoldRunsV + 1;
        r.maxHoldDevV = max(r.maxHoldDevV, dev);
    else
        r.nHoldRunsE = r.nHoldRunsE + 1;
        r.maxHoldDevE = max(r.maxHoldDevE, dev);
    end
    if dev > tol
        r = addFailField(r, sprintf('holdConstancy%s', ch));
    end
end
end

function r = checkSlew(r, appl, prm, ch)
d = prm.rateLimit * prm.Ts;
dd = abs(diff(appl));
if any(dd > d * (1 + 1e-9) + 1e-15)
    r = addFailField(r, sprintf('appliedSlew%s', ch));
end
end

function r = checkLag(r, cand, appl, search, prm, ch)
n = numel(search);
trans = find([true; diff(search) ~= 0]);
L = ceil(prm.amplitude / (prm.rateLimit * prm.Ts));
for k = 1:n
    kt = trans(find(trans <= k, 1, 'last'));
    if k - kt > L
        lag = abs(appl(k) - cand(k));
        if strcmp(ch, 'V')
            r.maxAppliedLagV = max(r.maxAppliedLagV, lag);
        else
            r.maxAppliedLagE = max(r.maxAppliedLagE, lag);
        end
        if lag > 1e-9
            r = addFailField(r, sprintf('appliedLag%s', ch));
        end
    end
end
end

function r = checkResume(r, cand, search, prm, ch)
idx = find(diff(search) ~= 0) + 1;   % planned role changes
for j = 1:numel(idx)
    k = idx(j);
    dev = abs(cand(k) - cand(k - 1));
    if dev > prm.amplitude * 1.001 + 1e-15
        r = addFailField(r, sprintf('resumeJump%s', ch));
    end
end
end

function r = checkTracking(r, actual, cand, t, prm, ch)
%CHECKTRACKING physical-actual tracking bound (etaAppliedIsActual): from
%   t = 10 s on (rotor spin-up excluded) the measured ratio must follow
%   the candidate within half the dither amplitude.
sel = t >= 10.0;
dev = abs(actual(sel) - cand(sel));
if any(dev > 0.5 * prm.amplitude + 1e-12)
    r = addFailField(r, sprintf('actualTracking%s', ch));
end
end

function r = checkParticipation(r, cand, search, prm, ch, required)
%CHECKPARTICATION dither-scale movement in every planned search run.
%   Range >= half the dither amplitude (the full swing is 2x amplitude;
%   half is far above any dead trace and safely below a live dither).
%   Runs shorter than 10 samples are too short to grade either way.
runs = holdRuns(search);
for j = 1:size(runs, 1)
    i0 = runs(j, 1); i1 = runs(j, 2);
    if i1 - i0 + 1 < 10
        continue;
    end
    rng = max(cand(i0:i1)) - min(cand(i0:i1));
    if strcmp(ch, 'V')
        r.minSearchRangeV = min(r.minSearchRangeV, rng);
    else
        r.minSearchRangeE = min(r.minSearchRangeE, rng);
    end
    if required && rng < 0.5 * prm.amplitude
        r = addFailField(r, sprintf('searchParticipation%s', ch));
    end
end
end

function runs = holdRuns(holdLgl)
%HOLDRUNS maximal runs of holdLgl==true as [start end] pairs.
padded = [false; holdLgl(:); false];
d = diff(padded);
runs = [find(d == 1), find(d == -1) - 1];
if isempty(runs)
    runs = zeros(0, 2);
end
end
