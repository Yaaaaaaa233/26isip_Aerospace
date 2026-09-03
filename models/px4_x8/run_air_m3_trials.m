function result = run_air_m3_trials(injectError, scenarioSet, baseDir)
%RUN_AIR_M3_TRIALS M3 paired coordination trials (M3_V_ETA_COORDINATION.md
%   section 5, pre-registered). 13-scenario row-frozen pairing matrix:
%   M3 nominal 5 ({7,11} x {0.8,1.2} + (9,1.0)), disturbed 2,
%   reproducibility 1, and the B0/B1/B2 baselines (7 rows). Same model,
%   same wiring; the only difference between arms is the global config.
%   Duration 240 s; primary gate = the cycle-common energy window
%   [144,240] s (exactly one full eta 64 + v 32 cycle); eta convergence
%   end-window [200,240] s; [20,30] s continuity reported only.
%   Per-arm records (M3 doc section 5): delta-E% vs B0 on the common grid,
%   tracking by nearest-variable pairing, the execution-evidence table
%   (reconstructed plan vs the archived eta candidate / applied v, per
%   hold-run constancy, per-window invalid itemization), and the standard
%   safety supervision numbers. Everything model-estimated (P_est, no
%   calibration).
%
%   FUNCTION ENTRY per ACCEPTANCE_AUTOMATION_RULES.md 2.1/3.1: returns a
%   machine-checkable result; the four globals are snapshotted and
%   restored on exit (success and error paths). injectError = 'trials'
%   short-circuits with pass = false after the entry contract is set up.
%   scenarioSet: 'full' (default) = all 13 rows; any subset of row IDs,
%   e.g. {'M3-N1'} or {'B0-N','M3-N5'}, for the segmented execution the
%   R2022b heap limitation requires (M2 'keep' filter precedent).

if nargin < 1
    injectError = '';
end
if nargin < 2
    scenarioSet = 'full';
end
if nargin < 3
    baseDir = '';   % archive of a previous segment: baseline arms are
end                 % loaded from there for the cross-segment paired gates

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));

global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
snap = snapshotGlobals();
cleanup = onCleanup(@() m3tr_restore(snap)); %#ok<NASGU>

% ---- M3 model set: every field of both channels explicit (M3 doc 2.5;
% eta gain 1e-4 = M2 model set, duty-cycle recheck confirmed no change)
arb = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 64.0, 'slotV', 32.0);
pvBase = struct('mode', 'm3', 'center0', 9.0, 'lower', 6.0, 'upper', 12.0, ...
    'amplitude', 0.3, 'frequency', 0.25, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 6e-3, 'rateLimit', 2.0);
peBase = struct('mode', 'm3', 'center0', 1.0, 'lower', 0.75, 'upper', 1.25, ...
    'amplitude', 0.02, 'frequency', 0.25, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 2e-4, 'rateLimit', 0.05);
m3_validate_channels(pvBase.mode, peBase.mode, arb);

% ---- pairing matrix (row-frozen, M3 doc section 5) ----------------------
%   {id, nominal, modeV, modeEta, v0, eta0, stopT}
plan = { ...
    'M3-N1', 1, 'm3', 'm3',  7.0, 0.8, 240.0; ...
    'M3-N2', 1, 'm3', 'm3',  7.0, 1.2, 240.0; ...
    'M3-N3', 1, 'm3', 'm3', 11.0, 0.8, 240.0; ...
    'M3-N4', 1, 'm3', 'm3', 11.0, 1.2, 240.0; ...
    'M3-N5', 1, 'm3', 'm3',  9.0, 1.0, 240.0; ...
    'M3-D1', 0, 'm3', 'm3',  9.0, 0.8, 240.0; ...
    'M3-D2', 0, 'm3', 'm3', 11.0, 1.0, 240.0; ...
    'M3-R1', 1, 'm3', 'm3',  9.0, 1.0, 240.0; ...
    'B0-N',  1, 'fixed', 'fixed', 9.0, 1.0, 240.0; ...
    'B0-D',  0, 'fixed', 'fixed', 9.0, 1.0, 240.0; ...
    'B1-N1', 1, 'esc', 'fixed',  7.0, 1.0, 240.0; ...
    'B1-N2', 1, 'esc', 'fixed', 11.0, 1.0, 240.0; ...
    'B2-N1', 1, 'fixed', 'esc',  9.0, 0.8, 240.0; ...
    'B2-N2', 1, 'fixed', 'esc',  9.0, 1.2, 240.0};
if iscell(scenarioSet)
    keep = scenarioSet;
    plan = plan(ismember(plan(:, 1), keep), :);
    assert(~isempty(plan), 'air:M3Trials:EmptySet', ...
        'no requested scenario IDs matched the frozen matrix');
elseif ~strcmp(scenarioSet, 'full')
    error('air:M3Trials:BadScenarioSet', ...
        'scenarioSet must be ''full'' or a cell of row IDs');
end

% controlled-failure hook: fires after the entry contract exists
if strcmp(injectError, 'trials')
    result = struct('pass', false, 'archiveDir', "injected");
    fprintf('run_air_m3_trials: injected controlled failure (pass=false)\n');
    return;
end

GATE_WIN = [144.0, 240.0];    % cycle-common energy window (primary)
CONV_WIN = [200.0, 240.0];   % eta convergence end-window
CONT_WIN = [20.0, 30.0];     % continuity window (reported only)
NOTWORSE = 0.5;              % dE% gate vs B1/B2 (M2 precedent)
VTRK_TOL = 0.05;             % v tracking tolerance vs the paired B1 arm
ETA_CONV_TOL = 0.01;         % |period mean - 1.0| on the last search slot
ETA_MONO_TOL = 5e-3;         % adjacent period-end regression tolerance

outDir = fullfile(wsRoot, 'results', 'air_m3_trials', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
% archive the complete effective config of every arm before any sim runs
% (machine-checkable provenance, M3 doc 2.5: no ambient inheritance)
cfgAll = struct();
for k = 1:size(plan, 1)
    id = plan{k, 1};
    % dynamic field names accept dashes; struct() name/value pairs do not
    cfgAll.(fieldOf(id)) = struct('pv', channelCfg(pvBase, plan{k, 3}, plan{k, 5}), ...
        'pe', channelCfg(peBase, plan{k, 4}, plan{k, 6}), 'arb', arb, ...
        'row', {plan(k, :)});
end
save(fullfile(outDir, 'effective_config.mat'), 'cfgAll');

R = struct();
ok = true;
for k = 1:size(plan, 1)
    id = plan{k, 1};
    nominal = plan{k, 2} == 1;
    modeV = plan{k, 3};
    modeEta = plan{k, 4};
    v0 = plan{k, 5};
    eta0 = plan{k, 6};
    stopT = plan{k, 7};
    fprintf('=== %s (v %s %.1f / eta %s %.2f, %s, %.0f s) ===\n', id, ...
        modeV, v0, modeEta, eta0, nominal * 1 + ~nominal * 0, stopT);
    M0C_ESC_PARAMS = channelCfg(pvBase, modeV, v0);
    M2_ETA_PARAMS = channelCfg(peBase, modeEta, eta0);
    if strcmp(modeV, 'm3') || strcmp(modeEta, 'm3')
        M3_ARB_PARAMS = arb;
    else
        M3_ARB_PARAMS = [];
    end
    M2_ETA_APPLIED = eta0;
    if bdIsLoaded(model)
        close_system(model, 0);
    end
    load_system(fullfile(modelDir, [model '.slx']));
    set_param(model, 'StopTime', num2str(stopT));
    set_param([model '/M0B Speed Loop Enable'], 'Value', '1');
    set_param([model '/M0A Optimizer Enable'], 'Value', '1');
    set_param([model '/M0B v Ref Manual'], 'Value', '5');
    if nominal
        set_param([model '/Attitude Control/InputConditioning/Sine Wave'], ...
            'Amplitude', '0');
    end
    try
        out = sim(model);
        [r, logs] = extractLogs(out);
        r = evalArm(id, nominal, modeV, modeEta, v0, eta0, arb, r, logs, ...
            GATE_WIN, CONV_WIN, CONT_WIN, stopT);
        r.logs = logs;   % embedded: in-session pairing + cross-segment loads
        R.(fieldOf(id)) = r;
        printArm(r);
        save(fullfile(outDir, [id '.mat']), 'r');
        if ~r.ok
            ok = false;
        end
    catch err
        fprintf('  %s FAILED: %s\n', id, err.message);
        R.(fieldOf(id)) = struct('id', id, 'ok', false, 'error', err.message);
        ok = false;
    end
    if bdIsLoaded(model)
        close_system(model, 0);
    end
end

% ---- paired evaluation (M3 doc sections 5/6) -----------------------------
% cross-segment support: an arm not simulated in this invocation is loaded
% from the baseDir archive (M3 doc 5: the 13-scenario matrix runs segmented
% against the R2022b heap limitation; pairing must not depend on which
% segment a baseline happened to run in)
pair = struct();
GB = struct();   % loaded arms cache
if isfield(R, fieldOf('B0-N'))
    B0N = R.(fieldOf('B0-N'));
elseif ~isempty(baseDir)
    B0N = loadArm(baseDir, GB, 'B0-N');
else
    B0N = [];
end
if ~isempty(B0N)
    % energy: every nominal M3 arm against B0-N on the cycle-common window
    for a = {'M3-N1', 'M3-N2', 'M3-N3', 'M3-N4', 'M3-N5'}
        id = a{1};
        if ~isfield(R, fieldOf(id)) || ~R.(fieldOf(id)).ok
            continue;
        end
        e = m3_eval_energy(R.(fieldOf(id)).logs.ta, R.(fieldOf(id)).logs.Pe, ...
            R.(fieldOf(id)).validCostMs, B0N.logs.ta, B0N.logs.Pe, ...
            B0N.validCostMs, GATE_WIN, NOTWORSE);
        pair.(fieldOf(sprintf('%s_dB0', id))) = e;
        fprintf('%s vs B0-N: dE[144,240] = %+.5f%% (gate %.1f%%)\n', ...
            id, e.dEPct, NOTWORSE);
    end
    B0D = getArmLocal(R, baseDir, 'B0-D');
    if isfield(R, fieldOf('M3-D1')) && R.(fieldOf('M3-D1')).ok && ~isempty(B0D) && B0D.ok
        e = m3_eval_energy(R.(fieldOf('M3-D1')).logs.ta, R.(fieldOf('M3-D1')).logs.Pe, ...
            R.(fieldOf('M3-D1')).validCostMs, B0D.logs.ta, B0D.logs.Pe, ...
            B0D.validCostMs, GATE_WIN, Inf);
        pair.M3D1_dB0 = e;
        fprintf('M3-D1 vs B0-D: dE[144,240] = %+.5f%% (disturbed, reported)\n', ...
            e.dEPct);
    end
    % §6.2 not-worse gates: each nominal M3 arm against its nearest-variable
    % paired B1 arm (same v0) AND B2 arm (same eta0); M3-N5 (9, 1.0) is the
    % grid-center/R-origin cell and has no same-initial pair by design
    gateMap = {'M3-N1', 'B1-N1', 'B2-N1'; ...
        'M3-N2', 'B1-N1', 'B2-N2'; ...
        'M3-N3', 'B1-N2', 'B2-N1'; ...
        'M3-N4', 'B1-N2', 'B2-N2'};
    for k = 1:size(gateMap, 1)
        a = gateMap{k, 1};
        if ~isfield(R, fieldOf(a)) || ~R.(fieldOf(a)).ok
            continue;
        end
        for jj = 1:2
            b = gateMap{k, 1 + jj};   % brace-index: for-over-cell yields columns
            bb = getArmLocal(R, baseDir, b);
            if isempty(bb) || ~bb.ok
                ok = false;
                fprintf('  %s missing its paired %s arm\n', a, b);
                continue;
            end
            e = m3_eval_energy(R.(fieldOf(a)).logs.ta, R.(fieldOf(a)).logs.Pe, ...
                R.(fieldOf(a)).validCostMs, bb.logs.ta, bb.logs.Pe, ...
                bb.validCostMs, GATE_WIN, NOTWORSE);
            pair.(fieldOf(sprintf('%s_d%s', a, b))) = e;
            fprintf('%s vs %s: dE[144,240] = %+.5f%% (gate %.1f%%)\n', ...
                a, b, e.dEPct, NOTWORSE);
            if ~e.pass
                ok = false;
                fprintf('  %s NOT-WORSE-THAN-BASELINE gate failed vs %s\n', a, b);
            end
        end
    end
    % convergence reporting (eta arms use the frozen evaluator)
    for id = {'M3-N1', 'M3-N2', 'M3-N5', 'M3-D1'}
        a = id{1};
        if isfield(R, fieldOf(a)) && R.(fieldOf(a)).ok && ~isempty(R.(fieldOf(a)).etaConv)
            pair.(fieldOf(sprintf('%s_conv', a))) = R.(fieldOf(a)).etaConv;
            if R.(fieldOf(a)).nominal && ~R.(fieldOf(a)).etaConv.converged
                ok = false;
            end
        end
    end
    % v tracking: nearest-variable pairing (same v0 only)
    vPairs = {'M3-N1', 'B1-N1'; 'M3-N3', 'B1-N2'};
    for k = 1:size(vPairs, 1)
        a = vPairs{k, 1}; b = vPairs{k, 2};
        bb = getArmLocal(R, baseDir, b);
        if isfield(R, fieldOf(a)) && R.(fieldOf(a)).ok && ~isempty(bb) && bb.ok
            dv = R.(fieldOf(a)).vTrk - bb.vTrk;
            pair.(fieldOf(sprintf('%s_vTrk', a))) = struct('m3', R.(fieldOf(a)).vTrk, ...
                'b1', bb.vTrk, 'delta', dv, 'pass', dv <= VTRK_TOL);
            fprintf('%s vs %s: mean|v-vref| %.5f vs %.5f (tol +%.2f)\n', ...
                a, b, R.(fieldOf(a)).vTrk, bb.vTrk, VTRK_TOL);
            if dv > VTRK_TOL
                ok = false;
            end
        elseif isfield(R, fieldOf(a))
            ok = false;
        end
    end
    % reproducibility: same session, same process, sample-exact -- the R1
    % and N5 arms must be in the SAME invocation by design
    if isfield(R, fieldOf('M3-N5')) && isfield(R, fieldOf('M3-R1')) && ...
            R.(fieldOf('M3-N5')).ok && R.(fieldOf('M3-R1')).ok
        n = min(size(R.(fieldOf('M3-N5')).logs.el, 1), size(R.(fieldOf('M3-R1')).logs.el, 1));
        dv = max(abs(R.(fieldOf('M3-N5')).logs.el(1:n, 1) - R.(fieldOf('M3-R1')).logs.el(1:n, 1)));
        n2 = min(size(R.(fieldOf('M3-N5')).logs.Mb, 1), size(R.(fieldOf('M3-R1')).logs.Mb, 1));
        dv2 = max(abs(R.(fieldOf('M3-N5')).logs.Mb(1:n2, 1) - R.(fieldOf('M3-R1')).logs.Mb(1:n2, 1)));
        pair.repro = struct('maxDEtaRef', dv, 'maxDVref', dv2, ...
            'pass', max(dv, dv2) < 1e-9);
        fprintf('M3-R1 vs M3-N5: max|d eta_ref| = %.3g, max|d v_ref| = %.3g\n', ...
            dv, dv2);
        if max(dv, dv2) >= 1e-9
            ok = false;
        end
    end
else
    ok = false;
    fprintf('no B0-N baseline available (this segment or baseDir): paired gates not run\n');
end

result = struct('pass', ok, 'archiveDir', string(outDir), 'runs', R, ...
    'pair', pair);
save(fullfile(outDir, 'result.mat'), 'result');
if ok
    fprintf('M3 TRIALS PASS\n');
else
    fprintf('M3 TRIALS FAIL (see above)\n');
end
fprintf('Archive: %s\n', outDir);
end

% ---------------------------------------------------------------------------
function c = channelCfg(base, mode, center0)
%CHANNELCFG copy of the base config with mode/center0 replaced; every
%   other field stays at the frozen M3 model set value.
c = base;
c.mode = mode;
c.center0 = center0;
end

function [r, logs] = extractLogs(out)
%EXTRACTLOGS pull the archived buses off the simulation output.
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
Lg = out.get('m2_eta_log');
el = double(squeeze(Lg.Data));
if size(el, 2) ~= 4
    el = el';
end
te2 = Lg.Time(:);
Pe = interp1(tp, P, ta, 'previous', P(1));
PeE = interp1(ta, Pe, te2, 'previous', Pe(1));
logs = struct('Mb', Mb, 'tb', tb, 'A', A, 'ta', ta, 'Pe', Pe, ...
    'PeE', PeE, 'el', el, 'te2', te2);
r = struct();
end

function r = evalArm(id, nominal, modeV, modeEta, v0, eta0, arb, r, logs, ...
    gateWin, convWin, contWin, stopT)
%EVALARM per-arm metrics and the execution-evidence table.
Mb = logs.Mb; tb = logs.tb; A = logs.A; ta = logs.ta; Pe = logs.PeE;
el = logs.el; te2 = logs.te2;
nE = numel(te2);

% plan (expectation only) and per-sample validity reconstruction (M3 doc
% 2.3: the valid set is rebuilt from the ARCHIVED inputs)
searchE = false(nE, 1); searchV = false(nE, 1);
for k = 1:nE
    ro = m3_schedule(te2(k), arb);
    searchE(k) = strcmp(ro.eta, 'search');
    searchV(k) = strcmp(ro.v, 'search');
end
status = interp1(tb, Mb(:, 4), te2, 'previous', 0);
vrefApplied = interp1(tb, Mb(:, 1), te2, 'previous', 0);
vMeas = interp1(tb, Mb(:, 7), te2, 'previous', 0);
hardE = any(A(:, 27:30) > 0.5, 2) | any(A(:, 32:33) > 0.5, 2);
hardEi = interp1(ta, double(hardE), te2, 'previous', 0) > 0.5;
etaCand = el(:, 1);
etaAct = el(:, 2);
sat = el(:, 3) > 0.5;

validE = ~hardEi & ~sat & etaAct > 0 & isfinite(Pe);
validV = ~hardEi & isfinite(Pe) & vMeas >= 6.0 & vMeas <= 12.0;
% online learning participation: valid AND in a search slot (the hold
% branch never calls the kernel whatever the inputs, M3 doc 2.1)
learnE = validE & searchE;
learnV = validV & searchV;

% offline cost mask (M0-C/M2 caliber: status==2, flag5 quiet, sat quiet --
% deliberately separate from the online gates, M3 doc 2.3)
flag5i = interp1(ta, A(:, 31), te2, 'previous', 0) > 0.5;
costMask = status == 2 & ~flag5i & ~sat & te2 >= 0.005;
r.validCost = costMask;
% same mask mapped onto the 1 ms bus grid (previous-fill) for the energy
% pairing, which integrates on the continuous 1 ms grid (M3 doc 5)
r.validCostMs = interp1(te2, double(costMask), ta, 'previous', 0) > 0.5;

% ---- execution-evidence table (per M3 doc 5): plan vs archived signals
r.exe = struct();
r.exe.etaHoldConst = true;
r.exe.etaHoldDev = 0.0;
r.exe.etaHoldSamples = 0;
r.exe.vHoldDev = 0.0;
r.exe.vHoldSamples = 0;
r.exe.planExclusive = ~any(searchV & searchE);
r.exe.nSwitch = sum(diff(searchV) ~= 0);
if strcmp(modeEta, 'm3')
    runs = maskWindowsLocal(~searchE);
    for j = 1:size(runs, 1)
        seg = etaCand(runs(j, 1):runs(j, 2));
        r.exe.etaHoldDev = max(r.exe.etaHoldDev, max(abs(seg - seg(1))));
        r.exe.etaHoldSamples = r.exe.etaHoldSamples + numel(seg);
        if max(abs(seg - seg(1))) > 1e-12
            r.exe.etaHoldConst = false;
        end
    end
end
if strcmp(modeV, 'm3')
    runs = maskWindowsLocal(searchE);   % v holds while eta searches
    for j = 1:size(runs, 1)
        i0 = runs(j, 1); i1 = runs(j, 2);
        sel = (i0:i1)';
        sel = sel(te2(sel) >= te2(i0) + 0.3 & status(sel) == 2 & ...
            ~hardEi(sel));
        if numel(sel) >= 2
            r.exe.vHoldDev = max(r.exe.vHoldDev, ...
                max(abs(vrefApplied(sel) - vrefApplied(sel(1)))));
            r.exe.vHoldSamples = r.exe.vHoldSamples + numel(sel);
        end
    end
end
% invalid windows itemized per cause, per channel, with role annotation
r.exe.etaInvalid = windowTable(maskWindowsLocal(~validE & searchE), ...
    te2, hardEi, sat, etaAct > 0, isfinite(Pe));
r.exe.vInvalid = windowTable(maskWindowsLocal(~validV & searchV), ...
    te2, hardEi, false(size(te2)), ...
    vMeas >= 6.0 & vMeas <= 12.0, isfinite(Pe));

% ---- tracking / safety / energy bookkeeping on the cost mask
cMask = costMask;
r.vTrk = mean(abs(vMeas(cMask) - vrefApplied(cMask)));
r.satFrac = mean(sat(te2 >= 0.05));
r.yawMax = max(abs(interp1(ta, A(:, 10), te2, 'previous', 0)));
% map the 0.05 s cost mask onto the 1 ms bus rows (previous-fill)
maskMs = interp1(te2, double(costMask), ta, 'previous', 0) > 0.5;
r.pwmMin = min(A(maskMs, 11:18), [], 'all');
r.pwmMax = max(A(maskMs, 11:18), [], 'all');
hardBase = te2 >= 0.05;
r.hardMax = max(double(hardEi(hardBase)));
r.nFb = sum(diff(interp1(tb, Mb(:, 4), tb, 'previous', 0) == 4) == 1);
r.etaBandOK = all(etaCand(te2 >= 10.0) >= 0.73 & etaCand(te2 >= 10.0) <= 1.27);
r.vBandOK = all(vrefApplied(te2 >= 10.0) >= 5.95 & vrefApplied(te2 >= 10.0) <= 12.05);

% ---- eta convergence (m3 arms): center via candidate minus dither is not
% archived in V1; use the period means of the CANDIDATE on the last full
% search slot (dither is zero-mean over full 4 s periods -- the slot is a
% contiguous search run, so period means equal the center means)
r.etaCenter = [];
r.etaConv = [];
if strcmp(modeEta, 'm3')
    sel = te2 >= convWin(1) & te2 <= convWin(2);
    c = etaCand(sel);
    tt = te2(sel);
    pLen = round(4.0 / 0.05);
    nP = floor(numel(c) / pLen);
    assert(nP >= 2, 'air:M3Trials:ConvWindow', ...
        'convergence window has < 2 dither periods');
    pm = arrayfun(@(j) mean(c((j - 1) * pLen + 1:j * pLen)), 1:nP);
    r.etaConv = struct('periodMeans', pm, 'finalMean', mean(pm), ...
        'converged', abs(mean(pm) - 1.0) <= 0.01, ...
        'monotonic', all(diff(abs(pm - 1.0)) <= 5e-3));
    r.etaCenter = mean(pm);
end

% ---- hard gates per arm (safety + execution evidence)
r.ok = r.exe.planExclusive && r.etaBandOK && r.vBandOK && r.nFb == 0 && ...
    r.yawMax <= 1.5;
if nominal
    r.ok = r.ok && r.hardMax == 0 && r.satFrac == 0;
end
if strcmp(modeEta, 'm3')
    r.ok = r.ok && r.exe.etaHoldConst;
end
if strcmp(modeV, 'm3')
    r.ok = r.ok && r.exe.vHoldDev < 1e-9;
end
if strcmp(modeEta, 'm3') && nominal
    r.ok = r.ok && r.etaConv.converged;
end
r = structwithfields(r, 'id', id, 'nominal', nominal, 'modeV', modeV, ...
    'modeEta', modeEta, 'v0', v0, 'eta0', eta0, 'stopT', stopT);
end

function a = getArmLocal(R, baseDir, id)
%GETARMLOCAL an arm from this invocation's results, or from the baseDir
%   archive of a previous segment (cross-segment paired gates).
if isfield(R, fieldOf(id))
    a = R.(fieldOf(id));
    return;
end
a = loadArm(baseDir, struct(), id);
end

function fn = fieldOf(id)
%FIELDOF struct-field-safe name for a scenario ID (dashes are not valid in
%   dynamic field names; display IDs and archive file names keep them).
fn = strrep(id, '-', '_');
end

function a = loadArm(baseDir, ~, id)
%LOADARM read a previously archived arm (r only; the logs travel with it).
if isempty(baseDir)
    a = [];
    return;
end
f = fullfile(baseDir, [id '.mat']);
if exist(f, 'file')
    S = load(f, 'r');
    a = S.r;
else
    a = [];
end
end

function tbl = windowTable(win, t, hard, sat, inBand, finP)
n = size(win, 1);
tbl = struct('tStart', {}, 'tEnd', {}, 'causes', {});
for j = 1:n
    i0 = win(j, 1); i1 = win(j, 2);
    causes = {};
    if any(hard(i0:i1)), causes{end + 1} = 'hard'; end %#ok<AGROW>
    if any(sat(i0:i1)), causes{end + 1} = 'sat'; end %#ok<AGROW>
    if any(~inBand(i0:i1)), causes{end + 1} = 'outOfBand'; end %#ok<AGROW>
    if any(~finP(i0:i1)), causes{end + 1} = 'nonFiniteP'; end %#ok<AGROW>
    if isempty(causes), causes = {'other'}; end
    tbl(end + 1) = struct('tStart', t(i0), 'tEnd', t(i1), ...
        'causes', {causes}); %#ok<AGROW>
end
end

function runs = maskWindowsLocal(mask)
padded = [false; mask(:); false];
d = diff(padded);
runs = [find(d == 1), find(d == -1) - 1];
if isempty(runs)
    runs = zeros(0, 2);
end
end

function printArm(r)
fprintf(['  ok %d | hold: eta dev %.3g (%d), v dev %.3g (%d) | ' ...
    'vTrk %.5f sat %.3f yaw %.3f pwm [%.0f %.0f] hard %d fb %d\n'], ...
    r.ok, r.exe.etaHoldDev, r.exe.etaHoldSamples, r.exe.vHoldDev, ...
    r.exe.vHoldSamples, r.vTrk, r.satFrac, r.yawMax, r.pwmMin, ...
    r.pwmMax, r.hardMax, r.nFb);
if ~isempty(r.etaConv)
    fprintf('  eta conv: last-slot mean %.5f (converged %d, monotonic %d)\n', ...
        r.etaCenter, r.etaConv.converged, r.etaConv.monotonic);
end
for j = 1:numel(r.exe.etaInvalid)
    w = r.exe.etaInvalid(j);
    fprintf('    eta invalid-during-search [%.2f, %.2f]: %s\n', ...
        w.tStart, w.tEnd, strjoin(w.causes, '+'));
end
for j = 1:numel(r.exe.vInvalid)
    w = r.exe.vInvalid(j);
    fprintf('    v invalid-during-search [%.2f, %.2f]: %s\n', ...
        w.tStart, w.tEnd, strjoin(w.causes, '+'));
end
end

function s = structwithfields(s, varargin)
%STRUCTWITHFIELDS prepend the identity fields (kept for readability).
f = fieldnames(s);
s2 = struct();
for k = 1:2:numel(varargin)
    s2.(varargin{k}) = varargin{k + 1};
end
for k = 1:numel(f)
    s2.(f{k}) = s.(f{k});
end
s = s2;
end

function s = snapshotGlobals()
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
s = struct('M0C', M0C_ESC_PARAMS, 'M2P', M2_ETA_PARAMS, ...
    'M2A', M2_ETA_APPLIED, 'M3A', M3_ARB_PARAMS);
end

function m3tr_restore(s)
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
M0C_ESC_PARAMS = s.M0C; M2_ETA_PARAMS = s.M2P;
M2_ETA_APPLIED = s.M2A; M3_ARB_PARAMS = s.M3A;
clear('m0c_vref_esc'); clear('m2_eta_esc');
end
