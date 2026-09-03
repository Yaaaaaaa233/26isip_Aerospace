%TEST_M3_COORDINATION_UNIT M3 unit tests, pure MATLAB, no model (B1-B6).
%   B1 schedule pure function: exclusivity, slot boundaries, both
%      firstSlot values, cycle repetition, non-integer-dither-period slot
%      geometry, config-validation negatives (slot<=0, bad firstSlot,
%      missing/unknown fields, disabled arbitration, bad t), adapter
%      legality (mode='m3' with enable='off' fails loud) and the
%      trial-entry cross-channel check (single-sided m3 rejected).
%   B2 hold/resume through the REAL adapters: search->hold->valid and
%      search->hold->invalid->valid chains on both channels and both
%      firstSlot values, exact step-by-step replication of the reference
%      bookkeeping (independent oracle), the F1 core case (invalid resume
%      must return the synced clean center, not the stale dithered
%      reference), warmup 80->79 semantics (center first moves at the
%      81st valid step after resume), phase continuation across hold for
%      66 s non-integer-dither-period slots, old fixed/esc regression.
%   B3 gating matrix: per-event online gate equals the M3 doc 2.3
%      boolean table (hard bits [1 2 3 4 6 7], finite P, in-band, eta
%      sat/eta_act; bit 5 stays offline-only on both channels -- asserted
%      as still-learning, not assumed; the v channel has no sat input,
%      which is the registered V1 limitation).
%   B4 2-D toy convergence under alternating slots (both centers
%      converge, held center exactly frozen), duty-cycle eta-gain recheck
%      (slotted vs continuous convergence in SEARCH steps), session
%      isolation (snapshot/restore incl. the error path via a recursive
%      injected child, persistent-fresh equality, ambient independence).
%   B5 execution evidence: the checker passes the good alternating run
%      with selector-rate-limited applied values (no false alarm) and
%      rejects a traitor adapter that bypasses arbitration on the
%      holdConstancyV field; concurrent-esc cross-talk contrast (eta
%      convergence strictly slower than alternating on the same toy).
%   B6 evaluation fixtures: no-valid-window, hold-only pseudo-
%      convergence, missing pair arm, grid mismatch and deliberate
%      threshold breaches all land on the expected field/error id.
%
%   SESSION ISOLATION (ACCEPTANCE_AUTOMATION_RULES.md 2.1/4.2): the test
%   snapshots M0C_ESC_PARAMS, M2_ETA_PARAMS, M2_ETA_APPLIED and
%   M3_ARB_PARAMS on entry and restores them on exit -- success AND
%   error paths -- and clears both adapters' persistent state.
%   injectError = 'unit' fires one controlled assertion after the
%   globals were touched, so the error-path restore is really exercised.

function ok = test_m3_coordination_unit(injectError)
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
assert(isfolder(ratioRoot), 'm3test:KernelMissing', ...
    'ratio_esc module not found relative to %s', adapterDir);
addpath(ratioRoot);

global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
snap = snapshotGlobals();
restoreGlobals = onCleanup(@() m3_cleanup(snap)); %#ok<NASGU>

Ts = 0.05;
f0 = 0.25;                 % channel dither frequency (both channels)
rpm0 = 500 * 60 / (2 * pi); % 500 rad/s expressed in rpm

%% =================== B1: schedule pure function ===================
fprintf('=== B1 schedule pure function ===\n');
arbOnEta = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 64.0, 'slotV', 32.0);
arbOnV = struct('enable', 'on', 'firstSlot', 'v', 'slotEta', 64.0, 'slotV', 32.0);
geoms = {arbOnEta, arbOnV, ...
    struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 66.0, 'slotV', 66.0), ...
    struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 9.05, 'slotV', 5.0)};
for gi = 1:numel(geoms)
    g = geoms{gi};
    cyc = g.slotEta + g.slotV;
    for tq = 0:0.05:300
        ro = m3_schedule(tq, g);
        nS = strcmp(ro.v, 'search') + strcmp(ro.eta, 'search');
        assert(nS == 1, 'B1 exclusivity broken at t=%g geom %d', tq, gi);
        ro2 = m3_schedule(tq + cyc, g);
        assert(isequal(ro, ro2), 'B1 cycle repetition broken at t=%g', tq);
    end
end
% default-geometry slot arithmetic (incl. the 1e-9 boundary guard)
assert(strcmp(m3_schedule(0, arbOnEta).eta, 'search'));
assert(strcmp(m3_schedule(63.95, arbOnEta).eta, 'search'));
assert(strcmp(m3_schedule(64.0, arbOnEta).v, 'search'));
assert(strcmp(m3_schedule(95.95, arbOnEta).v, 'search'));
assert(strcmp(m3_schedule(96.0, arbOnEta).eta, 'search'));
assert(strcmp(m3_schedule(160.0, arbOnEta).v, 'search'));
assert(strcmp(m3_schedule(191.95, arbOnEta).v, 'search'));
assert(strcmp(m3_schedule(192.0, arbOnEta).eta, 'search'));
assert(strcmp(m3_schedule(240.0, arbOnEta).eta, 'search'));
assert(strcmp(m3_schedule(0, arbOnV).v, 'search'));
assert(strcmp(m3_schedule(31.95, arbOnV).v, 'search'));
assert(strcmp(m3_schedule(32.0, arbOnV).eta, 'search'));
fprintf('  exclusivity/boundaries/cycle: OK (4 geometries x 6001 samples)\n');

% config-validation negatives -> exact error ids
b1Neg = { ...
    @() m3_schedule(0, struct('enable','on','firstSlot','eta','slotEta',0.0,'slotV',32.0)), ...
    @() m3_schedule(0, struct('enable','on','firstSlot','eta','slotEta',-1.0,'slotV',32.0)), ...
    @() m3_schedule(0, struct('enable','on','firstSlot','eta','slotEta',NaN,'slotV',32.0)), ...
    @() m3_schedule(0, struct('enable','on','firstSlot','eta','slotEta',64.0,'slotV',Inf)), ...
    @() m3_schedule(0, struct('enable','on','firstSlot','x','slotEta',64.0,'slotV',32.0)), ...
    @() m3_schedule(0, struct('enable','on','firstSlot','eta','slotEta',64.0)), ...
    @() m3_schedule(0, struct('enable','on','firstSlot','eta','slotEta',64.0,'slotV',32.0,'extra',1)), ...
    @() m3_schedule(0, struct('enable','off','firstSlot','eta','slotEta',64.0,'slotV',32.0)), ...
    @() m3_schedule(-1, arbOnEta), ...
    @() m3_schedule([0 1], arbOnEta)};
b1Exp = {'m3:schedule:BadConfig', 'm3:schedule:BadConfig', ...
    'm3:schedule:BadConfig', 'm3:schedule:BadConfig', ...
    'm3:schedule:BadConfig', 'm3:schedule:BadConfig', ...
    'm3:schedule:BadConfig', 'm3:schedule:Disabled', ...
    'm3:schedule:BadTime', 'm3:schedule:BadTime'};
for ni = 1:numel(b1Neg)
    got = catchId(b1Neg{ni});
    assert(strcmp(got, b1Exp{ni}), ...
        'B1 negative %d: got id %s, want %s', ni, got, b1Exp{ni});
end
fprintf('  schedule negatives: %d/%d rejected with exact ids\n', numel(b1Neg), numel(b1Neg));

% adapter-level legality: mode='m3' + disabled arbitration fails loud
M0C_ESC_PARAMS = struct('mode', 'm3', 'center0', 9.0);
M3_ARB_PARAMS = [];   % defaults to enable='off'
uV0 = [0; 9; 251; 0; zeros(6, 1); zeros(8, 1)];
got = catchId(@() m0c_vref_esc(uV0));
assert(strcmp(got, 'm3:schedule:Disabled'), 'B1 m0c m3+off: %s', got);
M2_ETA_PARAMS = struct('mode', 'm3', 'center0', 0.8);
uE0 = [0; 9; 251; 0; zeros(6, 1); 1500 * ones(8, 1); ...
    repmat(rpm0, 8, 1); zeros(8, 1); 0];
got = catchId(@() m2_eta_esc(uE0));
assert(strcmp(got, 'm3:schedule:Disabled'), 'B1 m2 m3+off: %s', got);
% trial-entry cross-channel legality
got = catchId(@() m3_validate_channels('m3', 'esc', arbOnEta));
assert(strcmp(got, 'air:M3:SingleSided'), 'B1 single-sided (v): %s', got);
got = catchId(@() m3_validate_channels('esc', 'm3', arbOnEta));
assert(strcmp(got, 'air:M3:SingleSided'), 'B1 single-sided (eta): %s', got);
got = catchId(@() m3_validate_channels('m3', 'm3', ...
    struct('enable', 'off', 'firstSlot', 'eta', 'slotEta', 64.0, 'slotV', 32.0)));
assert(strcmp(got, 'm3:schedule:Disabled'), 'B1 entry m3+off: %s', got);
got = catchId(@() m3_validate_channels('banana', 'fixed', []));
assert(strcmp(got, 'air:M3:BadMode'), 'B1 bad mode: %s', got);
m3_validate_channels('m3', 'm3', arbOnEta);   % must not error
m3_validate_channels('fixed', 'fixed', struct());  % never reads the arb global
fprintf('  adapter+entry legality: m3+off / single-sided / bad mode rejected; valid combos accepted\n');

% controlled-failure hook: fires after the globals were touched so the
% error-path restore is genuinely exercised (recursive child below in B4)
if strcmp(injectError, 'unit')
    assert(false, 'air:M3Test:InjectedFailure', ...
        'controlled failure injection after the globals were touched');
end

%% ============== B2: hold/resume through the real adapters ==============
fprintf('=== B2 hold/resume (real adapters) ===\n');
% ---- eta channel, firstSlot='eta', slots 9.05/5.0 (2.2625 dither
% periods: the geometry does not rely on integer-period slots)
arbB2 = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 9.05, 'slotV', 5.0);
peB2 = struct('mode', 'm3', 'center0', 0.8, 'lower', 0.75, 'upper', 1.25, ...
    'amplitude', 0.02, 'frequency', f0, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 3.2e-3, 'rateLimit', 0.05);
M2_ETA_PARAMS = peB2; M3_ARB_PARAMS = arbB2; M2_ETA_APPLIED = 1.0;
n = 641;   % t = 0 .. 32.0 s
candE2 = zeros(n, 1); sE2 = false(n, 1); smpE = 0;
for k = 1:n
    t = (k - 1) * Ts;
    isS = strcmp(m3_schedule(t, arbB2).eta, 'search');
    sE2(k) = isS;
    ph = 2 * pi * f0 * (smpE * Ts);   % phase the kernel will use this step
    Pe = 251.0;
    if isS && t >= 14.10 - 1e-12
        % dither-correlated power: once warmup ends, the center must move
        % (detection signal for the 80-step warmup block)
        Pe = 251.0 + 20.0 * sin(ph);
    end
    flagsE = zeros(1, 8);
    if abs(t - 14.05) < 1e-9
        flagsE(2) = 1;   % first search step after hold arrives INVALID (F1 core)
    end
    uE = [t; 9; Pe; 0; zeros(6, 1); 1500 * ones(8, 1); ...
        repmat(rpm0, 8, 1); flagsE(:); 0];
    eo = m2_eta_esc(uE);
    candE2(k) = eo(1);
    if isS
        smpE = smpE + 1;   % kernel increments sample on search steps only
    end
end
% independent replication of the reference bookkeeping (oracle): center
% stays exactly 0.8 while the gradient is zero (constant power); hold
% steps sync the bookkeeping to the clean center; invalid search steps
% hold the reference without rate-limiting toward the request
ref = zeros(n, 1); r = 0.8; smpR = 0;
for k = 1:n
    t = (k - 1) * Ts; isS = sE2(k);
    if isS
        if ~(abs(t - 14.05) < 1e-9)
            req = 0.8 + 0.02 * sin(2 * pi * f0 * (smpR * Ts));
            dlt = 0.05 * Ts;
            r = r + min(max(req - r, -dlt), dlt);
        end
        smpR = smpR + 1;
    else
        r = 0.8;   % hold: synced bookkeeping
    end
    ref(k) = r;
end
assert(all(abs(candE2(1:362) - ref(1:362)) < 1e-12), ...
    'B2 exact bookkeeping mismatch before adapt onset');
devIdx = find(candE2 - ref < -1e-9, 1);
assert(~isempty(devIdx), 'B2 center never moved after warmup');
assert(devIdx == 363, ...
    'B2 warmup onset at k=%d, expected 363 (81st valid step after resume)', devIdx);
i9 = 9.00 / Ts + 1; iHold = 9.05 / Ts + 1;
iInv = 14.05 / Ts + 1; iRes = 14.10 / Ts + 1;
assert(abs(candE2(i9) - 0.82) < 1e-9, 'B2 pre-hold dithered reference at phase peak');
assert(candE2(iHold) == 0.8, 'B2 hold output is the clean center');
assert(candE2(iInv) == 0.8, ...
    'B2 F1 core: invalid resume must return the synced center');
assert(candE2(iInv) ~= candE2(i9), 'B2 F1 case would be masked (0.82 == 0.8)');
expRes = 0.8 + min(0.02 * sin(2 * pi * f0 * 182 * 0.05), 0.05 * 0.05);
assert(abs(candE2(iRes) - expRes) < 1e-12, ...
    'B2 resume: rate-limit base is the synced center and the phase continues');
fprintf('  eta chain (firstSlot=eta): bookkeeping exact, F1 sync, warmup onset at step 81\n');

% ---- v channel, firstSlot='v' (same geometry): the F1 core on v
arbB2v = struct('enable', 'on', 'firstSlot', 'v', 'slotEta', 5.0, 'slotV', 9.05);
pvB2 = struct('mode', 'm3', 'center0', 9.0, 'lower', 6.0, 'upper', 12.0, ...
    'amplitude', 0.3, 'frequency', f0, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 6e-3, 'rateLimit', 2.0);
M0C_ESC_PARAMS = pvB2; M3_ARB_PARAMS = arbB2v;
candV2 = zeros(n, 1);
for k = 1:n
    t = (k - 1) * Ts;
    flagsV = zeros(1, 8);
    if abs(t - 14.05) < 1e-9, flagsV(2) = 1; end
    uV = [t; 9; 251; 0; zeros(6, 1); flagsV(:)];
    candV2(k) = m0c_vref_esc(uV);
end
assert(abs(candV2(i9) - 9.3) < 1e-9, 'B2 v pre-hold dithered reference');
assert(candV2(iHold) == 9.0, 'B2 v hold output is the clean center');
assert(candV2(iInv) == 9.0, 'B2 v-channel F1 sync');
assert(candV2(iInv) ~= candV2(i9), 'B2 v F1 case masked');
expResV = 9.0 + min(0.3 * sin(2 * pi * f0 * 182 * 0.05), 2.0 * 0.05);
assert(abs(candV2(iRes) - expResV) < 1e-9, 'B2 v resume phase continuation');
fprintf('  v chain (firstSlot=v): F1 sync and phase continuation OK\n');

% ---- 66 s non-integer-dither-period slots: phase survives a long hold
arbB2b = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 66.0, 'slotV', 66.0);
M3_ARB_PARAMS = arbB2b; M2_ETA_PARAMS = peB2; M2_ETA_APPLIED = 1.0;
nb = 4001;   % t = 0 .. 200 s
candb = zeros(nb, 1); tb = (0:nb - 1)' * Ts;
for k = 1:nb
    uE = [tb(k); 9; 251; 0; zeros(6, 1); 1500 * ones(8, 1); ...
        repmat(rpm0, 8, 1); zeros(8, 1); 0];
    eo = m2_eta_esc(uE);
    candb(k) = eo(1);
end
holdSel = tb >= 66 - 1e-9 & tb < 132 - 1e-9;
assert(all(candb(holdSel) == 0.8), 'B2 66s: hold outputs not the clean center');
% resume: sample is frozen at 1320 during hold, so the phase continues at
% sin(2*pi*0.25*66.05) = -0.0785 (a phase reset would give sin(0) = 0)
kRes = 132.05 / Ts + 1;
assert(candb(kRes) < 0.8 - 1e-4, ...
    'B2 66s: phase did not continue across the hold (got %.6f)', candb(kRes));
assert(max(abs(candb - 0.8)) <= 0.02 * 1.0001, 'B2 66s: dither amplitude bound');
fprintf('  66s non-integer-period slots: phase continuation and amplitude bound OK\n');

% ---- old fixed/esc modes unchanged (full suites rerun in group D)
M3_ARB_PARAMS = [];
M2_ETA_PARAMS = struct('mode', 'fixed', 'center0', 0.95);
cf = zeros(81, 1);
for k = 1:81
    t = (k - 1) * Ts;
    uE = [t; 9; 251; 0; zeros(6, 1); 1500 * ones(8, 1); ...
        repmat(rpm0, 8, 1); zeros(8, 1); 0];
    eo = m2_eta_esc(uE);
    cf(k) = eo(1);
end
assert(all(cf == 0.95), 'B2 fixed-mode eta not constant');
% eta esc on the analytic bowl (test_m2 U2 style, 30 s)
M2_ETA_PARAMS = struct('mode', 'esc', 'center0', 0.8, 'lower', 0.75, ...
    'upper', 1.25, 'amplitude', 0.02, 'frequency', f0, 'hpOmega', 0.6, ...
    'lpOmega', 0.6, 'gain', 3.2e-3, 'rateLimit', 0.05);
ce = zeros(601, 1); eA = 0.8;
for k = 1:601
    t = (k - 1) * Ts;
    % rpm layout: u(19:22) lower rotors, u(23:26) upper; eta_act = eA
    uE = [t; 9; bowlPower(eA); 0; zeros(6, 1); 1500 * ones(8, 1); ...
        [repmat(rpm0, 4, 1); repmat(rpm0 * eA, 4, 1)]; zeros(8, 1); 0];
    eo = m2_eta_esc(uE);
    ce(k) = eo(1);
    eA = eA + Ts / 1.0 * (ce(k) - eA);
end
pLen = round(4.0 / Ts);
nP = floor(601 / pLen);
pm = arrayfun(@(j) mean(ce((j - 1) * pLen + 1:j * pLen)), 1:nP);
assert(abs(pm(end) - 1.0) <= 0.02, 'B2 esc-mode bowl convergence regressed');
% v fixed + v esc on a flat face (M0-C semantics)
M0C_ESC_PARAMS = struct('mode', 'fixed', 'center0', 8.5);
cv = zeros(81, 1);
for k = 1:81
    cv(k) = m0c_vref_esc([(k - 1) * Ts; 9; 251; 0; zeros(6, 1); zeros(8, 1)]);
end
assert(all(cv == 8.5), 'B2 fixed-mode v not constant');
M0C_ESC_PARAMS = struct('mode', 'esc', 'center0', 9.0, 'lower', 6.0, ...
    'upper', 12.0, 'amplitude', 0.3, 'frequency', f0, 'hpOmega', 0.6, ...
    'lpOmega', 0.6, 'gain', 6e-3, 'rateLimit', 2.0);
cv2 = zeros(401, 1);
for k = 1:401
    cv2(k) = m0c_vref_esc([(k - 1) * Ts; 9; 251; 0; zeros(6, 1); zeros(8, 1)]);
end
assert(max(abs(cv2 - 9.0)) <= 0.3 * 1.0001, 'B2 esc-mode v left the dither band');
assert(abs(mean(cv2) - 9.0) < 1e-9, 'B2 esc-mode v center drifted on a flat face');
fprintf('  old fixed/esc modes: unchanged (constant / bowl / flat semantics)\n');

%% ==================== B3: gating matrix ====================
fprintf('=== B3 gating matrix (doc 2.3 boolean table) ===\n');
% eta events: [name, expectedFrozenDuringEvent]
evEta = {'bit1', true; 'bit2', true; 'bit3', true; 'bit4', true; ...
    'bit5', false; 'bit6', true; 'bit7', true; ...
    'sat', true; 'eta0', true; 'peNaN', true};
for j = 1:size(evEta, 1)
    sig = gateRunEta(evEta{j, 1}, peB2);
    assert(~sig.preFrozen, 'B3 eta %s: clean window not dithering', evEta{j, 1});
    assert(sig.evFrozen == evEta{j, 2}, ...
        'B3 eta %s: gate frozen=%d, doc table says %d', ...
        evEta{j, 1}, sig.evFrozen, evEta{j, 2});
    assert(~sig.postFrozen, 'B3 eta %s: no recovery after the event', evEta{j, 1});
    fprintf('  eta %-5s: online gate frozen=%d (doc 2.3: %d) OK\n', ...
        evEta{j, 1}, sig.evFrozen, evEta{j, 2});
end
evV = {'bit1', true; 'bit2', true; 'bit3', true; 'bit4', true; ...
    'bit5', false; 'bit6', true; 'bit7', true; ...
    'vNaN', true; 'vOut', true; 'peNaN', true};
for j = 1:size(evV, 1)
    sig = gateRunV(evV{j, 1}, pvB2);
    assert(~sig.preFrozen, 'B3 v %s: clean window not dithering', evV{j, 1});
    assert(sig.evFrozen == evV{j, 2}, ...
        'B3 v %s: gate frozen=%d, doc table says %d', ...
        evV{j, 1}, sig.evFrozen, evV{j, 2});
    assert(~sig.postFrozen, 'B3 v %s: no recovery after the event', evV{j, 1});
    fprintf('  v   %-5s: online gate frozen=%d (doc 2.3: %d) OK\n', ...
        evV{j, 1}, sig.evFrozen, evV{j, 2});
end
fprintf('  v sat: n/a by construction (18-dim input, registered V1 limitation)\n');

%% ============ B4: 2-D toy convergence + session isolation ============
fprintf('=== B4 2-D toy convergence ===\n');
arbM = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 64.0, 'slotV', 32.0);
peT = peB2;   % eta toy set: gain 3.2e-3, full field set
gainSweep = [6e-3, 1.2e-2, 2.4e-2, 4.8e-2];
chosen = NaN;
for gi = 1:numel(gainSweep)
    pvT = struct('mode', 'm3', 'center0', 7.0, 'lower', 6.0, 'upper', 12.0, ...
        'amplitude', 0.3, 'frequency', f0, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
        'gain', gainSweep(gi), 'rateLimit', 2.0);
    rA = driveChannels('m3', 'm3', arbM, pvT, peT, 240, 7.0, 0.8);
    rB = driveChannels('m3', 'm3', arbM, ...
        setfieldlocal(pvT, 'center0', 11.0), peT, 240, 11.0, 0.8);
    mvA = mean(rA.candV(rA.searchV & rA.t >= 160 & rA.t < 192));
    mvB = mean(rB.candV(rB.searchV & rB.t >= 160 & rB.t < 192));
    meA = mean(rA.candE(rA.searchE & rA.t >= 192));
    fprintf('  v gain %.0e: |v-9| = %.3f / %.3f, |eta-1| = %.3f\n', ...
        gainSweep(gi), abs(mvA - 9.0), abs(mvB - 9.0), abs(meA - 1.0));
    if abs(mvA - 9.0) <= 0.1 && abs(mvB - 9.0) <= 0.1 && abs(meA - 1.0) <= 0.02
        chosen = gainSweep(gi);
        break;
    end
end
assert(~isnan(chosen), 'B4 no v gain on the toy sweep met the convergence criteria');
pvT = struct('mode', 'm3', 'center0', 7.0, 'lower', 6.0, 'upper', 12.0, ...
    'amplitude', 0.3, 'frequency', f0, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', chosen, 'rateLimit', 2.0);
fprintf('  chosen toy v gain = %g (smallest on the sweep, backfill doc 2.5)\n', chosen);
% full assertions with the chosen gain
assert(abs(meA - 1.0) <= 0.02, 'B4 eta center did not converge under slots');
assert(abs(mvA - 9.0) <= 0.1, 'B4 v center did not converge under slots');
% held center exactly frozen during the other channel's slots
assert(holdFrozen(rA.candV, rA.searchV), 'B4 v center moved during eta slots');
assert(holdFrozen(rA.candE, rA.searchE), 'B4 eta center moved during v slots');
fprintf('  both centers converge; held center exactly frozen in every hold run\n');

% duty-cycle recheck: same eta toy, v held at 9 in both arms
pvF9 = struct('mode', 'fixed', 'center0', 9.0);
peEsc = setfieldlocal(peT, 'mode', 'esc');
rCont = driveChannels('fixed', 'esc', [], pvF9, peEsc, 240, 9.0, 0.8);
rSlot = driveChannels('fixed', 'm3', arbM, pvF9, peT, 240, 9.0, 0.8);
stCont = convSearchSteps(rCont);
stSlot = convSearchSteps(rSlot);
assert(stSlot <= 1.15 * stCont && stCont <= 1.15 * stSlot, ...
    'B4 duty recheck: slotted eta needed %d search steps vs %d continuous', ...
    stSlot, stCont);
fprintf('  duty recheck: eta converges in %d search steps slotted vs %d continuous\n', ...
    stSlot, stCont);

% ---- session isolation and config snapshot
fprintf('=== B4 session isolation ===\n');
arbIso = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 64.0, 'slotV', 32.0);
pvIso = struct('mode', 'm3', 'center0', 7.0, 'lower', 6.0, 'upper', 12.0, ...
    'amplitude', 0.3, 'frequency', f0, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', chosen, 'rateLimit', 2.0);
peIso = peT;
% (a) explicit config vs ambient leftovers (wrong values AND extra fields)
M0C_ESC_PARAMS = struct('mode', 'fixed', 'center0', 3.0, 'gain', 1.0, 'bogus', 7);
M2_ETA_PARAMS = struct('mode', 'esc', 'center0', 0.5, 'gain', 9e-1, 'bogus', 8);
M3_ARB_PARAMS = struct('enable', 'on', 'firstSlot', 'v', ...
    'slotEta', 13.0, 'slotV', 7.0);
r1 = driveChannels('m3', 'm3', arbIso, pvIso, peIso, 10.0, 7.0, 0.8);
M0C_ESC_PARAMS = struct('mode', 'esc', 'center0', 11.0, 'gain', 5e-2, 'bogus', 9);
M2_ETA_PARAMS = struct('mode', 'fixed', 'center0', 1.2, 'gain', 2e-3, 'bogus', 10);
M3_ARB_PARAMS = struct('enable', 'on', 'firstSlot', 'eta', ...
    'slotEta', 31.0, 'slotV', 17.0);
r2 = driveChannels('m3', 'm3', arbIso, pvIso, peIso, 10.0, 7.0, 0.8);
assert(isequal(r1.candV, r2.candV) && isequal(r1.candE, r2.candE), ...
    'B4 ambient leftovers changed an explicitly configured run');
% (b) persistent fresh: identical outputs after clearing the adapters
clear('m0c_vref_esc'); clear('m2_eta_esc');
r3 = driveChannels('m3', 'm3', arbIso, pvIso, peIso, 10.0, 7.0, 0.8);
assert(isequal(r1.candV, r3.candV) && isequal(r1.candE, r3.candE), ...
    'B4 persistent state leaked across runs');
fprintf('  ambient independence and persistent fresh: bit-identical runs\n');
% (c) error-path restore: recursive child with the injected failure
cur = snapshotGlobals();
gotId = '';
try
    test_m3_coordination_unit('unit');
catch e
    gotId = e.identifier;
end
assert(strcmp(gotId, 'air:M3Test:InjectedFailure'), ...
    'B4 injected child failed with unexpected id %s', gotId);
assert(globalsEqualSnapshot(cur), 'B4 error path did not restore the globals');
fprintf('  error-path restore: child run restored globals exactly\n');

%% ============ B5: execution evidence + cross-talk ============
fprintf('=== B5 execution evidence ===\n');
selV = struct('lower', 6.0, 'upper', 12.0, 'rateLimit', 2.0, 'Ts', Ts, ...
    'amplitude', 0.3);
selE = struct('lower', 0.75, 'upper', 1.25, 'rateLimit', 0.05, 'Ts', Ts, ...
    'amplitude', 0.02);
applV = emulateSelector(rA.candV, selV);
applE = emulateSelector(rA.candE, selE);
chk = m3_check_execution(rA.t, rA.searchV, rA.searchE, rA.candV, ...
    rA.candE, applV, applE, selV, selE);
assert(chk.pass, 'B5 checker false alarm on the good run: %s', ...
    strjoin(chk.failFields, ','));
fprintf('  good alternating run: checker PASS (hold runs V=%d E=%d, no false alarm)\n', ...
    chk.nHoldRunsV, chk.nHoldRunsE);
% traitor: v channel keeps searching (esc) while eta obeys the schedule.
% The checker gets the SCHEDULE plan as the expectation and the traitor's
% actual candidate as the evidence -- exactly the trial-time arrangement.
pvTesc = setfieldlocal(pvT, 'mode', 'esc');
rT = driveChannels('esc', 'm3', arbM, pvTesc, peT, 240, 7.0, 0.8);
planV = false(numel(rT.t), 1); planE = false(numel(rT.t), 1);
for k = 1:numel(rT.t)
    ro = m3_schedule(rT.t(k), arbM);
    planV(k) = strcmp(ro.v, 'search');
    planE(k) = strcmp(ro.eta, 'search');
end
applVT = emulateSelector(rT.candV, selV);
applET = emulateSelector(rT.candE, selE);
chkT = m3_check_execution(rT.t, planV, planE, rT.candV, ...
    rT.candE, applVT, applET, selV, selE);
assert(~chkT.pass, 'B5 checker missed the traitor adapter');
assert(any(strcmp(chkT.failFields, 'holdConstancyV')), ...
    'B5 traitor must fail on holdConstancyV (got: %s)', ...
    strjoin(chkT.failFields, ','));
fprintf('  traitor adapter: rejected on field holdConstancyV (%s)\n', ...
    strjoin(chkT.failFields, ','));
% concurrent cross-talk on the same toy (mechanism-level necessity)
peTesc = setfieldlocal(peT, 'mode', 'esc');
rCC = driveChannels('esc', 'esc', [], pvTesc, peTesc, 240, 7.0, 0.8);
ctAlt = convSearchSteps(rA);
ctCC = convSearchSteps(rCC);
assert(ctCC > ctAlt, ...
    'B5 cross-talk: concurrent (%d steps) did not slow eta vs alternating (%d)', ...
    ctCC, ctAlt);
if isinf(ctCC)
    fprintf('  cross-talk: eta converged after %d search steps alternating, NEVER concurrently\n', ctAlt);
else
    fprintf('  cross-talk: eta convergence %d search steps alternating vs %d concurrent\n', ...
        ctAlt, ctCC);
end

%% ================= B6: evaluation fixtures ====================
fprintf('=== B6 evaluation fixtures ===\n');
tb = (0:0.05:240)';
nB = numel(tb);
% no valid window in the energy evaluation
got = catchId(@() m3_eval_energy(tb, 200 * ones(nB, 1), false(nB, 1), ...
    tb, 200 * ones(nB, 1), true(nB, 1), [144, 240], 0.5));
assert(strcmp(got, 'air:M3:NoValidWindow'), 'B6 no-valid-window: %s', got);
% hold-only pseudo-convergence must be rejected, not graded
got = catchId(@() m3_eval_convergence(tb, 1.0001 * ones(nB, 1), ...
    false(nB, 1), f0, 0.01, 5e-3));
assert(strcmp(got, 'air:M3:NoSearchWindow'), 'B6 hold-only: %s', got);
% missing pair arm
got = catchId(@() m3_eval_energy(tb, 200 * ones(nB, 1), true(nB, 1), ...
    [], [], [], [144, 240], 0.5));
assert(strcmp(got, 'air:M3:MissingPair'), 'B6 missing pair: %s', got);
% grid misalignment between arms
got = catchId(@() m3_eval_energy(tb, 200 * ones(nB, 1), true(nB, 1), ...
    tb + 0.01, 200 * ones(nB, 1), true(nB, 1), [144, 240], 0.5));
assert(strcmp(got, 'air:M3:GridMismatch'), 'B6 grid mismatch: %s', got);
% deliberate convergence breach: last-slot center 1.05
ctr = 1.05 * ones(nB, 1);
srchE = false(nB, 1); srchE(tb >= 192 & tb < 240) = true;
rc6 = m3_eval_convergence(tb, ctr, srchE, f0, 0.01, 5e-3);
assert(~rc6.converged, 'B6 breach: 1.05 center passed the 0.01 tolerance');
assert(rc6.monotonic, 'B6 breach: constant trace must stay monotonic');
% deliberate energy breach: +2% against a +0.5% threshold
re6 = m3_eval_energy(tb, 204 * ones(nB, 1), true(nB, 1), ...
    tb, 200 * ones(nB, 1), true(nB, 1), [144, 240], 0.5);
assert(~re6.pass && abs(re6.dEPct - 2.0) < 1e-9, ...
    'B6 breach: +2%% energy passed a +0.5%% threshold');
% positive control: -0.2% passes
re7 = m3_eval_energy(tb, 199.6 * ones(nB, 1), true(nB, 1), ...
    tb, 200 * ones(nB, 1), true(nB, 1), [144, 240], 0.5);
assert(re7.pass && abs(re7.dEPct + 0.2) < 1e-9, 'B6 positive control failed');
fprintf('  fixtures: 4 exact error ids + breach/positive controls all land correctly\n');

ok = true;
fprintf('M3 COORDINATION UNIT TESTS PASS\n');
end

% ---------------------------------------------------------------------------
function id = catchId(fn)
%CATCHID run fn, return the thrown identifier (fail if no error).
id = '';
try
    fn();
catch e
    id = e.identifier;
end
assert(~isempty(id), 'expected an error but the call succeeded');
end

function s = setfieldlocal(s, name, value)
%SETFIELDLOCAL copy-with-field (struct assignment in one expression).
s.(name) = value;
end

function s = snapshotGlobals()
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
s = struct('M0C', M0C_ESC_PARAMS, 'M2P', M2_ETA_PARAMS, ...
    'M2A', M2_ETA_APPLIED, 'M3A', M3_ARB_PARAMS);
end

function eq = globalsEqualSnapshot(s)
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
eq = isequal(M0C_ESC_PARAMS, s.M0C) && isequal(M2_ETA_PARAMS, s.M2P) ...
    && isequal(M2_ETA_APPLIED, s.M2A) && isequal(M3_ARB_PARAMS, s.M3A);
end

function m3_cleanup(snap)
%M3_CLEANUP restore the entry-time globals (empty stays empty) and wipe
%   both adapters' persistent state; runs on success AND error paths.
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
M0C_ESC_PARAMS = snap.M0C; M2_ETA_PARAMS = snap.M2P;
M2_ETA_APPLIED = snap.M2A; M3_ARB_PARAMS = snap.M3A;
clear('m0c_vref_esc'); clear('m2_eta_esc');
end

function P = bowlPower(eta)
%BOWLPOWER analytic proxy power at fixed total thrust (test_m2 pattern).
g = @(x) (1 + x^3) / (1 + x^2)^1.5;
P = 251.0 * g(eta) / g(1.0);
end

function P = pwr2d(~, vA, eA)
%PWR2D 2-D toy (M3 doc 4.4): eta bowl x v bowl, both with real gradients.
g = @(x) (1 + x^3) / (1 + x^2)^1.5;
P = 251.0 * g(eA) / g(1.0) * (1 + 0.02 * (vA - 9.0)^2);
end

function m = measPlain(~, ~, vA, eA)
%MEASPLAIN default measurement: clean flags, true plant states.
m = struct();
m.vFeed = vA; m.eFeed = eA;
m.flagsV = zeros(1, 8); m.flagsE = zeros(1, 8); m.sat = 0;
end

function r = driveChannels(modeV, modeE, arb, pv, pe, T, v0, eta0)
%DRIVECHANNELS both adapters on the 2-D toy at Ts = 0.05, first-order
%   actuator tau = 1 s on both channels; roles recorded from the plan
%   (m3 channels) or all-search (esc channels).
global M0C_ESC_PARAMS M2_ETA_PARAMS M3_ARB_PARAMS M2_ETA_APPLIED
M0C_ESC_PARAMS = pv; M2_ETA_PARAMS = pe; M3_ARB_PARAMS = arb;
M2_ETA_APPLIED = 1.0;
Ts = 0.05; tau = 1.0;
n = round(T / Ts);
t = (0:n - 1)' * Ts;
candV = zeros(n, 1); candE = zeros(n, 1);
sV = false(n, 1); sE = false(n, 1);
vAct = zeros(n, 1); eAct = zeros(n, 1);
vA = v0; eA = eta0;
for k = 1:n
    m = measPlain(t(k), k, vA, eA);
    Pe = pwr2d(t(k), vA, eA);
    uV = [t(k); m.vFeed; Pe; 0; zeros(6, 1); m.flagsV(:)];
    candV(k) = m0c_vref_esc(uV);
    rpmLo = 500 * 60 / (2 * pi);
    rpmUp = 500 * m.eFeed * 60 / (2 * pi);
    uE = [t(k); m.vFeed; Pe; 0; zeros(6, 1); 1500 * ones(8, 1); ...
        [repmat(rpmLo, 4, 1); repmat(rpmUp, 4, 1)]; m.flagsE(:); m.sat];
    eo = m2_eta_esc(uE);
    candE(k) = eo(1);
    if strcmp(modeV, 'm3')
        sV(k) = strcmp(m3_schedule(t(k), arb).v, 'search');
    else
        sV(k) = true;
    end
    if strcmp(modeE, 'm3')
        sE(k) = strcmp(m3_schedule(t(k), arb).eta, 'search');
    else
        sE(k) = true;
    end
    vAct(k) = vA; eAct(k) = eA;
    vA = vA + Ts / tau * (candV(k) - vA);
    eA = eA + Ts / tau * (candE(k) - eA);
end
r = struct('t', t, 'candV', candV, 'candE', candE, 'searchV', sV, ...
    'searchE', sE, 'vAct', vAct, 'eAct', eAct);
end

function fro = holdFrozen(cand, search)
%HOLDFROZEN every maximal hold run has an exactly constant candidate.
runs = holdRunsLocal(search);
fro = true;
for j = 1:size(runs, 1)
    seg = cand(runs(j, 1):runs(j, 2));
    if max(seg) - min(seg) > 0
        fro = false;
        return;
    end
end
end

function runs = holdRunsLocal(search)
n = numel(search);
holdLgl = ~search(:);
padded = [false; holdLgl; false];
d = diff(padded);
runs = [find(d == 1), find(d == -1) - 1];
if isempty(runs)
    runs = zeros(0, 2);
end
end

function s = convSearchSteps(r)
%CONVSEARCHSTEPS eta search steps to convergence: blocks of 80 search
%   samples (one dither period); converged at block b when every block
%   mean from b on stays within 0.02 of 1.0. Inf when never.
c = r.candE; sr = r.searchE;
cs = c(sr);
bLen = 80; nB = floor(numel(cs) / bLen);
assert(nB >= 2, 'convSearchSteps: not enough search samples');
bm = arrayfun(@(j) mean(cs((j - 1) * bLen + 1:j * bLen)), 1:nB);
s = Inf;
for j = 1:nB
    if max(abs(bm(j:end) - 1.0)) <= 0.02
        s = (j - 1) * bLen;
        break;
    end
end
end

function a = emulateSelector(cand, prm)
%EMULATESELECTOR band-clamp + rate-limit application of the candidate
%   (mirrors ratioesc.limit_reference, the selector/allocator path).
a = zeros(size(cand));
for k = 1:numel(cand)
    req = min(max(cand(k), prm.lower), prm.upper);
    if k == 1
        a(k) = req;
    else
        d = prm.rateLimit * prm.Ts;
        a(k) = a(k - 1) + min(max(req - a(k - 1), -d), d);
    end
end
end

function sig = gateRunEta(evName, peStruct)
%GATERUNETA 6 s eta-adapter run: clean [0,2), event [2,4), recovery [4,6).
%   frozen = candidate exactly constant (kernel invalid path holds the
%   reference; a valid search always carries the dither).
global M2_ETA_PARAMS M3_ARB_PARAMS
Ts = 0.05; n = 121;
M2_ETA_PARAMS = peStruct;
M3_ARB_PARAMS = struct('enable', 'on', 'firstSlot', 'eta', ...
    'slotEta', 1000.0, 'slotV', 1.0);
cand = zeros(n, 1);
rpm0 = 500 * 60 / (2 * pi);
for k = 1:n
    t = (k - 1) * Ts;
    flags = zeros(1, 8); sat = 0; Pe = 251.0; eAct = 1.0;
    if t >= 2.0 - 1e-9 && t < 4.0 - 1e-9
        switch evName
            case 'bit1', flags(1) = 1;
            case 'bit2', flags(2) = 1;
            case 'bit3', flags(3) = 1;
            case 'bit4', flags(4) = 1;
            case 'bit5', flags(5) = 1;
            case 'bit6', flags(6) = 1;
            case 'bit7', flags(7) = 1;
            case 'sat', sat = 1;
            case 'eta0', eAct = 0.0;
            case 'peNaN', Pe = NaN;
        end
    end
    rpmUp = 500 * eAct * 60 / (2 * pi);
    uE = [t; 9; Pe; 0; zeros(6, 1); 1500 * ones(8, 1); ...
        [repmat(rpm0, 4, 1); repmat(rpmUp, 4, 1)]; flags(:); sat];
    eo = m2_eta_esc(uE);
    cand(k) = eo(1);
end
sig = struct('preFrozen', isConst(cand(1:40)), ...
    'evFrozen', isConst(cand(41:80)), ...
    'postFrozen', isConst(cand(81:120)));
end

function sig = gateRunV(evName, pvStruct)
%GATERUNV the v-channel twin of gateRunEta (v searches throughout).
global M0C_ESC_PARAMS M3_ARB_PARAMS
Ts = 0.05; n = 121;
M0C_ESC_PARAMS = pvStruct;
M3_ARB_PARAMS = struct('enable', 'on', 'firstSlot', 'v', ...
    'slotEta', 1.0, 'slotV', 1000.0);
cand = zeros(n, 1);
for k = 1:n
    t = (k - 1) * Ts;
    flags = zeros(1, 8); Pe = 251.0; vFeed = 9.0;
    if t >= 2.0 - 1e-9 && t < 4.0 - 1e-9
        switch evName
            case 'bit1', flags(1) = 1;
            case 'bit2', flags(2) = 1;
            case 'bit3', flags(3) = 1;
            case 'bit4', flags(4) = 1;
            case 'bit5', flags(5) = 1;
            case 'bit6', flags(6) = 1;
            case 'bit7', flags(7) = 1;
            case 'vNaN', vFeed = NaN;
            case 'vOut', vFeed = 13.0;
            case 'peNaN', Pe = NaN;
        end
    end
    uV = [t; vFeed; Pe; 0; zeros(6, 1); flags(:)];
    cand(k) = m0c_vref_esc(uV);
end
sig = struct('preFrozen', isConst(cand(1:40)), ...
    'evFrozen', isConst(cand(41:80)), ...
    'postFrozen', isConst(cand(81:120)));
end

function c = isConst(x)
c = max(x) - min(x) < 1e-12;
end
