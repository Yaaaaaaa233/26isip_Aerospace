function r = m3_eval_arm(id, nominal, modeV, modeEta, v0, eta0, arb, ...
    pv, pe, r, logs, gateWin, convWin, contWin, stopT)
%M3_EVAL_ARM The single production per-arm evaluation path (round-1
%   findings M3-R1-F2/F3 closure). Formerly a local function of
%   run_air_m3_trials, now the ONLY place per-arm gates are decided, so
%   unit negatives driven here are negatives of the formal batch itself:
%     - execution evidence runs through m3_check_execution (finiteness,
%       plan exclusivity, hold constancy, slew/lag/resume, participation)
%       instead of an inline plan-only reconstruction;
%     - eta convergence runs through m3_eval_convergence (the same
%       evaluator the unit fixtures use), window [192,240) per M3 doc
%       6.4, and MONOTONICITY is a hard gate for nominal m3 arms (it was
%       computed but never gated before). Round-2 M3-R2-F2: the graded
%       input is the search CENTER reconstructed by replaying the frozen
%       kernel on the archived measurements (m3_replay_eta_center); the
%       replay must reproduce the archived candidate sample-exact
%       (air:M3EvalArm:ReplayMismatch) -- the candidate itself is
%       center+dither and its period-end samples are dither-polluted;
%     - every arm (nominal AND disturbed) is subject to the section 6.2
%       rule-3 long-window saturation cap: bits 1/2 continuously hot for
%       at most 2 s;
%     - every arm is subject to the section 6.3 attitude-limit gate:
%       bit 3 (log column 29) must never fire (round-2 M3-R2-F3 -- it
%       was gated for nominal arms only, leaving disturbed arms without
%       the contract's 姿态限幅内 requirement);
%     - allocator-sat run length is reported (not gated: the cap is on
%       bits 1/2).
%   pv/pe are THIS arm's effective channel configs (frozen per-arm
%   parameter sets, M3 doc 2.5); gateWin/convWin/contWin per doc 5/6.
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
validV = ~hardEi & isfinite(Pe) & vMeas >= pv.lower & vMeas <= pv.upper;
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

r.exe = struct();
r.exe.planExclusive = ~any(searchV & searchE);
r.exe.nSwitch = sum(diff(searchV) ~= 0);

% ---- execution evidence: the checker runs on archived signals and is
% the decision path (V1 logs no v candidate: hold constancy for v is
% checked on the applied trace after its rate-limit transition; search
% participation is a hard requirement on nominal arms only -- disturbed
% arms legitimately freeze the dither through invalid windows)
r.exe.chk = [];
if strcmp(modeV, 'm3') || strcmp(modeEta, 'm3')
    prmV = struct('amplitude', pv.amplitude, 'rateLimit', pv.rateLimit, ...
        'Ts', 0.05);
    prmE = struct('amplitude', pe.amplitude, 'rateLimit', pe.rateLimit, ...
        'Ts', 0.05);
    r.exe.chk = m3_check_execution(te2, searchV, searchE, vrefApplied, ...
        etaCand, vrefApplied, etaAct, prmV, prmE, ...
        'vViaApplied', true, 'requireParticipation', nominal, ...
        'etaAppliedIsActual', true, 'vHoldMask', status == 2 & ~hardEi);
    r.exe.etaHoldDev = r.exe.chk.maxHoldDevE;
    r.exe.etaHoldSamples = r.exe.chk.nHoldRunsE;
    r.exe.vHoldDev = r.exe.chk.maxHoldDevV;
    r.exe.vHoldSamples = r.exe.chk.nHoldRunsV;
    r.exe.etaHoldConst = r.exe.chk.maxHoldDevE < 1e-12;
else
    r.exe.etaHoldDev = 0.0;
    r.exe.etaHoldSamples = 0;
    r.exe.vHoldDev = 0.0;
    r.exe.vHoldSamples = 0;
    r.exe.etaHoldConst = true;
end

% invalid windows itemized per cause, per channel, with role annotation
r.exe.etaInvalid = windowTable(maskWindowsLocal(~validE & searchE), ...
    te2, hardEi, sat, etaAct > 0, isfinite(Pe));
r.exe.vInvalid = windowTable(maskWindowsLocal(~validV & searchV), ...
    te2, hardEi, false(size(te2)), ...
    vMeas >= pv.lower & vMeas <= pv.upper, isfinite(Pe));
r.exe.learnE = sum(learnE);
r.exe.learnV = sum(learnV);

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

% ---- attitude-limit gate (round-2 M3-R2-F3): contract section 6.3
% requires 姿态限幅内 for EVERY trial, not only nominal arms -- bit 3
% (log column 29, M0B Att Tol 0.523 rad) firing at any sample after
% spin-up fails the arm. The remaining hard bits stay reported (bits 1/2
% are capped at 2 s below on every arm; the nominal branch additionally
% requires zero hard events and zero saturation).
att3i = interp1(ta, double(A(:, 29) > 0.5), te2, 'previous', 0) > 0.5;
r.attLimitMax = max(double(att3i(hardBase)));

% ---- long-window saturation cap (M3 doc 6.2 rule 3): bits 1/2 (m0a log
% columns 27/28) may not stay continuously hot longer than 2 s -- this
% applies to NOMINAL AND DISTURBED arms; the allocator sat run length is
% reported (the frozen cap is on bits 1/2)
bit12 = interp1(ta, double(A(:, 27) > 0.5 | A(:, 28) > 0.5), te2, ...
    'previous', 0) > 0.5;
r.hard12RunMax = maxRunDur(bit12, te2);
r.satRunMax = maxRunDur(sat, te2);
r.hard12OK = r.hard12RunMax <= 2.0 + 0.05;

% ---- eta convergence through the SINGLE shared evaluator (M3 doc 6.4:
% period means / period-END CENTERS on the last full search slot
% [192,240)). Round-2 M3-R2-F2: the graded input is the VERIFIABLE SEARCH
% CENTER, not the archived candidate -- the candidate is center + dither
% and its period-end samples are dither-polluted (a phase-shifted dither
% could pass a departing center or reject an approaching one). The center
% is reconstructed by replaying the frozen kernel on the archived
% measurements (m3_replay_eta_center); a faithful replay reproduces the
% archived candidate sample-exact, which is asserted here as the evidence
% self-consistency gate. Pure-esc arms (B2) search continuously: both arm
% families are graded on the SAME explicit [192,240) window.
r.etaCenter = [];
r.etaConv = [];
r.etaReplayDiff = Inf;
if strcmp(modeEta, 'm3') || strcmp(modeEta, 'esc')
    convMask = te2 >= convWin(1) & te2 < convWin(2);
    if strcmp(modeEta, 'm3')
        convMask = convMask & searchE;
    end
    [ctr, ~, repDiff] = m3_replay_eta_center(te2, Pe, etaAct, sat, ...
        hardEi, searchE, modeEta, eta0, pe, etaCand);
    assert(repDiff <= 1e-12, 'air:M3EvalArm:ReplayMismatch', ...
        ['kernel replay diverges from the archived candidate (max ' ...
        'abs diff %.3g): the logs are not self-consistent evidence'], ...
        repDiff);
    r.etaReplayDiff = repDiff;
    ec = m3_eval_convergence(te2, ctr, convMask, pe.frequency, ...
        0.01, 5e-3);
    if strcmp(modeEta, 'm3')
        % the evaluator's last search run must BE the criterion window:
        % guards an arb/schedule drift between config and frozen gates
        runsE = runBounds(convMask);
        assert(abs(te2(runsE(end, 1)) - convWin(1)) < 0.1, ...
            'air:M3EvalArm:ConvWindow', ...
            'last eta search slot starts at %.2f s, expected %.2f s', ...
            te2(runsE(end, 1)), convWin(1));
    end
    r.etaConv = ec;
    r.etaCenter = ec.periodMean;
end

% ---- hard gates per arm (safety + execution evidence + convergence)
r.ok = r.exe.planExclusive && r.etaBandOK && r.vBandOK && r.nFb == 0 && ...
    r.yawMax <= 1.5 && r.hard12OK && r.attLimitMax == 0;
if nominal
    r.ok = r.ok && r.hardMax == 0 && r.satFrac == 0;
end
if ~isempty(r.exe.chk)
    % finiteness, hold constancy, slew/lag/resume, and (nominal)
    % participation all live inside the checker's pass
    r.ok = r.ok && r.exe.chk.pass;
end
if strcmp(modeEta, 'm3') && nominal
    % monotonicity is part of the frozen 6.4 criterion -- computed but
    % never gated before (round-1 negative N6)
    r.ok = r.ok && r.etaConv.converged && r.etaConv.monotonic;
end
r = structwithfields(r, 'id', id, 'nominal', nominal, 'modeV', modeV, ...
    'modeEta', modeEta, 'v0', v0, 'eta0', eta0, 'stopT', stopT, ...
    'gateWin', gateWin, 'convWin', convWin, 'contWin', contWin);
end

function runs = runBounds(mask)
padded = [false; mask(:); false];
d = diff(padded);
runs = [find(d == 1), find(d == -1) - 1];
if isempty(runs)
    runs = zeros(0, 2);
end
end

function dur = maxRunDur(maskLogical, t)
%MAXRUNDUR longest contiguous true-run duration in seconds.
runs = runBounds(maskLogical);
dur = 0.0;
for j = 1:size(runs, 1)
    dur = max(dur, t(runs(j, 2)) - t(runs(j, 1)));
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
