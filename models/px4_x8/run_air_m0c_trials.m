%RUN_AIR_M0C_TRIALS M0-C paired no-noise trials (plan: M0C_SPEED_ESC.md §5).
%   Four pairs (same model, same wiring; the optimizer is the m0c_vref_esc
%   wrapper, 'fixed' = constant center0, 'esc' = online search) plus one
%   reproducibility repeat:
%     T1 nominal, center 7   T2 nominal, center 9   T3 nominal, center 11
%     DT2 disturbed (baseline roll sine), center 9
%     R   T2-esc repeated (determinism, max|dv_ref| < 1e-9)
%   Each run: 30 s, speed loop + optimizer enabled, manual fallback 5 m/s.
%   Metrics per run: cost window = ACTIVE samples only (status 2, flag5
%   quiet; codex reacceptance 4.1 -- warm-up/ramp status 1 excluded),
%   tracking error, mean/integral power, engagement counts, PWM spread,
%   band respect; convergence time for esc runs (period-mean definition);
%   pair delta-energy over the same continuous [20,30] s time grid.

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));

global M0C_ESC_PARAMS
% compile-probe safe: the global exists before the first update/sim
M0C_ESC_PARAMS = struct('mode', 'esc', 'center0', 9.0);

plan = { ...
    'T1_fixed', 1, 'fixed', 7.0; ...
    'T1_esc',   1, 'esc',   7.0; ...
    'T2_fixed', 1, 'fixed', 9.0; ...
    'T2_esc',   1, 'esc',   9.0; ...
    'T3_fixed', 1, 'fixed', 11.0; ...
    'T3_esc',   1, 'esc',   11.0; ...
    'DT2_fixed', 0, 'fixed', 9.0; ...
    'DT2_esc',   0, 'esc',   9.0; ...
    'R_esc',    1, 'esc',   9.0};
STOP_T = 30.0;
BAND = [6.0, 12.0];
PERIOD = 4.0;               % dither period, s (0.25 Hz)
COMMON_WIN = [20.0, 30.0];  % common pair comparison window

outDir = fullfile(wsRoot, 'results', 'air_m0c_trials', ...
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
    fprintf('=== %s (mode %s, center %.1f, %s) ===\n', name, mode, ...
        center0, ternary(nominal, 'nominal', 'disturbed'));
    M0C_ESC_PARAMS = struct('mode', mode, 'center0', center0);
    if bdIsLoaded(model)
        close_system(model, 0);
    end
    load_system(fullfile(modelDir, [model '.slx']));
    set_param(model, 'StopTime', num2str(STOP_T));
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
        % P_est logs on a 4 ms grid, E_est on the 1 ms grid (M0-A power
        % subsystem sample times); align both onto the 1 ms log grid
        Pts = out.get('m0a_P_est_W');
        P = double(Pts.Data(:));
        tp = Pts.Time(:);
        Ets = out.get('m0a_E_est_J');
        E = double(Ets.Data(:));
        te = Ets.Time(:);
        Pe = interp1(tp, P, ta, 'previous', P(1));
        Ee = interp1(te, E, ta, 'previous', E(1));

        r = evalRun(name, mode, center0, nominal, Mb, tb, A, ta, Pe, Ee, ...
            BAND, PERIOD, STOP_T);
        R.(name) = r;
        printRun(r);
        save(fullfile(outDir, [name '.mat']), 'r', 'Mb', 'tb', 'A', 'ta', ...
            'Pe', 'Ee');
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
    if ~r.ok
        rows(end + 1, :) = {r.name, '-', NaN, NaN, NaN, NaN, NaN, NaN, ...
            NaN, false}; %#ok<AGROW>
        continue
    end
    rows(end + 1, :) = {r.name, r.mode, r.center0, r.cleanFrac, ...
        r.errMean, r.Pmean, r.Eclean, r.convT, r.nFrozen + r.nFb, ...
        r.ok}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'run', 'mode', 'center0', ...
    'cleanFrac', 'errMean_mps', 'Pmean_W', 'Eclean_J', 'convT_s', ...
    'trips', 'ok'});
writetable(T, fullfile(outDir, 'summary.csv'));
disp(T);

% ---- pair summaries --------------------------------------------------------
pairs = {'T1', 'T2', 'T3', 'DT2'};
prows = {};
for k = 1:numel(pairs)
    pfx = pairs{k};
    if isfield(R, [pfx '_fixed']) && isfield(R, [pfx '_esc']) && ...
            R.([pfx '_fixed']).ok && R.([pfx '_esc']).ok
        f = R.([pfx '_fixed']);
        e = R.([pfx '_esc']);
        Sf = load(fullfile(outDir, [pfx '_fixed.mat']), 'ta', 'Pe');
        Se = load(fullfile(outDir, [pfx '_esc.mat']), 'ta', 'Pe');
        assert(numel(Sf.ta) == numel(Se.ta) && ...
            max(abs(Sf.ta - Se.ta)) < 1e-12, ...
            'air:M0C:PairTimeGridMismatch', ...
            '%s fixed/esc runs do not share the same time grid.', pfx);
        cw = Sf.ta >= COMMON_WIN(1) & Sf.ta <= COMMON_WIN(2);
        assert(nnz(cw) >= 2, 'air:M0C:PairWindowEmpty', ...
            '%s common comparison window is empty.', pfx);
        Pfixed = mean(Sf.Pe(cw));
        Pesc = mean(Se.Pe(cw));
        Efixed = trapz(Sf.ta(cw), Sf.Pe(cw));
        Eesc = trapz(Sf.ta(cw), Se.Pe(cw));
        dE = 100 * (Eesc - Efixed) / max(Efixed, eps);
        prows(end + 1, :) = {pfx, Pfixed, Pesc, Efixed, ...
            Eesc, dE, e.convT}; %#ok<AGROW>
    end
end
if ~isempty(prows)
    T2 = cell2table(prows, 'VariableNames', {'pair', 'P_fixed_W', ...
        'P_esc_W', 'E_fixed_J', 'E_esc_J', 'delta_E_pct', 'esc_convT_s'});
    writetable(T2, fullfile(outDir, 'pairs.csv'));
    disp(T2);
end

% ---- reproducibility -------------------------------------------------------
reproOK = false;
try
    S1 = load(fullfile(outDir, 'T2_esc.mat'));
    S2 = load(fullfile(outDir, 'R_esc.mat'));
    n = min(numel(S1.tb), numel(S2.tb));
    dv = max(abs(S1.Mb(1:n, 1) - S2.Mb(1:n, 1)));
    fprintf('reproducibility T2_esc vs R_esc: max|dv_ref| = %.3g\n', dv);
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
    fprintf('M0-C TRIALS PASS\n');
else
    fprintf('M0-C TRIALS FAIL (see summary above)\n');
end
fprintf('Archive: %s\n', outDir);

% ---------------------------------------------------------------------------
function r = evalRun(name, mode, center0, nominal, Mb, tb, A, ta, Pe, Ee, ...
    band, period, stopT)
%EVALRUN per-run metrics on the clean window (status in {1,2}, flag5 quiet).
    status = Mb(:, 4);
    vref = Mb(:, 1);
    v = Mb(:, 7);
    flag5 = A(:, 31);   % bus columns 27..34 = flags 1..8

    % window definitions (codex reacceptance 4.1): cost metrics accept
    % ONLY active (status 2) samples with flag5 quiet -- warm-up / reference
    % ramp (status 1) and disengaged phases never enter the cost; the
    % engaged set {1,2} is reported for safety-supervision diagnostics only
    base = tb >= 0.005;
    act = base & status == 2 & flag5 < 0.5;
    eng = base & (status == 1 | status == 2) & flag5 < 0.5;
    cleanFrac = mean(act(base));
    engFrac = mean(eng(base));
    gateEngaged = mean(eng(tb >= 5.0));

    err = abs(v - vref);
    errMean = mean(err(act));
    Pmean = mean(Pe(act));
    Eclean = trapz(tb(act), Pe(act));

    % constraint activity
    hard = any(A(:, 27:30) > 0.5, 2) | any(A(:, 32:33) > 0.5, 2);
    hardMax = max(hard(base));
    flag5Frac = mean(A(base, 31) > 0.5);
    nFrozen = sum(diff(status == 3) == 1);
    nFb = sum(diff(status == 4) == 1);

    % actuator spread on the clean window
    pwm = A(act, 11:18);
    pwmMin = min(pwm, [], 'all');
    pwmMax = max(pwm, [], 'all');

    % the band constrains the ESC request, not the selector's warm-up
    % ramp; check after the ramp to any center in the band completes (6 s)
    late = tb >= 6.0;
    bandOK = all(vref(late) >= band(1) - 0.05 & ...
        vref(late) <= band(2) + 0.05);

    % convergence (esc runs): period means of v_ref; settled when the
    % remaining period means stay inside a 0.1 m/s band
    convT = NaN;
    if strcmp(mode, 'esc')
        pLen = round(period * 1000);  % 1 ms log
        nP = floor(numel(vref) / pLen);
        m = arrayfun(@(j) mean(vref((j - 1) * pLen + 1:j * pLen)), 1:nP);
        for j = 1:nP
            if max(m(j:end)) - min(m(j:end)) <= 0.1
                convT = (j - 1) * period;
                break
            end
        end
    end

    % acceptance for this run (plan §7): no hard flags, no fallback trips
    % in nominal, band respected, engaged almost everywhere when clean
    if nominal
        runOK = hardMax == 0 && nFb == 0 && bandOK && gateEngaged >= 0.95;
    else
        runOK = bandOK;  % disturbed pair reported honestly, not gated
    end
    r = struct('name', name, 'mode', mode, 'center0', center0, ...
        'nominal', nominal, 'ok', runOK, 'cleanFrac', cleanFrac, ...
        'engFrac', engFrac, 'gateEngaged', gateEngaged, ...
        'errMean', errMean, 'Pmean', Pmean, 'Eclean', Eclean, ...
        'convT', convT, ...
        'nFrozen', nFrozen, 'nFb', nFb, 'hardMax', hardMax, ...
        'flag5Frac', flag5Frac, 'pwmMin', pwmMin, 'pwmMax', pwmMax, ...
        'bandOK', bandOK, 'vrefFinal', vref(end), 'stopT', stopT);
end

function printRun(r)
%PRINTRUN one-line human summary of a run.
    fprintf(['  act %.2f  err %.3f m/s  P %.1f W  Eclean %.0f J  ' ...
        'convT %.1f s  frozen %d  fb %d  hard %d  flag5 %.2f  ' ...
        'pwm [%.0f %.0f]  band %d  vref(end) %.3f\n'], r.cleanFrac, ...
        r.errMean, r.Pmean, r.Eclean, r.convT, r.nFrozen, r.nFb, ...
        r.hardMax, r.flag5Frac, r.pwmMin, r.pwmMax, r.bandOK, r.vrefFinal);
end

function s = ternary(c, a, b)
if c
    s = a;
else
    s = b;
end
end
