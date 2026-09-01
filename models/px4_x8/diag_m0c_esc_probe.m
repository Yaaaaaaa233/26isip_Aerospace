%DIAG_M0C_ESC_PROBE instrument the unit-test bowl loop: print center,
% gradient and demod diagnostics from ratioesc.esc_step over time.
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));
addpath(modelDir);
addpath(fullfile(wsRoot, '26isip_Aerospace', 'modules', 'ratio_esc'));
global M0C_ESC_PARAMS
M0C_ESC_PARAMS = struct('mode', 'esc', 'center0', 11.0, 'gain', 3e-3);
Ts = 0.05; r = exp(-Ts / 1.0);
v = 0.0;
st = [];
p = [];
for k = 1:800
    t = (k - 1) * Ts;
    P = 251 + 40 * (v - 8.0) ^ 2;
    if k == 1
        c = ratioesc.config('Ts', Ts, 'lower', 6.0, 'upper', 12.0, ...
            'amplitude', 0.3, 'frequency', 0.25, 'hpOmega', 0.6, ...
            'lpOmega', 0.6, 'gain', 6e-3, 'rateLimit', 2.0, ...
            'initialRatio', 11.0, 'fixedReference', 11.0, ...
            'optimalRatio', 11.0, 'shiftedOptimalRatio', 11.0, ...
            'stage', 'esc', 'duration', 600);
        p = ratioesc.controller_config(c);
        st = ratioesc.esc_reset(p, 11.0, P);
    end
    valid = isfinite(P) && isfinite(v);
    [vr, st, d] = ratioesc.esc_step(st, P, v, valid, p);
    if mod(k, 40) == 0
        fprintf('t %5.1f  vr %7.3f  center %7.3f  grad %9.2f  hp %9.2f  demod %9.2f  v %6.3f\n', ...
            t, vr, d.center, d.gradient, d.highpass, d.demodulated, v);
    end
    v = r * v + (1 - r) * vr;
end
