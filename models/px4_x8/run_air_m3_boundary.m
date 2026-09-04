function result = run_air_m3_boundary(injectError)
%RUN_AIR_M3_BOUNDARY M3 group-C boundary trial: short Simulink, real wiring.
%   Two 160 s runs on air_spare (M2 semantic baseline; nominal + roll-sine
%   disturbed), slots eta 64 / v 32 with firstSlot = 'eta' and
%   (v0, eta0) = (9, 1.0):
%     - both channels take both roles (eta: search [0,64) hold [64,96)
%       search [96,160); v: hold [0,64) search [64,96) hold [96,160));
%     - eta's armed-floor startup (eta_act = 0 until the rotors spin up)
%       is a REAL invalid-during-search recovery through the model wiring;
%     - evidence is independent of m3_schedule's own outputs: the eta
%       candidate (m2_eta_log column 1) must be EXACTLY constant through
%       the planned hold slot, and the applied v channel (m0b_log_bus
%       column 1, after the selector ramp) must be constant through the
%       planned eta slots; invalid windows are itemized per cause from
%       the archived inputs, never blanket-exempted.
%   CONFIGURATION CALIBER (declared 2026-09-04, round-1 M3-R1-F6): this
%   entry is a MECHANISM PROBE at the M2-legacy eta gain 1e-4 -- it is
%   NOT the frozen M3 model set (2e-4, run_air_m3_trials) and never
%   grades the formal convergence numbers. The full effective config is
%   archived to effective_config.mat so the caliber is machine-checkable.
%   Zero .slx structure change (V1). FUNCTION ENTRY per rules 2.1/3.1:
%   machine-checkable result; the three config globals and M2_ETA_APPLIED
%   are snapshotted and restored on exit (success and error paths).
%   injectError = 'postwrite' throws after the first run's globals were
%   written and archived (restore-after-write evidence; not evidence
%   itself, so the dirty-tree gate does not apply to it).
if nargin < 1
    injectError = '';
end
model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));

global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
snap = snapshotGlobals();
cleanup = onCleanup(@() m3b_restore(snap)); %#ok<NASGU>

binding = m3_source_binding([mfilename('fullpath') '.m']);
assert(binding.dirty == 0 || strcmp(injectError, 'postwrite'), ...
    'air:M3Boundary:DirtyTree', ...
    ['evidence runs require a clean working tree; uncommitted ' ...
    'changes:\n%s'], strjoin(binding.dirtyLines, newline));

% ---- boundary mechanism-probe config: every field explicit, M2-legacy
% eta gain 1e-4 (see header -- NOT the 2e-4 M3 model set), no ambient
% inheritance (M3 doc 2.5)
pv = struct('mode', 'm3', 'center0', 9.0, 'lower', 6.0, 'upper', 12.0, ...
    'amplitude', 0.3, 'frequency', 0.25, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 6e-3, 'rateLimit', 2.0);
pe = struct('mode', 'm3', 'center0', 1.0, 'lower', 0.75, 'upper', 1.25, ...
    'amplitude', 0.02, 'frequency', 0.25, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 1e-4, 'rateLimit', 0.05);
arb = struct('enable', 'on', 'firstSlot', 'eta', 'slotEta', 64.0, 'slotV', 32.0);
m3_validate_channels(pv.mode, pe.mode, arb);   % cross-channel legality first

STOP_T = 160.0;
outDir = fullfile(wsRoot, 'results', 'air_m3_boundary', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
cfgB = struct('pv', pv, 'pe', pe, 'arb', arb, 'stopT', STOP_T, ...
    'caliber', 'mechanism probe, M2-legacy eta gain 1e-4');
save(fullfile(outDir, 'effective_config.mat'), 'cfgB');

runs = {'BN_nominal', true; 'BD_disturbed', false};
R = struct();
ok = true;
for k = 1:size(runs, 1)
    name = runs{k, 1};
    nominal = runs{k, 2};
    fprintf('=== %s (%s, slots eta 64 / v 32, 160 s) ===\n', name, ...
        nominal * 1 + ~nominal * 0);
    M0C_ESC_PARAMS = pv;
    M2_ETA_PARAMS = pe;
    M3_ARB_PARAMS = arb;
    M2_ETA_APPLIED = pe.center0;
    if bdIsLoaded(model)
        close_system(model, 0);
    end
    load_system(fullfile(modelDir, [model '.slx']));
    set_param(model, 'StopTime', num2str(STOP_T));
    set_param([model '/M0B Speed Loop Enable'], 'Value', '1');
    set_param([model '/M0A Optimizer Enable'], 'Value', '1');
    set_param([model '/M0B v Ref Manual'], 'Value', '5');
    if nominal
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
        Lg = out.get('m2_eta_log');
        el = double(squeeze(Lg.Data));
        if size(el, 2) ~= 4
            el = el';
        end
        te2 = Lg.Time(:);
        Pe = interp1(tp, P, te2, 'previous', P(1));
        r = evalBoundary(name, nominal, arb, Mb, tb, A, ta, Pe, el, te2, ...
            pv, pe, STOP_T);
        R.(name) = r;
        printBoundary(r);
        save(fullfile(outDir, [name '.mat']), 'r', 'Mb', 'tb', 'A', 'ta', ...
            'Pe', 'el', 'te2');
        if k == 1 && strcmp(injectError, 'postwrite')
            error('air:M3Boundary:InjectedPostWrite', ...
                'controlled failure after globals were written and archived');
        end
        if ~r.ok
            ok = false;
        end
    catch err
        % controlled-injection hooks escape the per-run degrade path: they
        % prove the ERROR-exit restore contract (see trials entry)
        if startsWith(err.identifier, 'air:M3Boundary:Injected')
            rethrow(err);
        end
        fprintf('  %s FAILED: %s\n', name, err.message);
        R.(name) = struct('name', name, 'ok', false);
        ok = false;
    end
    if bdIsLoaded(model)
        close_system(model, 0);
    end
end

result = struct('pass', ok, 'archiveDir', string(outDir), 'runs', R, ...
    'binding', binding, 'bindingExit', m3_source_binding( ...
    [mfilename('fullpath') '.m']), 'isFullBatch', true);
save(fullfile(outDir, 'result.mat'), 'result');
if ok
    fprintf('M3 BOUNDARY TRIAL PASS\n');
else
    fprintf('M3 BOUNDARY TRIAL FAIL\n');
end
fprintf('Archive: %s\n', outDir);
end

% ---------------------------------------------------------------------------
function r = evalBoundary(name, nominal, arb, Mb, tb, A, ta, Pe, el, te2, ...
    pv, pe, stopT) %#ok<INUSD>
%EVALBOUNDARY boundary predicates on the real logs (M3 doc sections
%   2.1/2.3/5). The plan is reconstructed ONLY as the expectation; every
%   predicate runs on archived signals that the schedule does not produce.
r = struct('name', name, 'nominal', nominal, 'ok', false);
nE = numel(te2);
searchE = false(nE, 1);
searchV = false(nE, 1);
for k = 1:nE
    ro = m3_schedule(te2(k), arb);
    searchE(k) = strcmp(ro.eta, 'search');
    searchV(k) = strcmp(ro.v, 'search');
end
% grid sanity: the eta log must sit on the 0.05 s sample grid
r.gridOK = max(abs(diff(te2) - 0.05)) < 1e-9;

% status / flags on the 1 ms bus
status = interp1(tb, Mb(:, 4), te2, 'previous', 0);
vrefApplied = interp1(tb, Mb(:, 1), te2, 'previous', 0);
vMeas = interp1(tb, Mb(:, 7), te2, 'previous', 0);
hardE = any(A(:, 27:30) > 0.5, 2) | any(A(:, 32:33) > 0.5, 2);
hardEi = interp1(ta, double(hardE), te2, 'previous', 0) > 0.5;
flag5i = interp1(ta, A(:, 31), te2, 'previous', 0) > 0.5;

etaCand = el(:, 1);
etaAct = el(:, 2);
sat = el(:, 3) > 0.5;

% ---- 1. role coverage: both channels take both roles
etaHold = ~searchE;
vHold = ~searchV;
r.rolesCovered = any(searchE) && any(etaHold) && any(searchV) && any(vHold);

% ---- 2. eta candidate EXACTLY constant through the planned hold slot
holdSel = searchV & te2 >= 64.0 + 1e-9 & te2 < 96.0 - 1e-9;   % v searches
r.etaHoldSamples = sum(holdSel);
r.etaHoldDev = max(abs(etaCand(holdSel) - etaCand(find(holdSel, 1))));
r.etaHoldConst = r.etaHoldDev < 1e-12;

% ---- 3. v applied constant WITHIN each planned v-hold run (the v
%         CANDIDATE is not logged in V1 -- registered evidence
%         limitation, checked through the applied channel after the
%         0.3/2.0 = 0.15 s rate-limit transition). The center may
%         legitimately CHANGE between hold runs -- that is the
%         alternating-search design -- so constancy is per-run.
holdRunsV = maskWindows(searchE);
r.vHoldDev = 0.0;
r.vHoldSamples = 0;
for j = 1:size(holdRunsV, 1)
    i0 = holdRunsV(j, 1); i1 = holdRunsV(j, 2);
    sel = (i0:i1)';
    sel = sel(te2(sel) >= te2(i0) + 0.3 & status(sel) == 2 & ~hardEi(sel));
    if numel(sel) >= 2
        r.vHoldDev = max(r.vHoldDev, ...
            max(abs(vrefApplied(sel) - vrefApplied(sel(1)))));
        r.vHoldSamples = r.vHoldSamples + numel(sel);
    end
end
r.vHoldConst = r.vHoldDev < 1e-9;

% ---- 4. invalid windows itemized per cause (never blanket-exempted)
validE = ~hardEi & ~sat & etaAct > 0 & isfinite(Pe);
invE = ~validE;
winE = maskWindows(invE);
r.etaInvalidWindows = buildWindowTable(winE, te2, searchE, ...
    hardEi, sat, etaAct > 0, isfinite(Pe));
validV = ~hardEi & isfinite(Pe) & vMeas >= pv.lower & vMeas <= pv.upper;
invV = ~validV;
winV = maskWindows(invV);
r.vInvalidWindows = buildWindowTable(winV, te2, searchV, ...
    hardEi, false(size(te2)), vMeas >= pv.lower & vMeas <= pv.upper, ...
    isfinite(Pe));
% the armed-floor startup must give eta a real invalid-during-search
% window that recovers (recovery = the channel stays valid afterwards
% through at least the first full eta slot)
r.etaInvalidDuringSearch = any([r.etaInvalidWindows.duringSearch]) && ...
    all(validE(te2 >= 20.0 & te2 < 60.0));
if isempty(r.etaInvalidWindows)
    r.etaInvalidDuringSearch = false;
end

% ---- 5. bands and supervision
late = te2 >= 10.0;
r.etaBandOK = all(etaCand(late) >= 0.73 & etaCand(late) <= 1.27);
r.vBandOK = all(vrefApplied(te2 >= 10.0) >= 5.95 & ...
    vrefApplied(te2 >= 10.0) <= 12.05);
r.statusActive = any(status == 2);
r.nFrozen = sum(diff(interp1(tb, Mb(:, 4), tb, 'previous', 0) == 3) == 1);
r.nFb = sum(diff(status == 4) == 1);
% t=0 initialization sample excluded (M2 convention: base = tb >= 0.005;
% the monitors trip on the zero state at the solver's first step)
baseE = te2 >= 0.05;
r.hardMax = max(double(hardEi(baseE)));
r.satFrac = mean(sat(baseE));

r.ok = r.gridOK && r.rolesCovered && r.etaHoldConst && r.vHoldConst && ...
    r.etaInvalidDuringSearch && r.etaBandOK && r.vBandOK && ...
    r.statusActive && r.nFb == 0;
if nominal
    r.ok = r.ok && r.hardMax == 0 && r.satFrac == 0 && r.nFrozen == 0;
end
end

function w = maskWindows(mask)
%MASKWINDOWS contiguous true-runs as [start idx; end idx].
padded = [false; mask(:); false];
d = diff(padded);
w = [find(d == 1), find(d == -1) - 1];
end

function tbl = buildWindowTable(win, t, searchMask, hard, sat, inBand, finP)
%BUILDWINDOWTABLE per-window cause itemization for the evidence report.
n = size(win, 1);
tbl = struct('tStart', {}, 'tEnd', {}, 'duringSearch', {}, 'causes', {});
for j = 1:n
    i0 = win(j, 1); i1 = win(j, 2);
    causes = {};
    if any(hard(i0:i1)), causes{end + 1} = 'hard'; end %#ok<AGROW>
    if any(sat(i0:i1)), causes{end + 1} = 'sat'; end %#ok<AGROW>
    if any(~inBand(i0:i1)), causes{end + 1} = 'outOfBand'; end %#ok<AGROW>
    if any(~finP(i0:i1)), causes{end + 1} = 'nonFiniteP'; end %#ok<AGROW>
    if isempty(causes), causes = {'other'}; end
    tbl(end + 1) = struct('tStart', t(i0), 'tEnd', t(i1), ...
        'duringSearch', any(searchMask(i0:i1)), 'causes', {causes}); %#ok<AGROW>
end
end

function printBoundary(r)
fprintf(['  grid %d roles %d | eta hold dev %.3g (%d samples) | ' ...
    'v applied hold dev %.3g (%d samples) | eta invalid-during-search %d\n'], ...
    r.gridOK, r.rolesCovered, r.etaHoldDev, r.etaHoldSamples, ...
    r.vHoldDev, r.vHoldSamples, r.etaInvalidDuringSearch);
fprintf(['  band eta %d v %d | status2 %d frozen %d fb %d | hard %d ' ...
    'sat %.3f | invalid windows: eta %d, v %d\n'], ...
    r.etaBandOK, r.vBandOK, r.statusActive, r.nFrozen, r.nFb, ...
    r.hardMax, r.satFrac, numel(r.etaInvalidWindows), ...
    numel(r.vInvalidWindows));
for j = 1:numel(r.etaInvalidWindows)
    w = r.etaInvalidWindows(j);
    fprintf('    eta invalid [%.2f, %.2f] duringSearch=%d causes: %s\n', ...
        w.tStart, w.tEnd, w.duringSearch, strjoin(w.causes, '+'));
end
for j = 1:numel(r.vInvalidWindows)
    w = r.vInvalidWindows(j);
    fprintf('    v invalid [%.2f, %.2f] duringSearch=%d causes: %s\n', ...
        w.tStart, w.tEnd, w.duringSearch, strjoin(w.causes, '+'));
end
end

function s = snapshotGlobals()
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
s = struct('M0C', M0C_ESC_PARAMS, 'M2P', M2_ETA_PARAMS, ...
    'M2A', M2_ETA_APPLIED, 'M3A', M3_ARB_PARAMS);
end

function m3b_restore(s)
global M0C_ESC_PARAMS M2_ETA_PARAMS M2_ETA_APPLIED M3_ARB_PARAMS
M0C_ESC_PARAMS = s.M0C; M2_ETA_PARAMS = s.M2P;
M2_ETA_APPLIED = s.M2A; M3_ARB_PARAMS = s.M3A;
clear('m0c_vref_esc'); clear('m2_eta_esc');
end
