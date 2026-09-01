%RUN_AIR_M2_TRIALS M2 paired eta trials (plan: M2_ETA_ALLOCATOR.md section 7).
%   Fixed-eta baselines E1/E2/E3 (0.8/1.0/1.2; E2 = passthrough identity),
%   esc runs S1/S2/S3 started from each center, a disturbed-scenario pair,
%   and one reproducibility repeat. Runs: 120 s for the nominal pairs
%   (settled [90,120] s gate window, [20,30] s continuity reported),
%   30 s for the disturbed pair. Speed loop + optimizer enabled, same
%   model and wiring, only the global M2_ETA_PARAMS differs.
%   Metrics per run: eta tracking, allocator sat/dmz, yaw rate, flags,
%   PWM spread, convergence (period-mean of eta_ref); pair delta-energy
%   over the same continuous time grid (932c55d hardened convention);
%   fixed-vs-fixed power deltas E1/E3 vs E2 as the non-trivial P(eta)
%   surface evidence (model-estimated only).
%
%   FUNCTION ENTRY (ACCEPTANCE_AUTOMATION_RULES.md rule 2.1): returns the
%   machine-checkable result; failures never rely on printed output.
%   injectError = 'trials' short-circuits with result.pass = false after
%   the entry/exit state contract is set up (controlled-failure hook for
%   the round-4 closure verification; default '' = normal behaviour).

function result = run_air_m2_trials(injectError)
if nargin < 1
    injectError = '';
end

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));

global M2_ETA_PARAMS M2_ETA_APPLIED
% R2-F1 (round-2 reacceptance): the trials are themselves a stale-state
% source -- snapshot the caller's globals on entry and restore them on
% exit (success or error; reliable here because this is a function frame).
% The session chain normalizes explicitly BEFORE calling.
trialsSavedParams = [];
trialsSavedApplied = [];
if ~isempty(M2_ETA_PARAMS), trialsSavedParams = M2_ETA_PARAMS; end
if ~isempty(M2_ETA_APPLIED) && isfinite(M2_ETA_APPLIED)
    trialsSavedApplied = M2_ETA_APPLIED;
end
trialsCleanup = onCleanup(@() m2trials_restore_globals( ...
    trialsSavedParams, trialsSavedApplied)); %#ok<NASGU>
M2_ETA_PARAMS = struct('mode', 'fixed', 'center0', 1.0);
M2_ETA_APPLIED = 1.0;

% controlled-failure hook (round-4 closure condition 3): short-circuit
% AFTER the entry/exit state contract so the restore is exercised without
% running any simulation
if strcmp(injectError, 'trials')
    result = struct('pass', false, 'reproducible', false, ...
        'archiveDir', "injected");
    fprintf('run_air_m2_trials: injected controlled failure (pass=false)\n');
    return;
end

% Protocol (reacceptance F1/Z4, pre-registered 2026-09-01 BEFORE the
% verification reruns): the nominal pair runs extend 30 -> 120 s and the
% pair gate window moves to the settled window [90,120] s. Rationale: the
% S1/S3 gates measure the optimizer's converged energy against the fixed
% baseline; a window inside the approach phase conflates the documented
% convergence-in-progress penalty with optimizer quality (the esc center
% needs ~100 s to travel from 1.2 to the 1.0 optimum on the model's
% shallow P(eta) bowl). The +/-0.5% gate itself is UNCHANGED; [20,30]
% continuity values are still reported; the disturbed pair stays 30 s and
% report-only. Cross-session jitter fingerprint: ulp-level float
% differences cross uint16 rounding boundaries (attitude differential at
% pwm 1500.5) and jitter dE by ~+/-0.015 pp -- an order of magnitude below
% the margin this protocol builds.
plan = { ...
    'E1_fixed',  1, 'fixed', 0.8, 120.0; ...
    'E2_fixed',  1, 'fixed', 1.0, 120.0; ...
    'E3_fixed',  1, 'fixed', 1.2, 120.0; ...
    'S1_esc',    1, 'esc',   0.8, 120.0; ...
    'S2_esc',    1, 'esc',   1.0, 120.0; ...
    'S3_esc',    1, 'esc',   1.2, 120.0; ...
    'DE2_fixed', 0, 'fixed', 1.0,  30.0; ...
    'DS2_esc',   0, 'esc',   1.0,  30.0; ...
    'R_esc',     1, 'esc',   1.0, 120.0};
BAND = [0.75, 1.25];
BAND_TOL = 0.02;
PERIOD = 4.0;               % dither period, s (0.25 Hz)
GATE_WIN = [90.0, 120.0];   % settled pair comparison window (gate)
CONT_WIN = [20.0, 30.0];    % continuity window (reported, not gated)

outDir = fullfile(wsRoot, 'results', 'air_m2_trials', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

R = struct();
ok = true;
for k = 1:size(plan, 1)
    name = plan{k, 1};
    nominal = plan{k, 2} == 1;
    mode = plan{k, 3};
    center0 = plan{k, 4};
    stopT = plan{k, 5};
    fprintf('=== %s (mode %s, center %.2f, %s, %.0f s) ===\n', name, mode, ...
        center0, ternary(nominal, 'nominal', 'disturbed'), stopT);
    M2_ETA_PARAMS = struct('mode', mode, 'center0', center0);
    % deterministic first-sample initialization: the allocator must not
    % inherit the previous run's applied ratio before the ESC's first
    % 0.05 s update lands (the ESC outputs center0 at t=0 by definition)
    M2_ETA_APPLIED = center0;
    if bdIsLoaded(model)
        close_system(model, 0);
    end
    load_system(fullfile(modelDir, [model '.slx']));
    set_param(model, 'StopTime', num2str(stopT));
    set_param([model '/M0B Speed Loop Enable'], 'Value', '1');
    set_param([model '/M0A Optimizer Enable'], 'Value', '1');
    set_param([model '/M0B v Ref Manual'], 'Value', '5');
    if nominal
        % roll-sine disturbance off for this run only (in memory)
        set_param([model '/Attitude Control/InputConditioning/Sine Wave'], ...
            'Amplitude', '0');
    end
    try
        out = sim(model);
        Mb = double(squeeze(out.get('m0b_log_bus').Data));
        if size(Mb, 2) ~= 7
            Mb = Mb';
        end
        tb = out.get('m0b_log_bus').Time(:);
        A = double(squeeze(out.get('m0a_log_bus').Data));
        if size(A, 2) ~= 35
            A = A';
        end
        ta = out.get('m0a_log_bus').Time(:);
        Pts = out.get('m0a_P_est_W');
        P = double(Pts.Data(:));
        tp = Pts.Time(:);
        Ets = out.get('m0a_E_est_J');
        E = double(Ets.Data(:));
        te = Ets.Time(:);
        Pe = interp1(tp, P, ta, 'previous', P(1));
        Ee = interp1(te, E, ta, 'previous', E(1));
        Lg = out.get('m2_eta_log');
        el = double(squeeze(Lg.Data));
        if size(el, 2) ~= 4
            el = el';
        end
        te2 = Lg.Time(:);

        r = evalRun(name, mode, center0, nominal, Mb, tb, A, ta, Pe, Ee, ...
            el, te2, BAND, BAND_TOL, PERIOD, stopT);
        R.(name) = r;
        printRun(r);
        save(fullfile(outDir, [name '.mat']), 'r', 'Mb', 'tb', 'A', 'ta', ...
            'Pe', 'Ee', 'el', 'te2');
        if ~r.ok
            ok = false;
        end
    catch err
        fprintf('  %s FAILED: %s\n', name, err.message);
        R.(name) = struct('name', name, 'ok', false);
        ok = false;
    end
    if bdIsLoaded(model)
        close_system(model, 0);
    end
end

% ---- per-run summary table ------------------------------------------------
fn = fieldnames(R);
rows = {};
for k = 1:numel(fn)
    r = R.(fn{k});
    if ~r.ok && ~isfield(r, 'etaTrk')
        rows(end + 1, :) = {r.name, '-', NaN, NaN, NaN, NaN, NaN, NaN, ...
            NaN, false}; %#ok<AGROW>
        continue
    end
    rows(end + 1, :) = {r.name, r.mode, r.center0, r.cleanFrac, ...
        r.etaTrk, r.Pmean, r.Eclean, r.convT, r.nFrozen + r.nFb, r.ok}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'run', 'mode', 'center0', ...
    'cleanFrac', 'etaTrk', 'Pmean_W', 'Eclean_J', 'convT_s', ...
    'trips', 'ok'});
writetable(T, fullfile(outDir, 'summary.csv'));
disp(T);

% ---- pair summaries: esc arms against the fixed eta = 1 baseline ----------
pairs = {'S1', 'S2', 'S3'};
prows = {};
for k = 1:numel(pairs)
    pfx = pairs{k};
    if isfield(R, [pfx '_esc']) && isfield(R, 'E2_fixed') && ...
            R.([pfx '_esc']).ok && R.E2_fixed.ok
        Sf = load(fullfile(outDir, 'E2_fixed.mat'), 'ta', 'Pe');
        Se = load(fullfile(outDir, [pfx '_esc.mat']), 'ta', 'Pe');
        [dE, Pf, Pe_] = pairDeltaE(Sf, Se, GATE_WIN);
        [dEc, ~, ~] = pairDeltaE(Sf, Se, CONT_WIN);
        e = R.([pfx '_esc']);
        prows(end + 1, :) = {pfx, Pf, Pe_, dE, dEc, e.convT}; %#ok<AGROW>
        fprintf('%s vs E2: dE[90,120] = %+.5f%% (gate), dE[20,30] = %+.5f%%\n', pfx, dE, dEc);
        if ~(dE <= 0.5)
            ok = false;
            fprintf('  %s NOT-WORSE-THAN-BASELINE gate failed\n', pfx);
        end
    else
        ok = false;
    end
end
if ~isempty(prows)
    T2 = cell2table(prows, 'VariableNames', {'pair', 'P_fixed_W', ...
        'P_esc_W', 'delta_E_pct', 'delta_E_cont_pct', 'esc_convT_s'});
    writetable(T2, fullfile(outDir, 'pairs.csv'));
    disp(T2);
end

% ---- fixed-vs-fixed power surface evidence (E1/E3 vs E2) -------------------
frows = {};
for pfx = {'E1', 'E3'}
    if R.([pfx{1} '_fixed']).ok && R.E2_fixed.ok
        Sf = load(fullfile(outDir, [pfx{1} '_fixed.mat']), 'ta', 'Pe');
        Sb = load(fullfile(outDir, 'E2_fixed.mat'), 'ta', 'Pe');
        [dE, Pf, Pb] = pairDeltaE(Sb, Sf, GATE_WIN);
        frows(end + 1, :) = {pfx{1}, Pf, Pb, dE}; %#ok<AGROW>
        fprintf('%s vs E2 (fixed surface): dE = %+.4f%%\n', pfx{1}, dE);
    end
end
if ~isempty(frows)
    T3 = cell2table(frows, 'VariableNames', {'fixed_run', 'P_E2_W', ...
        'P_run_W', 'delta_E_pct'});
    writetable(T3, fullfile(outDir, 'fixed_surface.csv'));
    disp(T3);
end

% ---- disturbed pair (reported honestly, not gated) --------------------------
if isfield(R, 'DE2_fixed') && isfield(R, 'DS2_esc') && ...
        R.DE2_fixed.ok && R.DS2_esc.ok
    Sf = load(fullfile(outDir, 'DE2_fixed.mat'), 'ta', 'Pe');
    Se = load(fullfile(outDir, 'DS2_esc.mat'), 'ta', 'Pe');
    [dEd, ~, ~] = pairDeltaE(Sf, Se, [20.0, 30.0]);
    fprintf('disturbed pair DS2 vs DE2: dE = %+.5f%% (reported, not gated)\n', ...
        dEd);
    fid = fopen(fullfile(outDir, 'disturbed_pair.txt'), 'w');
    fprintf(fid, 'DS2_esc - DE2_fixed dE%% = %+.5f\n', dEd);
    fclose(fid);
end

% ---- reproducibility --------------------------------------------------------
reproOK = false;
try
    S1 = load(fullfile(outDir, 'S2_esc.mat'));
    S2 = load(fullfile(outDir, 'R_esc.mat'));
    n = min(numel(S1.te2), numel(S2.te2));
    dv = max(abs(S1.el(1:n, 1) - S2.el(1:n, 1)));
    fprintf('reproducibility S2_esc vs R_esc: max|d eta_ref| = %.3g\n', dv);
    reproOK = dv < 1e-9;
catch err
    fprintf('reproducibility check could not run: %s\n', err.message);
end
if ~reproOK
    ok = false;
end
fprintf('reproducibility: %d\n', reproOK);

result = struct('pass', ok, 'reproducible', reproOK, ...
    'archiveDir', string(outDir));
save(fullfile(outDir, 'result.mat'), 'result');
if ok
    fprintf('M2 TRIALS PASS\n');
else
    fprintf('M2 TRIALS FAIL (see summary above)\n');
end
fprintf('Archive: %s\n', outDir);
end

% ---------------------------------------------------------------------------
function [dE, Pf, Pe2] = pairDeltaE(Sf, Se, commonWin)
%PAIRDELTAE delta-energy on the same continuous time grid (932c55d).
    assert(numel(Sf.ta) == numel(Se.ta) && ...
        max(abs(Sf.ta - Se.ta)) < 1e-12, ...
        'air:M2:PairTimeGridMismatch', ...
        'pair runs do not share the same time grid.');
    cw = Sf.ta >= commonWin(1) & Sf.ta <= commonWin(2);
    assert(nnz(cw) >= 2, 'air:M2:PairWindowEmpty', ...
        'common comparison window is empty.');
    Efixed = trapz(Sf.ta(cw), Sf.Pe(cw));
    Eesc = trapz(Se.ta(cw), Se.Pe(cw));
    dE = 100 * (Eesc - Efixed) / max(Efixed, eps);
    Pf = mean(Sf.Pe(cw));
    Pe2 = mean(Se.Pe(cw));
end

function r = evalRun(name, mode, center0, nominal, Mb, tb, A, ta, Pe, Ee, ...
    el, te2, band, bandTol, period, stopT)
%EVALRUN per-run metrics; cost window = active samples with flag5 quiet.
    status = Mb(:, 4);
    flag5 = A(:, 31);   % bus columns 27..34 = flags 1..8

    base = tb >= 0.005;
    act = base & status == 2 & flag5 < 0.5;
    eng = base & (status == 1 | status == 2) & flag5 < 0.5;
    cleanFrac = mean(act(base));
    gateEngaged = mean(eng(tb >= 5.0));

    Pmean = mean(Pe(act));
    Eclean = trapz(tb(act), Pe(act));

    % eta log (0.05 s grid): [eta_ref, eta_act, sat, dmz]
    eb = te2 >= 0.025;
    etaRef = el(:, 1);
    etaAct = el(:, 2);
    sat = el(:, 3);
    dmz = el(:, 4);
    late = te2 >= 2.0;
    bandOK = all(etaRef(late) >= band(1) - bandTol & ...
        etaRef(late) <= band(2) + bandTol);
    sf2 = interp1(tb, [status flag5], te2, 'previous', 0);
    f52 = interp1(tb, flag5, te2, 'previous', 0);
    cleanE = eb & sf2(:, 1) == 2 & f52 < 0.5;
    trkMask = cleanE & sat < 0.5 & etaAct > 0;
    etaTrk = mean(abs(etaAct(trkMask) - etaRef(trkMask)));
    satFrac = mean(sat(eb) > 0.5);
    dmzMax = max(abs(dmz(eb)));
    dmzRMS = sqrt(mean(dmz(eb) .^ 2));

    % constraint activity (hard bits 1,2,3,4,6,7 -> cols 27:30,32,33)
    hard = any(A(:, 27:30) > 0.5, 2) | any(A(:, 32:33) > 0.5, 2);
    hardMax = max(hard(base));
    flag5Frac = mean(A(base, 31) > 0.5);
    nFrozen = sum(diff(status == 3) == 1);
    nFb = sum(diff(status == 4) == 1);

    % actuator spread on the clean window
    pwm = A(act, 11:18);
    pwmMin = min(pwm, [], 'all');
    pwmMax = max(pwm, [], 'all');
    yawMax = max(abs(A(base, 10)));

    % convergence (esc runs): period means of eta_ref settled within 0.01
    convT = NaN;
    if strcmp(mode, 'esc')
        pLen = round(period / 0.05);
        nP = floor(numel(etaRef) / pLen);
        m = arrayfun(@(j) mean(etaRef((j - 1) * pLen + 1:j * pLen)), 1:nP);
        for j = 1:nP
            if max(m(j:end)) - min(m(j:end)) <= 0.01
                convT = (j - 1) * period;
                break
            end
        end
    end

    % Z2 hard gates (reacceptance F4): the aggregate PASS must cover every
    % acceptance condition in the interface doc, not only a subset.
    % All runs: eta in band, no fallback, no allocator saturation, yaw rate
    % inside the flag-4 threshold (1.5 rad/s), eta tracking within 0.02.
    % Nominal additionally: hard flags silent, selector engaged, pwm
    % inside the +-5 us flag margins. Esc nominal: convergence reached.
    runOK = bandOK && nFb == 0 && satFrac == 0 && yawMax <= 1.5 && ...
        etaTrk <= 0.02;
    if nominal
        runOK = runOK && hardMax == 0 && gateEngaged >= 0.95 && ...
            pwmMin >= 1005.0 && pwmMax <= 1995.0;
        if strcmp(mode, 'esc')
            runOK = runOK && ~isnan(convT);
        end
    end
    r = struct('name', name, 'mode', mode, 'center0', center0, ...
        'nominal', nominal, 'ok', runOK, 'cleanFrac', cleanFrac, ...
        'gateEngaged', gateEngaged, 'Pmean', Pmean, 'Eclean', Eclean, ...
        'bandOK', bandOK, 'etaTrk', etaTrk, 'satFrac', satFrac, ...
        'dmzMax', dmzMax, 'dmzRMS', dmzRMS, 'yawMax', yawMax, ...
        'convT', convT, 'nFrozen', nFrozen, 'nFb', nFb, ...
        'hardMax', hardMax, 'flag5Frac', flag5Frac, ...
        'pwmMin', pwmMin, 'pwmMax', pwmMax, 'etaRefFinal', etaRef(end), ...
        'stopT', stopT);
end

function printRun(r)
%PRINTRUN one-line human summary of a run.
    fprintf(['  act %.2f  etaTrk %.4f  P %.1f W  Eclean %.0f J  ' ...
        'convT %.1f s  sat %.3f  dmz max %.3e  yaw %.3f  frozen %d  ' ...
        'fb %d  hard %d  flag5 %.2f  pwm [%.0f %.0f]  band %d  ' ...
        'etaRef(end) %.4f\n'], r.cleanFrac, r.etaTrk, r.Pmean, ...
        r.Eclean, r.convT, r.satFrac, r.dmzMax, r.yawMax, r.nFrozen, ...
        r.nFb, r.hardMax, r.flag5Frac, r.pwmMin, r.pwmMax, r.bandOK, ...
        r.etaRefFinal);
end

function s = ternary(c, a, b)
if c
    s = a;
else
    s = b;
end
end

function m2trials_restore_globals(savedParams, savedApplied)
%M2TRIALS_RESTORE_GLOBALS R2-F1: put M2 globals back to their entry-time
%   values (empty stays empty -- the safe identity default) after the
%   trials, on success and on any error path.
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
