%RUN_AIR_M1_ROBUSTNESS M1 robustness scenario matrix (plan: M1_ROBUSTNESS.md).
%   27 runs around the M0-C ESC interface; every injection is wired in
%   memory and the model is reloaded from disk after every run -- zero .slx
%   changes. The degradation chain sits between 'M0A Power Measurement'
%   out 1 and its two consumers ('M0C P ZOH' in 1 = ESC P_e, 'M0A
%   Constraint Flags' in 4 = power monitor), so both see the same degraded
%   measurement while the m0a_P_est_W log stays on the REAL signal (cost /
%   regret are never polluted by measurement noise).
%
%   Groups (all center0 = 9 m/s):
%     R0      nominal repeat, no injection                 fixed + esc
%     WN1..5  2% power noise (sigma ~ 5.02 W), seeds 11-15 fixed + esc
%     DL1     0.5 s measurement delay (10 x Unit Delay)    fixed + esc
%     DL2     DL1 repeat, determinism (max|dv_ref|<1e-9)   esc
%     WD      baseline roll-sine disturbance               fixed + esc
%     CM1..3  noise + delay + wind, seeds 21-23            fixed + esc
%     F1..F4  M0-B fault injections over a 2% noise        fixed
%             background (F4 embeds noise in its source);
%             M0-B criteria verbatim + pre-window 8-bit
%             quiet (the noise must not false-trigger)
%
%   Gates (plan §7): R0/WN/DL esc arms converge inside the band with ZERO
%   safety trips; every fixed/esc pair regret = 100*(E_esc-E_fixed)/E_fixed
%   over the common continuous [20,30] s grid <= 3%; DL2 == DL1-esc sample
%   by sample; F1..F4 pass the M0-B criteria set. WD/CM are reported
%   honestly (trips, recovery) without gating, per plan §7.4.

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));

global M0C_ESC_PARAMS
% compile-probe safe: the global exists before the first update/sim
M0C_ESC_PARAMS = struct('mode', 'esc', 'center0', 9.0);

% name, group, zeroSine, noise, delay, seed, mode, stopT
plan = { ...
    'R0_fixed',     'R0', 1, 0, 0,  0, 'fixed', 30; ...
    'R0_esc',       'R0', 1, 0, 0,  0, 'esc',   30; ...
    'WN1_fixed',    'WN', 1, 1, 0, 11, 'fixed', 30; ...
    'WN1_esc',      'WN', 1, 1, 0, 11, 'esc',   30; ...
    'WN2_fixed',    'WN', 1, 1, 0, 12, 'fixed', 30; ...
    'WN2_esc',      'WN', 1, 1, 0, 12, 'esc',   30; ...
    'WN3_fixed',    'WN', 1, 1, 0, 13, 'fixed', 30; ...
    'WN3_esc',      'WN', 1, 1, 0, 13, 'esc',   30; ...
    'WN4_fixed',    'WN', 1, 1, 0, 14, 'fixed', 30; ...
    'WN4_esc',      'WN', 1, 1, 0, 14, 'esc',   30; ...
    'WN5_fixed',    'WN', 1, 1, 0, 15, 'fixed', 30; ...
    'WN5_esc',      'WN', 1, 1, 0, 15, 'esc',   30; ...
    'DL1_fixed',    'DL', 1, 0, 1,  0, 'fixed', 30; ...
    'DL1_esc',      'DL', 1, 0, 1,  0, 'esc',   30; ...
    'DL2_esc',      'DL', 1, 0, 1,  0, 'esc',   30; ...
    'WD_fixed',     'WD', 0, 0, 0,  0, 'fixed', 30; ...
    'WD_esc',       'WD', 0, 0, 0,  0, 'esc',   30; ...
    'CM1_fixed',    'CM', 0, 1, 1, 21, 'fixed', 30; ...
    'CM1_esc',      'CM', 0, 1, 1, 21, 'esc',   30; ...
    'CM2_fixed',    'CM', 0, 1, 1, 22, 'fixed', 30; ...
    'CM2_esc',      'CM', 0, 1, 1, 22, 'esc',   30; ...
    'CM3_fixed',    'CM', 0, 1, 1, 23, 'fixed', 30; ...
    'CM3_esc',      'CM', 0, 1, 1, 23, 'esc',   30; ...
    'F1_pwm_edge',  'F',  1, 1, 0, 31, 'fixed', 10; ...
    'F2_yaw_rate',  'F',  1, 1, 0, 32, 'fixed', 10; ...
    'F3_nan_power', 'F',  1, 1, 0, 33, 'fixed', 10; ...
    'F4_power_rec', 'F',  1, 0, 0, 34, 'fixed', 13};
BAND = [6.0, 12.0];
PERIOD = 4.0;               % dither period, s (0.25 Hz)
COMMON_WIN = [20.0, 30.0];  % common pair comparison window
REGRET_MAX = 3.0;           % roadmap M1 gate, %

outDir = fullfile(wsRoot, 'results', 'air_m1_robustness', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

R = struct();
F = struct();
ok = true;
for k = 1:size(plan, 1)
    name = plan{k, 1};
    group = plan{k, 2};
    zeroSine = plan{k, 3} == 1;
    wantNoise = plan{k, 4} == 1;
    wantDelay = plan{k, 5} == 1;
    seed = plan{k, 6};
    mode = plan{k, 7};
    stopT = plan{k, 8};
    fprintf('=== %s (group %s, mode %s, seed %d, noise %d, delay %d) ===\n', ...
        name, group, mode, seed, wantNoise, wantDelay);
    M0C_ESC_PARAMS = struct('mode', mode, 'center0', 9.0);
    if bdIsLoaded(model)
        close_system(model, 0);
    end
    load_system(fullfile(modelDir, [model '.slx']));
    set_param(model, 'StopTime', num2str(stopT));
    set_param([model '/M0B Speed Loop Enable'], 'Value', '1');
    set_param([model '/M0A Optimizer Enable'], 'Value', '1');
    set_param([model '/M0B v Ref Manual'], 'Value', '5');
    if zeroSine
        set_param([model '/Attitude Control/InputConditioning/Sine Wave'], ...
            'Amplitude', '0');
    end
    try
        if strcmp(group, 'F')
            % 'F1_pwm_edge' -> 'pwm_edge' etc.
            tok = regexp(name, '^[^_]+_(.+)$', 'tokens', 'once');
            faultName = tok{1};
            if wantNoise || wantDelay
                % noise background first (ESC P_e + monitor in 4), then the
                % M0-B fault rewiring on its own monitor input; F4 has the
                % noise embedded in its fault source instead (plan §2.2)
                spliceDegradation(model, wantNoise, wantDelay, seed);
            end
            applyFault(model, faultName, seed);
        elseif wantNoise || wantDelay
            spliceDegradation(model, wantNoise, wantDelay, seed);
        end

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
        % P_est logs on a 4 ms grid, E_est on the 1 ms grid; align onto the
        % 1 ms log grid (M0-C pattern). These stay on the REAL signal.
        Pts = out.get('m0a_P_est_W');
        P = double(Pts.Data(:));
        tp = Pts.Time(:);
        Ets = out.get('m0a_E_est_J');
        E = double(Ets.Data(:));
        te = Ets.Time(:);
        Pe = interp1(tp, P, ta, 'previous', P(1));
        Ee = interp1(te, E, ta, 'previous', E(1));

        if strcmp(group, 'F')
            s = evalFault(name, faultName, Mb, tb, A);
            F.(name) = s;
            printFault(s);
            save(fullfile(outDir, [name '.mat']), 's', 'Mb', 'tb', 'A', 'ta');
            if ~s.ok
                ok = false;
            end
        else
            r = evalRun(name, group, mode, Mb, tb, A, ta, Pe, Ee, ...
                BAND, PERIOD, stopT);
            R.(name) = r;
            printRun(r);
            save(fullfile(outDir, [name '.mat']), 'r', 'Mb', 'tb', 'A', ...
                'ta', 'Pe', 'Ee');
            if ~r.ok
                ok = false;
            end
        end
    catch err
        fprintf('  %s FAILED: %s\n', name, err.message);
        if strcmp(group, 'F')
            F.(name) = struct('name', name, 'ok', false);
        else
            R.(name) = struct('name', name, 'group', group, 'mode', mode, ...
                'ok', false);
        end
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
    if ~r.ok && ~isfield(r, 'cleanFrac')
        rows(end + 1, :) = {r.name, r.group, r.mode, NaN, NaN, NaN, NaN, ...
            NaN, NaN, NaN, NaN, NaN, NaN, false}; %#ok<AGROW>
        continue
    end
    rows(end + 1, :) = {r.name, r.group, r.mode, r.cleanFrac, ...
        r.errMean, r.Pmean, r.Eclean, r.convT, r.nFrozen, r.nFb, ...
        r.hardMax, r.bandOK, r.tailRefOK, r.ok}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'run', 'group', 'mode', ...
    'cleanFrac', 'errMean_mps', 'Pmean_W', 'Eclean_J', 'convT_s', ...
    'nFrozen', 'nFb', 'hardMax', 'bandOK', 'tailRefOK', 'ok'});
writetable(T, fullfile(outDir, 'summary.csv'));
disp(T);

% ---- fixed/esc pairs: regret over the common continuous grid ---------------
pairs = {'R0', 'WN1', 'WN2', 'WN3', 'WN4', 'WN5', 'DL1', 'WD', ...
    'CM1', 'CM2', 'CM3'};
prows = {};
for k = 1:numel(pairs)
    pfx = pairs{k};
    if isfield(R, [pfx '_fixed']) && isfield(R, [pfx '_esc']) && ...
            R.([pfx '_fixed']).ok && R.([pfx '_esc']).ok && ...
            isfield(R.([pfx '_fixed']), 'cleanFrac')
        Sf = load(fullfile(outDir, [pfx '_fixed.mat']), 'ta', 'Pe');
        Se = load(fullfile(outDir, [pfx '_esc.mat']), 'ta', 'Pe');
        assert(numel(Sf.ta) == numel(Se.ta) && ...
            max(abs(Sf.ta - Se.ta)) < 1e-12, ...
            'air:M1:PairTimeGridMismatch', ...
            '%s fixed/esc runs do not share the same time grid.', pfx);
        cw = Sf.ta >= COMMON_WIN(1) & Sf.ta <= COMMON_WIN(2);
        assert(nnz(cw) >= 2, 'air:M1:PairWindowEmpty', ...
            '%s common comparison window is empty.', pfx);
        Pfixed = mean(Sf.Pe(cw));
        Pesc = mean(Se.Pe(cw));
        Efixed = trapz(Sf.ta(cw), Sf.Pe(cw));
        Eesc = trapz(Se.ta(cw), Se.Pe(cw));
        regret = 100 * (Eesc - Efixed) / max(Efixed, eps);
        escOK = regret <= REGRET_MAX;
        prows(end + 1, :) = {pfx, Pfixed, Pesc, Efixed, Eesc, ...
            regret, R.([pfx '_esc']).convT, escOK}; %#ok<AGROW>
        if ~escOK
            ok = false;
        end
    end
end
if ~isempty(prows)
    T2 = cell2table(prows, 'VariableNames', {'pair', 'P_fixed_W', ...
        'P_esc_W', 'E_fixed_J', 'E_esc_J', 'regret_pct', ...
        'esc_convT_s', 'ok'});
    writetable(T2, fullfile(outDir, 'pairs_regret.csv'));
    disp(T2);
end

% ---- fault regression summary ----------------------------------------------
fns = fieldnames(F);
frows = {};
for k = 1:numel(fns)
    s = F.(fns{k});
    if isfield(s, 'fault')
        frows(end + 1, :) = {s.name, s.fault, s.bit, s.preQuiet, ...
            s.preActive, s.t_fire_s, s.t_frozen_s, s.t_fallback_s, ...
            s.fallback_ref_ok, s.recovery_ok, s.ok}; %#ok<AGROW>
    else
        frows(end + 1, :) = {s.name, 'error', NaN, NaN, NaN, NaN, NaN, ...
            NaN, NaN, NaN, false}; %#ok<AGROW>
    end
end
T3 = cell2table(frows, 'VariableNames', {'scenario', 'fault', 'bit', ...
    'preQuiet', 'preActive', 't_fire_s', 't_frozen_s', 't_fallback_s', ...
    'fbRefOK', 'recoveryOK', 'ok'});
writetable(T3, fullfile(outDir, 'faults.csv'));
disp(T3);

% ---- DL determinism ---------------------------------------------------------
detOK = false;
try
    S1 = load(fullfile(outDir, 'DL1_esc.mat'), 'Mb', 'tb');
    S2 = load(fullfile(outDir, 'DL2_esc.mat'), 'Mb', 'tb');
    n = min(numel(S1.tb), numel(S2.tb));
    dv = max(abs(S1.Mb(1:n, 1) - S2.Mb(1:n, 1)));
    fprintf('determinism DL1_esc vs DL2_esc: max|dv_ref| = %.3g\n', dv);
    detOK = dv < 1e-9;
catch err
    fprintf('determinism check could not run: %s\n', err.message);
end
if ~detOK
    ok = false;
end

result = struct('pass', ok, 'deterministic', detOK, ...
    'archiveDir', string(outDir));
save(fullfile(outDir, 'result.mat'), 'result');
if ok
    fprintf('M1 ROBUSTNESS PASS\n');
else
    fprintf('M1 ROBUSTNESS FAIL (see summary above)\n');
end
fprintf('Archive: %s\n', outDir);

% ---------------------------------------------------------------------------
function spliceDegradation(model, wantNoise, wantDelay, seed)
%SPLICEDEGRADATION wire the measurement-degradation chain between
%   'M0A Power Measurement' out 1 and its two consumers. The original
%   branches to every other destination (logs) are left untouched.
    srcPh = get_param([model '/M0A Power Measurement'], 'PortHandles');
    pOut = srcPh.Outport(1);
    % probe-verified topology (diag_m1_probe): Power Measurement out 1
    % feeds the ESC via 'M0C P ZOH' and the power monitor via
    % 'M0A P Est ZOH 1ms' -> 'M0A Constraint Flags' in 4; the
    % 'M0A Log P Est' log branches stay on the real signal
    dsts = [ ...
        get_param([model '/M0C P ZOH'], 'PortHandles').Inport(1); ...
        get_param([model '/M0A P Est ZOH 1ms'], 'PortHandles').Inport(1)];
    for k = 1:2
        l = get_param(dsts(k), 'Line');
        assert(l ~= -1, 'air:M1:ConsumerLineMissing', ...
            'M1 consumer %d has no incoming line.', k);
        sp = get_param(l, 'SrcPortHandle');
        assert(sp == pOut, 'air:M1:UnexpectedSource', ...
            ['M1 consumer %d is not fed by Power Measurement out 1; ' ...
            'check the topology with diag_m1_probe.'], k);
        delete_line(model, sp, dsts(k));
    end
    head = pOut;
    if wantDelay
        % 10 x 0.05 s Unit Delay = 0.5 s; initial condition 251 W (cruise)
        % so the first 0.5 s cannot fake a power drop into bits 6/7
        prev = pOut;
        for j = 1:10
            nm = sprintf('%s/M1 Dly %02d', model, j);
            add_block('simulink/Discrete/Unit Delay', nm, ...
                'Position', [60 + 34 * j, 1470, 84 + 34 * j, 1490], ...
                'SampleTime', '0.05', 'InitialCondition', '251');
            ph = get_param(nm, 'PortHandles');
            add_line(model, prev, ph.Inport(1), 'autorouting', 'on');
            prev = ph.Outport(1);
        end
        head = prev;
    end
    if wantNoise
        % 2% of the 251 W cruise power; seed is fixed per scenario and
        % shared by the fixed/esc pair (same noise realization)
        nz = [model '/M1 Noise'];
        sm = [model '/M1 Noise Sum'];
        add_block('simulink/Sources/Random Number', nz, ...
            'Position', [420, 1510, 470, 1540], 'Mean', '0', ...
            'Variance', '(0.02*251)^2', 'SampleTime', '0.004', ...
            'Seed', num2str(seed));
        add_block('simulink/Math Operations/Sum', sm, ...
            'Position', [510, 1470, 540, 1500], 'Inputs', '++');
        add_line(model, head, get_param(sm, 'PortHandles').Inport(1), ...
            'autorouting', 'on');
        add_line(model, get_param(nz, 'PortHandles').Outport(1), ...
            get_param(sm, 'PortHandles').Inport(2), 'autorouting', 'on');
        head = get_param(sm, 'PortHandles').Outport(1);
    end
    for k = 1:2
        add_line(model, head, dsts(k), 'autorouting', 'on');
    end
    set_param(model, 'SimulationCommand', 'update');
end

function bitIdx = applyFault(model, name, seed)
%APPLYFAULT M0-B fault injection semantics (repo @932c55d), M1 block prefix.
%   power_rec embeds the 2% noise in its own source (F4); the other three
%   run over the already-spliced noisy monitor inputs.
    fp = get_param([model '/M0A Constraint Flags'], 'PortHandles');
    switch name
        case 'pwm_edge'                       % input 1: pwm_us (bit 1)
            dst = fp.Inport(1);
            bitIdx = 1;
            src = [model '/M1 Inject PWM'];
            add_block('simulink/Sources/Step', src, ...
                'Position', [60, 1300, 90, 1330], 'Time', '6', ...
                'Before', '1500', 'After', '2000', 'SampleTime', '0.001');
        case 'yaw_rate'                       % input 2: att(6) (bit 4)
            dst = fp.Inport(2);
            bitIdx = 4;
            src = [model '/M1 Inject Att Mux'];
            add_block('simulink/Signal Routing/Mux', src, ...
                'Position', [200, 1290, 205, 1360], 'Inputs', '6');
            for kk = 1:5
                z = sprintf('%s/M1 Inject Att Z%d', model, kk);
                add_block('simulink/Sources/Constant', z, ...
                    'Position', [60, 1285 + 15 * (kk - 1), ...
                    90, 1295 + 15 * (kk - 1)], 'Value', '0');
                add_line(model, get_param(z, 'PortHandles').Outport(1), ...
                    get_param(src, 'PortHandles').Inport(kk), ...
                    'autorouting', 'on');
            end
            rStep = [model '/M1 Inject Att R'];
            add_block('simulink/Sources/Step', rStep, ...
                'Position', [60, 1370, 90, 1400], 'Time', '6', ...
                'Before', '0', 'After', '2', 'SampleTime', '0.001');
            add_line(model, get_param(rStep, 'PortHandles').Outport(1), ...
                get_param(src, 'PortHandles').Inport(6), 'autorouting', 'on');
        case 'nan_power'                      % input 2: NaN on r (bit 7)
            dst = fp.Inport(2);
            bitIdx = 7;
            src = [model '/M1 Inject Att Mux'];
            add_block('simulink/Signal Routing/Mux', src, ...
                'Position', [200, 1290, 205, 1360], 'Inputs', '6');
            for kk = 1:5
                z = sprintf('%s/M1 Inject Att Z%d', model, kk);
                add_block('simulink/Sources/Constant', z, ...
                    'Position', [60, 1285 + 15 * (kk - 1), ...
                    90, 1295 + 15 * (kk - 1)], 'Value', '0');
                add_line(model, get_param(z, 'PortHandles').Outport(1), ...
                    get_param(src, 'PortHandles').Inport(kk), ...
                    'autorouting', 'on');
            end
            ctl = [model '/M1 Inject N Ctl'];
            one = [model '/M1 Inject N One'];
            dif = [model '/M1 Inject N Diff'];
            div = [model '/M1 Inject N Div'];
            add_block('simulink/Sources/Step', ctl, ...
                'Position', [60, 1370, 90, 1400], 'Time', '6', ...
                'Before', '0', 'After', '1', 'SampleTime', '0.001');
            add_block('simulink/Sources/Constant', one, ...
                'Position', [60, 1410, 90, 1440], 'Value', '1');
            add_block('simulink/Math Operations/Sum', dif, ...
                'Position', [160, 1370, 190, 1400], 'Inputs', '+-');
            add_block('simulink/Math Operations/Divide', div, ...
                'Position', [240, 1370, 270, 1400], 'Inputs', '*/');
            add_line(model, get_param(ctl, 'PortHandles').Outport(1), ...
                get_param(dif, 'PortHandles').Inport(1), 'autorouting', 'on');
            add_line(model, get_param(one, 'PortHandles').Outport(1), ...
                get_param(dif, 'PortHandles').Inport(2), 'autorouting', 'on');
            difOut = get_param(dif, 'PortHandles').Outport(1);
            add_line(model, difOut, ...
                get_param(div, 'PortHandles').Inport(1), 'autorouting', 'on');
            add_line(model, difOut, ...
                get_param(div, 'PortHandles').Inport(2), 'autorouting', 'on');
            add_line(model, get_param(div, 'PortHandles').Outport(1), ...
                get_param(src, 'PortHandles').Inport(6), 'autorouting', 'on');
        case 'power_rec'                      % input 4: P pulse + noise
            dst = fp.Inport(4);
            bitIdx = 6;
            base = [model '/M1 Inject P Base'];
            s1 = [model '/M1 Inject P Up'];
            s2 = [model '/M1 Inject P Down'];
            nz = [model '/M1 Inject P Noise'];
            sumB = [model '/M1 Inject P Sum'];
            add_block('simulink/Sources/Constant', base, ...
                'Position', [60, 1290, 90, 1320], 'Value', '251');
            add_block('simulink/Sources/Step', s1, ...
                'Position', [60, 1330, 90, 1360], 'Time', '6', ...
                'Before', '0', 'After', '1349', 'SampleTime', '0.001');
            add_block('simulink/Sources/Step', s2, ...
                'Position', [60, 1370, 90, 1400], 'Time', '7.5', ...
                'Before', '0', 'After', '-1349', 'SampleTime', '0.001');
            add_block('simulink/Sources/Random Number', nz, ...
                'Position', [60, 1410, 110, 1440], 'Mean', '0', ...
                'Variance', '(0.02*251)^2', 'SampleTime', '0.004', ...
                'Seed', num2str(seed));
            add_block('simulink/Math Operations/Sum', sumB, ...
                'Position', [160, 1310, 190, 1430], 'Inputs', '++++');
            srcHandles = {base, s1, s2, nz};
            for kk = 1:4
                add_line(model, ...
                    get_param(srcHandles{kk}, 'PortHandles').Outport(1), ...
                    get_param(sumB, 'PortHandles').Inport(kk), ...
                    'autorouting', 'on');
            end
            src = sumB;
        otherwise
            error('air:M1:UnknownFault', 'unknown fault %s', name);
    end
    l = get_param(dst, 'Line');
    assert(l ~= -1, 'air:M1:MonitorInputDangling', ...
        'flags input has no line before fault injection.');
    realSrc = get_param(l, 'SrcPortHandle');
    delete_line(model, realSrc, dst);
    add_line(model, get_param(src, 'PortHandles').Outport(1), dst, ...
        'autorouting', 'on');
    set_param(model, 'SimulationCommand', 'update');
end

function r = evalRun(name, group, mode, Mb, tb, A, ta, Pe, Ee, ...
    band, period, stopT)
%EVALRUN per-run metrics; cost metrics on active+quiet samples (M0-C rule),
%   energy statistics on the real (unpolluted) power log.
    status = Mb(:, 4);
    vref = Mb(:, 1);
    v = Mb(:, 7);
    flag5 = A(:, 31);   % bus columns 27..34 = flags 1..8

    base = tb >= 0.005;
    act = base & status == 2 & flag5 < 0.5;
    cleanFrac = mean(act(base));

    err = abs(v - vref);
    errMean = mean(err(act));
    Pmean = mean(Pe(act));
    Eclean = trapz(tb(act), Pe(act));

    hard = any(A(:, 27:30) > 0.5, 2) | any(A(:, 32:33) > 0.5, 2);
    hardMax = max(hard(base));
    flag5Frac = mean(A(base, 31) > 0.5);
    nFrozen = sum(diff(status == 3) == 1);
    nFb = sum(diff(status == 4) == 1);

    pwm = A(act, 11:18);
    pwmMin = min(pwm, [], 'all');
    pwmMax = max(pwm, [], 'all');

    late = tb >= 6.0;
    bandOK = all(vref(late) >= band(1) - 0.05 & ...
        vref(late) <= band(2) + 0.05);
    tailRefOK = ~isempty(vref(tb >= 25)) && ...
        all(abs(vref(tb >= 25) - 9.0) <= 0.51);
    zeroTrips = hardMax == 0 && nFrozen == 0 && nFb == 0;

    % convergence: period means of v_ref settle inside 0.1 m/s (M0-C rule)
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

    % gates (plan §3/§7): A+B sets gate R0/WN/DL; WD/CM report honestly
    switch group
        case {'R0', 'WN', 'DL'}
            if strcmp(mode, 'esc')
                runOK = isfinite(convT) && bandOK && zeroTrips;
            else
                runOK = bandOK && zeroTrips;
            end
        otherwise                   % 'WD', 'CM'
            runOK = true;
    end
    r = struct('name', name, 'group', group, 'mode', mode, 'ok', runOK, ...
        'cleanFrac', cleanFrac, 'errMean', errMean, 'Pmean', Pmean, ...
        'Eclean', Eclean, 'convT', convT, 'nFrozen', nFrozen, ...
        'nFb', nFb, 'hardMax', hardMax, 'flag5Frac', flag5Frac, ...
        'pwmMin', pwmMin, 'pwmMax', pwmMax, 'bandOK', bandOK, ...
        'tailRefOK', tailRefOK, 'zeroTrips', zeroTrips, ...
        'vrefFinal', vref(end), 'stopT', stopT);
end

function printRun(r)
%PRINTRUN one-line human summary of a robustness run.
    fprintf(['  act %.2f  err %.3f m/s  P %.1f W  Eclean %.0f J  ' ...
        'convT %.1f s  frozen %d  fb %d  hard %d  flag5 %.2f  ' ...
        'pwm [%.0f %.0f]  band %d  tail9 %d  vref(end) %.3f\n'], ...
        r.cleanFrac, r.errMean, r.Pmean, r.Eclean, r.convT, ...
        r.nFrozen, r.nFb, r.hardMax, r.flag5Frac, r.pwmMin, r.pwmMax, ...
        r.bandOK, r.tailRefOK, r.vrefFinal);
end

function s = evalFault(name, faultName, Mb, tb, A)
%EVALFAULT M0-B criteria verbatim (repo @932c55d) plus the M1 hardening:
%   the whole pre-fault window must have all 8 flags quiet (2% noise must
%   not false-trigger anything).
    bitMap = containers.Map({'pwm_edge', 'yaw_rate', 'nan_power', ...
        'power_rec'}, {1, 4, 7, 6});
    bitIdx = bitMap(faultName);
    status = Mb(:, 4);
    vref = Mb(:, 1);
    bitDown = A(:, 26 + bitIdx);

    pre = tb >= 5.0 & tb < 6.0;
    preBits = A(pre, 27:34);
    c0 = all(preBits(:) < 0.5);             % M1: noise background quiet
    c1 = all(status(pre) == 2) && ...
        all(abs(vref(pre) - 9.0) < 0.01) && all(bitDown(pre) < 0.5);
    inj = tb >= 6.0;
    firstFire = find(inj & bitDown > 0.5, 1, 'first');
    if isempty(firstFire)
        tFire = inf;
    else
        tFire = tb(firstFire) - 6.0;
    end
    c2 = tFire <= 0.05;
    firstFrozen = find(inj & status == 3, 1, 'first');
    if isempty(firstFrozen)
        tFrozen = inf;
    else
        tFrozen = tb(firstFrozen) - 6.0;
    end
    c3 = tFrozen <= 0.10;
    firstFb = find(inj & status == 4, 1, 'first');
    if isempty(firstFb)
        tFb = inf;
    else
        tFb = tb(firstFb) - 6.0;
    end
    c4 = tFb <= 1.0;
    fb = status == 4;
    fbIdx = find(fb);
    c5 = ~any(fb) || (all(vref(fb) <= 9.0 + 0.01) && ...
        vref(fbIdx(end)) <= 5.0 + 0.51);
    c6 = true;
    if strcmp(faultName, 'power_rec')
        reEngaged = any(tb >= 9.1 & (status == 1 | status == 2));
        leftManual = vref(end) >= 6.5;
        c6 = reEngaged && leftManual;
    end
    thisPass = c0 && c1 && c2 && c3 && c4 && c5 && c6;
    s = struct('name', name, 'fault', faultName, 'bit', bitIdx, ...
        'preQuiet', c0, 'preActive', c1, 't_fire_s', tFire, ...
        't_frozen_s', tFrozen, 't_fallback_s', tFb, ...
        'fallback_ref_ok', c5, 'recovery_ok', c6, 'ok', thisPass);
end

function printFault(s)
%PRINTFAULT one-line human summary of a fault regression run.
    fprintf(['  preQuiet %d  preActive %d  bitFire %.3f s  frozen %.3f s  ' ...
        'fallback %.3f s  fbRef %d  recovery %d\n'], s.preQuiet, ...
        s.preActive, s.t_fire_s, s.t_frozen_s, s.t_fallback_s, ...
        s.fallback_ref_ok, s.recovery_ok);
end