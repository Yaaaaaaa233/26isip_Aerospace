function [center, cand, maxDiff] = m3_replay_eta_center(te2, Pe, ...
    etaAct, sat, hardEi, searchE, mode, eta0, pe, candArchived)
%M3_REPLAY_ETA_CENTER Reconstruct the eta SEARCH CENTER by replaying the
%   frozen kernel offline over the archived measurements (round-2
%   independent report M3-R2-F2 closure).
%
%   The V1 log keeps only the CANDIDATE reference (el column 1) = center +
%   dither. The dither is generated INSIDE the ratioesc kernel, so the only
%   admissible way to recover the center is to replay that same kernel on
%   the same archived inputs: it is deterministic, so a faithful replay
%   reproduces the archived candidate SAMPLE-EXACT and its internal
%   st.center is the verifiable search center the contract (M3 doc 6.4)
%   grades. A log whose candidate the kernel cannot reproduce is not
%   self-consistent evidence and is rejected by the caller (replay
%   fidelity gate, air:M3EvalArm:ReplayMismatch).
%
%   The replay mirrors m2_eta_esc's m3/esc branches exactly: search samples
%   step the kernel with the archived validity (hard flags, sat, eta_act>0,
%   finite Pe); m3 hold samples publish the clean center and set the
%   reinitialize/warmup state like the adapter does; esc arms step every
%   sample. Config comes from THIS arm's frozen effective config (pe), so
%   per-arm gains replay per-arm behavior.
%
%   Inputs (all per-sample columns on the te2 grid):
%     te2 / Pe / etaAct / sat(logical) / hardEi(logical) / searchE(logical)
%     mode: 'm3' or 'esc' (the arm's eta mode)
%     eta0: the arm's initial ratio (kernel reset state)
%     pe: the arm's effective eta channel config (frozen set)
%     candArchived: the archived candidate (el column 1) for the fidelity
%       check; pass [] to skip (diagnostics only).
%   Outputs: center (replayed st.center per sample), cand (replayed
%   candidate), maxDiff (max |cand - candArchived|; 0 when skipped).
Ts = 0.05;
n = numel(te2);
center = zeros(n, 1);
cand = zeros(n, 1);

ensureKernelPath();
cfg = ratioesc.config('Ts', Ts, 'lower', pe.lower, 'upper', pe.upper, ...
    'amplitude', pe.amplitude, 'frequency', pe.frequency, ...
    'hpOmega', pe.hpOmega, 'lpOmega', pe.lpOmega, 'gain', pe.gain, ...
    'rateLimit', pe.rateLimit, ...
    'initialRatio', eta0, 'fixedReference', eta0, ...
    'optimalRatio', eta0, 'shiftedOptimalRatio', eta0, ...
    'stage', 'esc', 'duration', 600);
% module whitelist boundary: no plant map or optimizer truth crosses
p = ratioesc.controller_config(cfg);
st = ratioesc.esc_reset(p, eta0, Pe(1));
warmupSteps = ceil(1 / (pe.frequency * Ts));
for i = 1:n
    valid = ~hardEi(i) && isfinite(Pe(i)) && ~sat(i) && etaAct(i) > 0;
    if strcmp(mode, 'm3') && ~searchE(i)
        % hold: the adapter publishes the clean center and syncs the kernel
        % state exactly this way (m2_eta_esc m3 branch)
        cand(i) = st.center;
        st.lastReference = st.center;
        st.reinitialize = true;   % idempotent; consumed on resume
        st.warmup = warmupSteps;
    else
        [cand(i), st] = ratioesc.esc_step(st, Pe(i), etaAct(i), valid, p);
    end
    center(i) = st.center;
end
if isempty(candArchived)
    maxDiff = 0;
else
    maxDiff = max(abs(cand(:) - candArchived(:)));
end
end

function ensureKernelPath()
%ENSUREKERNELPATH make ratioesc resolvable regardless of the caller's
%   addpath state (m2_eta_esc pattern, isfolder-based resolution).
if isempty(which('ratioesc.esc_step'))
    adapterDir = fileparts(mfilename('fullpath'));
    wsRoot = fileparts(fileparts(adapterDir));
    cands = {fullfile(wsRoot, 'modules', 'ratio_esc'), ...
        fullfile(wsRoot, '26isip_Aerospace', 'modules', 'ratio_esc')};
    for k = 1:numel(cands)
        if ~isfolder(cands{k})
            continue
        end
        addpath(cands{k});
        if ~isempty(which('ratioesc.esc_step'))
            return
        end
    end
end
assert(~isempty(which('ratioesc.esc_step')), 'm3:KernelMissing', ...
    'ratio_esc module not found next to %s', mfilename('fullpath'));
end
