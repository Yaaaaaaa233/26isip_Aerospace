function etaOut = m2_eta_esc(u)
%M2_ETA_ESC M2 coaxial-ratio optimizer reference interface (roadmap M2).
%   Wraps the Git-module kernel (ratioesc.esc_reset/esc_step,
%   modules/ratio_esc) in its NATIVE ratio semantics: measuredPower =
%   platform P_est, actualRatio = coaxial ratio measured from the post-
%   allocator rpm channels. The kernel never sees model internals
%   (optima, analytic gradients) and never touches PWM; safety stays in
%   the M0-B selector/monitor and the plant-side flag chain.
%
%   u = [t; v; P_e; E_e; att(6); pwm(8); rpm(8); flags(8); alloc_sat]
%       (35 elements; roadmap §3.1 contract -- M2 makes motor_pwm and
%       motor_rpm required inputs -- plus the allocator saturation bit,
%       which gates cost validity without touching the 8-bit flag bus)
%   Output: etaOut = [eta_ref; eta_act] (2x1; single block output so the
%       model side needs only single-port wiring; eta_act is the
%       diagnostic half, 0 (= unmeasurable) while any rotor of a pair is
%       below the armed-flight floor)
%
%   DEFAULTS MATTER: unlike m0c_vref_esc the default mode is 'fixed',
%   center0 = 1.0. The allocator sits in the pwm main path even in bypass
%   runs, so an unconfigured global must fall on the eta=1 identity fast
%   path (bypass regression difference-0). Trial scripts set the global
%   M2_ETA_PARAMS explicitly per run.
%
%   The block runs at an explicit 0.05 s sample time; this function
%   sample-holds on that grid internally, and a new simulation is detected
%   by time going backwards (compile-probe safe, M0-C pattern).
%
%   mode = 'm3' (docs/interfaces/M3_V_ETA_COORDINATION.md) adds M3
%   time-division arbitration: the role comes from the pure m3_schedule
%   each step; hold steps never call the kernel and still publish the
%   clean center through M2_ETA_APPLIED (M3 doc 3.2 -- it doubles as the
%   execution-evidence source). The fixed/esc branches are unchanged.

persistent st p mode center0 arb lastK
global M2_ETA_APPLIED M2_ETA_PARAMS
if isempty(st)
    st = []; p = []; mode = 'fixed'; center0 = 1.0; arb = []; lastK = Inf;
    M2_ETA_APPLIED = 1.0;            % safe default before the first update
end

Ts = 0.05;
t = u(1);
Pe = u(3);
flags = u(27:34);
satBit = u(35);
rpm = u(19:26);
omUp = rpm(5:8) * 2 * pi / 60;   % rpm -> rad/s (proportional to pwm-1000)
omLo = rpm(1:4) * 2 * pi / 60;
eta_act = ratioMeasurement(omUp, omLo);

k = floor((t + 1e-9) / Ts);
if k <= lastK
    ensureKernelPath();
    cfg = m2_config();
    mode = cfg.mode;
    center0 = cfg.center0;
    if strcmp(mode, 'm3')
        % M3 doc 2.4 legality, self-consistency half: mode='m3' with
        % arbitration disabled is undefined and fails loud here; the
        % cross-channel half (single-sided m3) is checked at trial entry
        % (m3_validate_channels). Validating through m3_schedule now
        % means every field is checked before the first step, not at it.
        arb = m3_arb_config();
        m3_schedule(0.0, arb);
    else
        arb = [];
    end
    c = ratioesc.config('Ts', Ts, 'lower', cfg.lower, 'upper', cfg.upper, ...
        'amplitude', cfg.amplitude, 'frequency', cfg.frequency, ...
        'hpOmega', cfg.hpOmega, 'lpOmega', cfg.lpOmega, 'gain', cfg.gain, ...
        'rateLimit', cfg.rateLimit, ...
        'initialRatio', cfg.center0, 'fixedReference', cfg.center0, ...
        'optimalRatio', cfg.center0, 'shiftedOptimalRatio', cfg.center0, ...
        'stage', 'esc', 'duration', 600);
    % module whitelist boundary: no plant map or optimizer truth crosses
    p = ratioesc.controller_config(c);
    st = ratioesc.esc_reset(p, cfg.center0, Pe);
end
lastK = k;

switch mode
    case 'fixed'
        % paired baseline: same model, same wiring, constant ratio
        eta_ref = center0;
    case 'esc'
        % esc_step's sampleOK additionally requires eta_act inside the
        % search band (eta_act = 0 pre-arm fails it by construction);
        % invalid samples (hard flag, saturation, slow rotors) hold the
        % last reference per module semantics
        valid = all(flags([1 2 3 4 6 7]) <= 0.5) && isfinite(Pe) && ...
            satBit < 0.5 && eta_act > 0;
        [eta_ref, st] = ratioesc.esc_step(st, Pe, eta_act, valid, p);
    case 'm3'
        % M3 time-division arbitration (M3 doc 2.1): hold steps never call
        % the kernel -- filter state frozen, output is the clean center,
        % and lastReference is synced to it so that an invalid first
        % resume step returns the center instead of a stale dithered
        % reference (the kernel's invalid path and the rate limiter both
        % consume lastReference as their base). The publish below then
        % exports the clean center as the applied ratio.
        if strcmp(m3_schedule(t, arb).eta, 'search')
            valid = all(flags([1 2 3 4 6 7]) <= 0.5) && isfinite(Pe) && ...
                satBit < 0.5 && eta_act > 0;
            [eta_ref, st] = ratioesc.esc_step(st, Pe, eta_act, valid, p);
        else
            eta_ref = st.center;
            st.lastReference = st.center;
            st.reinitialize = true;   % idempotent; consumed on resume
        end
    otherwise
        error('m2:UnknownMode', 'unknown mode %s', mode);
end
% publish the applied ratio for m2_eta_allocator / m2_alloc_diag (global
% handoff: keeps the 0.05 -> 0.004 dependency out of Simulink's task
% graph so the bypass regression stays bit-exact)
M2_ETA_APPLIED = eta_ref;
etaOut = [eta_ref; eta_act];
end

function r = ratioMeasurement(omUp, omLo)
%RATIOMEASUREMENT eta_actual from the upper/lower rpm groups; 0 while any
%   rotor is below the 20 rad/s armed-flight floor (no division risk; 0 is
%   outside the search band so the kernel holds, and it keeps the block
%   output finite for Simulink's compile probe, unlike NaN).
if all(omUp > 20) && all(omLo > 20)
    r = mean(omUp ./ omLo);
else
    r = 0.0;
end
end

function ensureKernelPath()
%ENSUREKERNELPATH make ratioesc resolvable regardless of the caller's
%   addpath state (M0-C pattern, isfolder-based resolution).
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
assert(~isempty(which('ratioesc.esc_step')), 'm2:KernelMissing', ...
    'ratio_esc module not found next to %s', mfilename('fullpath'));
end

function cfg = m2_config()
%M2_CONFIG Defaults for the M2 eta ESC; run scripts override by setting the
%   global M2_ETA_PARAMS struct (any subset of these fields). mode defaults
%   to 'fixed' at center0 = 1.0 (see header comment).
global M2_ETA_PARAMS
cfg = struct('mode', 'fixed', 'center0', 1.0, ...
    'lower', 0.75, 'upper', 1.25, 'amplitude', 0.02, ...
    'frequency', 0.25, 'hpOmega', 0.6, 'lpOmega', 0.6, ...
    'gain', 1e-4, 'rateLimit', 0.05);
if ~isempty(M2_ETA_PARAMS)
    f = fieldnames(M2_ETA_PARAMS);
    for k = 1:numel(f)
        cfg.(f{k}) = M2_ETA_PARAMS.(f{k});
    end
end
end
