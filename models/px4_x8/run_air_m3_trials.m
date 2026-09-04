function result = run_air_m3_trials(injectError, scenarioSet, baseDir)
%RUN_AIR_M3_TRIALS M3 paired coordination trials (M3_V_ETA_COORDINATION.md
%   section 5, pre-registered). 14-scenario row-frozen pairing matrix:
%   M3 nominal 5 ({7,11} x {0.8,1.2} + (9,1.0)), disturbed 2,
%   reproducibility 1, and the B0/B1/B2 baselines (6 rows). Same model,
%   same wiring; the only difference between arms is the global config.
%   Duration 240 s; primary gate = the cycle-common energy window
%   [144,240] s (exactly one full eta 64 + v 32 cycle; the pairwise-common
%   valid mask decides which samples count -- coverage and the full-window
%   integral are reported alongside, never conflated); eta convergence
%   end-window [192,240) s (doc 6.4, the last full search slot -- the
%   doc's section 5 [200,240] wording was a conflict, unified 2026-09-04);
%   [20,30] s continuity reported only.
%   Per-arm evaluation lives in m3_eval_arm (the single production path);
%   per-arm gates include the execution checker, convergence monotonicity
%   (nominal) and the 2 s continuous bits-1/2 cap on every arm.
%   Everything model-estimated (P_est, no calibration).
%
%   FUNCTION ENTRY per ACCEPTANCE_AUTOMATION_RULES.md 2.1/3.1: returns a
%   machine-checkable result; the four globals are snapshotted and
%   restored on exit (success and error paths). Evidence runs require a
%   CLEAN tree and bind result.mat to the live commit + file fingerprints
%   (m3_source_binding; rules section 2 rules 4/5); a dirty tree is a
%   hard error except in hook mode. injectError hooks (controlled
%   failures, never evidence): 'trials' short-circuits with pass=false
%   before any state is written; 'cfgmismatch' flips a B2 arm's archived
%   gain before the frozen-config assertion (must be rejected); 'savefail'
%   and 'postwrite' fire after arm 1's globals were written, just before /
%   just after its archive save (restore-after-write evidence).
%   scenarioSet: 'full' (default) = all 14 rows; any subset of row IDs,
%   e.g. {'M3-N1'} or {'B0-N','M3-N5'}, for the segmented execution the
%   R2022b heap limitation requires (M2 'keep' filter precedent). A
%   subset result is a SEGMENT result: the batch verdict comes from
%   m3_aggregate_batch over all segments.


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

% ---- evidence binding (round-1 M3-R1-F4): live capture, no placeholders.
% Real (evidence) runs require a clean tree; the controlled-failure hooks
% are explicitly not evidence, so they are exempt from the dirty gate.
hookMode = any(strcmp(injectError, {'trials', 'cfgmismatch', ...
    'savefail', 'postwrite'}));
binding = m3_source_binding([mfilename('fullpath') '.m']);
assert(binding.dirty == 0 || hookMode, 'air:M3Trials:DirtyTree', ...
    ['evidence runs require a clean working tree; uncommitted ' ...
    'changes:\n%s'], strjoin(binding.dirtyLines, newline));

% ---- frozen parameter sets, PER ARM (M3 doc 2.5; round-1 M3-R1-F1):
% every non-m3 eta arm (fixed/esc, i.e. the B0/B1/B2 baselines) keeps the
% M2 model set gain 1e-4 -- B2 represents the M2 line; only m3 arms run
% the M3 model set gain 2e-4 (2026-09-03 slot-duty recheck freeze). The v
% channel gain 6e-3 is common to both sets (M0-C model caliber). The
% frozen expectation is asserted literally after archiving (see
% assertFrozenConfig) so a rerun cannot silently swap either set.
arb = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 64.0, 'slotV', 32.0);
pvBase = struct('mode', 'm3', 'center0', 9.0, 'lower', 6.0, 'upper', 12.0, ...
    'amplitude', 0.3, 'frequency', 0.25, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 6e-3, 'rateLimit', 2.0);
peM3 = struct('mode', 'm3', 'center0', 1.0, 'lower', 0.75, 'upper', 1.25, ...
    'amplitude', 0.02, 'frequency', 0.25, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 2e-4, 'rateLimit', 0.05);
peM2 = peM3;
peM2.gain = 1e-4;   % M2 legacy set (m2_eta_esc file default semantics)
m3_validate_channels(pvBase.mode, peM3.mode, arb);

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
CONV_WIN = [192.0, 240.0];   % eta convergence window = last full search
                              % slot (doc 6.4; section 5 conflict unified)
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
% (machine-checkable provenance, M3 doc 2.5: no ambient inheritance). The
% eta parameter set is selected PER ARM by mode (M3-R1-F1): m3 -> M3 model
% set, fixed/esc -> M2 model set.
cfgAll = struct();
for k = 1:size(plan, 1)
    id = plan{k, 1};
    peSel = peForMode(peM3, peM2, plan{k, 4});
    % dynamic field names accept dashes; struct() name/value pairs do not
    cfgAll.(fieldOf(id)) = struct('pv', channelCfg(pvBase, plan{k, 3}, plan{k, 5}), ...
        'pe', channelCfg(peSel, plan{k, 4}, plan{k, 6}), 'arb', arb, ...
        'row', {plan(k, :)});
end
% controlled-failure hook: corrupt the FIRST arm's archived gain AFTER the
% table is built -- the frozen assertion below must reject it (works for
% any subset: m3 arms drift off 2e-4, baseline arms off 1e-4)
if strcmp(injectError, 'cfgmismatch')
    f1 = fieldOf(plan{1, 1});
    cfgAll.(f1).pe.gain = 2 * cfgAll.(f1).pe.gain;
end
save(fullfile(outDir, 'effective_config.mat'), 'cfgAll');
assertFrozenConfig(cfgAll, strcmp(scenarioSet, 'full'));

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
    M2_ETA_PARAMS = channelCfg(peForMode(peM3, peM2, modeEta), modeEta, eta0);
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
        r = m3_eval_arm(id, nominal, modeV, modeEta, v0, eta0, arb, ...
            M0C_ESC_PARAMS, M2_ETA_PARAMS, r, logs, ...
            GATE_WIN, CONV_WIN, CONT_WIN, stopT);
        r.logs = logs;   % embedded: in-session pairing + cross-segment loads
        R.(fieldOf(id)) = r;
        printArm(r);
        % restore-after-write evidence hooks (round-1 M3-R1-F4): by now
        % this arm's globals were fully written; 'savefail' throws just
        % before the archive write, 'postwrite' just after it
        if k == 1 && strcmp(injectError, 'savefail')
            error('air:M3Trials:InjectedSaveFail', ...
                'controlled failure after globals were written, before archive');
        end
        save(fullfile(outDir, [id '.mat']), 'r');
        if k == 1 && strcmp(injectError, 'postwrite')
            error('air:M3Trials:InjectedPostWrite', ...
                'controlled failure after globals were written and archived');
        end
        if ~r.ok
            ok = false;
        end
    catch err
        % controlled-injection hooks escape the per-arm degrade path: they
        % exist to prove the ERROR-exit restore contract, not to exercise
        % the (already covered) arm-failure degradation
        if startsWith(err.identifier, 'air:M3Trials:Injected')
            rethrow(err);
        end
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
        fprintf(['%s vs B0-N: dE[144,240] masked %+.5f%% (gate %.1f%%) | ' ...
            'full-window %+.5f%% | common %.1f%% of window (%d/%d)\n'], ...
            id, e.dEPct, NOTWORSE, e.dEPctFull, 100 * e.maskFrac, ...
            e.nMask, e.nWin);
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
            fprintf(['%s vs %s: dE[144,240] masked %+.5f%% (gate %.1f%%) | ' ...
                'full-window %+.5f%% | common %.1f%% of window (%d/%d)\n'], ...
                a, b, e.dEPct, NOTWORSE, e.dEPctFull, 100 * e.maskFrac, ...
                e.nMask, e.nWin);
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
    % v tracking: nearest-variable pairing (same v0 only) -- ALL four
    % grid-corner nominal arms have a same-v0 B1 partner (round-1 M3-R1-F4
    % listed only N1/N3 before)
    vPairs = {'M3-N1', 'B1-N1'; 'M3-N2', 'B1-N1'; ...
        'M3-N3', 'B1-N2'; 'M3-N4', 'B1-N2'};
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
    % and N5 arms must be in the SAME invocation BY DESIGN: one without
    % the other is a FAILED segment (round-1 M3-R1-F4: this used to be
    % silently skipped), and unequal log lengths/grids are a hard failure
    % (no min-length truncation)
    haveN5 = isfield(R, fieldOf('M3-N5'));
    haveR1 = isfield(R, fieldOf('M3-R1'));
    if haveN5 ~= haveR1
        ok = false;
        fprintf(['  M3-R1/M3-N5 same-session requirement VIOLATED: %s ran ' ...
            'without %s\n'], ...
            ternary(haveN5, 'M3-N5', 'M3-R1'), ...
            ternary(haveN5, 'M3-R1', 'M3-N5'));
    elseif haveN5
        e5 = R.(fieldOf('M3-N5')).logs.el;
        eR = R.(fieldOf('M3-R1')).logs.el;
        assert(size(e5, 1) == size(eR, 1), 'air:M3Trials:ReproGrid', ...
            'M3-N5 (%d rows) and M3-R1 (%d rows) log lengths differ', ...
            size(e5, 1), size(eR, 1));
        dv = max(abs(e5(:, 1) - eR(:, 1)));
        v5 = R.(fieldOf('M3-N5')).logs.Mb;
        vR = R.(fieldOf('M3-R1')).logs.Mb;
        assert(size(v5, 1) == size(vR, 1), 'air:M3Trials:ReproGrid', ...
            'M3-N5 (%d rows) and M3-R1 (%d rows) bus lengths differ', ...
            size(v5, 1), size(vR, 1));
        dv2 = max(abs(v5(:, 1) - vR(:, 1)));
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

% segment-level result WITHOUT the embedded logs: the per-arm <id>.mat
% archives keep them; a multi-arm result with logs exceeded the 2 GB
% MAT-v7 limit in the round-2 rerun and the save silently skipped the
% variable (128-byte stub). Verdicts, bindings and pair metrics are all
% log-free; the aggregate loads arm data from the per-arm archives.
runsLite = R;
fnR = fieldnames(runsLite);
for j = 1:numel(fnR)
    if isfield(runsLite.(fnR{j}), 'logs')
        runsLite.(fnR{j}) = rmfield(runsLite.(fnR{j}), 'logs');
    end
end
% NOTE: scenarioSet is a cell array for segment runs -- struct() name/value
% REPLICATES the struct per cell element unless the cell is wrapped, which
% silently produced a 1xN result struct array (the round-2 rerun archives
% 20260904_112953/114351 carry that defect and are superseded)
result = struct('pass', ok, 'archiveDir', string(outDir), 'runs', runsLite, ...
    'pair', pair, 'binding', binding, 'isFullBatch', ...
    strcmp(scenarioSet, 'full'), 'scenarioSet', {scenarioSet});
save(fullfile(outDir, 'result.mat'), 'result');
if ~strcmp(scenarioSet, 'full')
    fprintf(['SEGMENT result (%s): the batch verdict requires ' ...
        'm3_aggregate_batch over all segments\n'], ...
        strjoin(plan(:, 1), ','));
end
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

function printArm(r)
chkPass = true;
if ~isempty(r.exe.chk)
    chkPass = r.exe.chk.pass;
end
fprintf(['  ok %d (chk %d) | hold: eta dev %.3g, v dev %.3g | ' ...
    'vTrk %.5f sat %.3f yaw %.3f pwm [%.0f %.0f] hard %d fb %d | ' ...
    'bit12run %.2f s satRun %.2f s\n'], ...
    r.ok, chkPass, r.exe.etaHoldDev, r.exe.vHoldDev, ...
    r.vTrk, r.satFrac, r.yawMax, r.pwmMin, ...
    r.pwmMax, r.hardMax, r.nFb, r.hard12RunMax, r.satRunMax);
if ~isempty(r.exe.chk) && ~r.exe.chk.pass
    fprintf('    chk failFields: %s\n', strjoin(r.exe.chk.failFields, ','));
end
if ~isempty(r.etaConv)
    fprintf(['  eta conv: [192,240) mean %.5f (converged %d, ' ...
        'monotonic %d, maxRegression %.2g)\n'], ...
        r.etaCenter, r.etaConv.converged, r.etaConv.monotonic, ...
        r.etaConv.maxRegression);
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

function b = peForMode(peM3set, peM2set, modeEta)
%PEFORMODE per-arm eta parameter set (M3 doc 2.5, round-1 M3-R1-F1): m3
%   arms run the M3 model set (gain 2e-4); every non-m3 eta arm
%   (fixed/esc) keeps the M2 model set (gain 1e-4) -- B2 represents the
%   M2 line. The selection is by MODE, not by a shared base struct, and
%   assertFrozenConfig re-checks the result literally below.
if strcmp(modeEta, 'm3')
    b = peM3set;
else
    b = peM2set;
end
end

function assertFrozenConfig(cfgAll, requireAll)
%ASSERTFROZENCONFIG literal per-arm expectation table (M3-R1-F1): the
%   archived effective config of every arm is checked against a frozen
%   LITERAL table, not against a rebuild -- a mode-based builder bug or a
%   tampered archive must fail here before any simulation runs. SEGMENT
%   (subset) runs check every arm they actually have; a 'full' run must
%   additionally contain all 14 frozen arms (the batch completeness
%   itself is enforced by m3_aggregate_batch's manifest contract).
%   v gain 6e-3 for every arm; eta gain 2e-4 for M3 arms, 1e-4 for all
%   baseline arms; eta/v modes and band limits are part of the frozen
%   matrix.
want = { ...
    'M3-N1', 'm3',  'm3',  2e-4; ...
    'M3-N2', 'm3',  'm3',  2e-4; ...
    'M3-N3', 'm3',  'm3',  2e-4; ...
    'M3-N4', 'm3',  'm3',  2e-4; ...
    'M3-N5', 'm3',  'm3',  2e-4; ...
    'M3-D1', 'm3',  'm3',  2e-4; ...
    'M3-D2', 'm3',  'm3',  2e-4; ...
    'M3-R1', 'm3',  'm3',  2e-4; ...
    'B0-N',  'fixed', 'fixed', 1e-4; ...
    'B0-D',  'fixed', 'fixed', 1e-4; ...
    'B1-N1', 'esc', 'fixed', 1e-4; ...
    'B1-N2', 'esc', 'fixed', 1e-4; ...
    'B2-N1', 'fixed', 'esc', 1e-4; ...
    'B2-N2', 'fixed', 'esc', 1e-4};
fn = sort(fieldnames(cfgAll));
assert(~isempty(fn), 'air:M3Trials:ConfigDrift', ...
    'empty effective-config table');
present = cellfun(@(x) strrep(x, '_', '-'), fn, ...
    'UniformOutput', false);
unknown = setdiff(present, want(:, 1));
assert(isempty(unknown), 'air:M3Trials:ConfigDrift', ...
    'arms outside the frozen matrix: %s', strjoin(unknown, ','));
if requireAll
    assert(numel(fn) == size(want, 1), 'air:M3Trials:ConfigDrift', ...
        'full run config table has %d arms, frozen matrix expects %d', ...
        numel(fn), size(want, 1));
end
for j = 1:numel(present)
    id = present{j};
    row = want(strcmp(want(:, 1), id), :);
    row = row(1, :);
    a = cfgAll.(fieldOf(id));
    assert(strcmp(a.pv.mode, row{2}) && strcmp(a.pe.mode, row{3}), ...
        'air:M3Trials:ConfigDrift', ...
        '%s channel modes (%s/%s) differ from the frozen matrix', ...
        id, a.pv.mode, a.pe.mode);
    assert(abs(a.pe.gain - row{4}) < 1e-12, ...
        'air:M3Trials:ConfigDrift', ...
        '%s eta gain %.0e differs from the frozen %.0e (M3 model set 2e-4, M2 legacy set 1e-4)', ...
        id, a.pe.gain, row{4});
    assert(abs(a.pv.gain - 6e-3) < 1e-12, 'air:M3Trials:ConfigDrift', ...
        '%s v gain %.0e differs from the frozen 6e-3', id, a.pv.gain);
    assert(abs(a.pe.amplitude - 0.02) < 1e-12 && ...
        abs(a.pv.amplitude - 0.3) < 1e-12 && ...
        abs(a.pe.rateLimit - 0.05) < 1e-12 && ...
        abs(a.pv.rateLimit - 2.0) < 1e-12, ...
        'air:M3Trials:ConfigDrift', ...
        '%s dither/limit fields differ from the frozen model set', id);
    assert(abs(a.arb.slotEta - 64.0) < 1e-12 && ...
        abs(a.arb.slotV - 32.0) < 1e-12 && ...
        strcmp(a.arb.firstSlot, 'eta') && strcmp(a.arb.enable, 'on'), ...
        'air:M3Trials:ConfigDrift', ...
        '%s arbitration config differs from the frozen eta64/v32', id);
end
end

function out = ternary(cond, a, b)
%TERNARY inline conditional (kept for the one-line repro message).
if cond
    out = a;
else
    out = b;
end
end
