function v_ref = m0c_vref_esc(u)
%M0C_VREF_ESC M0-C optimizer reference interface (roadmap contract).
%   Wraps the Git repository module kernel (ratioesc.esc_reset/esc_step in
%   modules/ratio_esc) behind the M0-C contract: inputs are ONLY
%   t, v, P_e, E_e, attitude(6), constraint_flags(8); the single output is
%   v_ref. The kernel never sees model internals (optima, analytic
%   gradients, offline search results) and never touches PWM; the safety
%   layer stays in the M0-B reference selector / monitor.
%
%   u = [t, v, P_e, E_e, att(6), flags(8)]   (18 elements, see M0C doc §2.2)
%   yaw_rate is attitude(6); E_e is logged for future algorithms, the
%   current kernel does not use it.
%
%   The block inherits the input rate; this function sample-holds on the
%   Ts = 0.05 s grid internally (update when floor(t/Ts) increments), so
%   no multi-rate transitions are inserted in the model.
%
%   Trial scripts configure a run through the global M0C_ESC_PARAMS
%   struct (see m0c_config); a new simulation is detected by time going
%   backwards and re-snapshots the configuration and ESC state.

persistent st p mode center0 lastK
if isempty(st)
    st = []; p = []; mode = 'esc'; center0 = 9.0; lastK = Inf;
end

Ts = 0.05;
t = u(1); v = u(2); Pe = u(3); flags = u(11:18);
k = floor((t + 1e-9) / Ts);

% new simulation (or the compile-phase probe call Simulink makes to infer
% the output width): re-read config and reset the ESC. With the block at an
% explicit 0.05 s sample time, k strictly increases within one simulation,
% so <= only fires for the compile probe and each new run's first hit.
if k <= lastK
    ensureKernelPath();
    cfg = m0c_config();
    mode = cfg.mode;
    center0 = cfg.center0;
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
        % paired baseline: same model, same wiring, constant reference
        v_ref = center0;
    case 'esc'
        % esc_step's sampleOK additionally requires v inside the search
        % band, so the wrapper holds center0 until the vehicle climbs into
        % it; invalid samples (hard flag, NaN, out of band) hold the last
        % reference and reinitialize the filters, per module semantics.
        valid = all(flags([1 2 3 4 6 7]) <= 0.5) && isfinite(Pe) && ...
            isfinite(v);
        [v_ref, st] = ratioesc.esc_step(st, Pe, v, valid, p);
    otherwise
        error('m0c:UnknownMode', 'unknown mode %s', mode);
end
end

function ensureKernelPath()
%ENSUREKERNELPATH make ratioesc resolvable regardless of the caller's
%   addpath state: the Git module lives at <workspace>/26isip_Aerospace/
%   modules/ratio_esc, located relative to this file.
if isempty(which('ratioesc.esc_step'))
    adapterDir = fileparts(mfilename('fullpath'));
    wsRoot = fileparts(fileparts(adapterDir));
    addpath(fullfile(wsRoot, '26isip_Aerospace', 'modules', 'ratio_esc'));
end
assert(~isempty(which('ratioesc.esc_step')), 'm0c:KernelMissing', ...
    'ratio_esc module not found next to %s', mfilename('fullpath'));
end

function cfg = m0c_config()
%M0C_CONFIG Defaults for the M0-C speed ESC trial; run scripts override by
% setting the global M0C_ESC_PARAMS struct (any subset of these fields).
global M0C_ESC_PARAMS
cfg = struct('mode', 'esc', 'center0', 9.0, ...
    'lower', 6.0, 'upper', 12.0, 'amplitude', 0.3, 'frequency', 0.25, ...
    'hpOmega', 0.6, 'lpOmega', 0.6, 'gain', 6e-3, 'rateLimit', 2.0);
if ~isempty(M0C_ESC_PARAMS)
    f = fieldnames(M0C_ESC_PARAMS);
    for k = 1:numel(f)
        cfg.(f{k}) = M0C_ESC_PARAMS.(f{k});
    end
end
end
