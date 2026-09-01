function pwm_out = m2_eta_allocator(pwm_in)
%M2_ETA_ALLOCATOR Constrained coaxial-ratio allocator (M2, fast-layer side).
%   PWM-domain post-mixer instantiation of the roadmap "X8 Control
%   Allocator": pwm_in is the untouched 8-channel mixer output (uint16-
%   valued, 1000..2000 us) which fully encodes the total-thrust / roll /
%   pitch / yaw commands. Each coaxial pair's squared speeds are rescaled
%   with the pair sum -- and therefore total thrust, roll moment and pitch
%   moment -- preserved exactly in the continuous domain. Pairing
%   (M2_ETA_ALLOCATOR.md section 2): lower = motors 1..4, upper = motors
%   5..8 (same arm angle, opposite spin); eta = omega_upper / omega_lower
%   with the plant map omega = (pwm - 1000)/1000 * omega_max.
%
%   The CURRENT eta reference is read from the global M2_ETA_APPLIED,
%   written by m2_eta_esc on its 0.05 s grid (default 1.0). It is
%   deliberately NOT a block input line: an explicit 0.05 -> 0.004 rate
%   dependency into the pwm main path changes Simulink's task scheduling
%   and breaks the bit-exact bypass regression (2026-09-01 E1 experiment,
%   M2_ETA_ALLOCATOR.md section 5); the global handoff keeps the pwm path
%   single-rate with ZOH-equivalent semantics.
%
%   |eta - 1| < 1e-12 takes a bit-exact passthrough fast path so the
%   bypass regression stays difference-0. Output: pwm_out, 8x1 DOUBLE
%   holding exact integer values in [1000,2000] (Interpreted MATLAB Fcn
%   blocks only accept double outputs; the model converts to uint16 via
%   the 'M2 Pwm Uint16' DataTypeConversion, which is lossless on these
%   integer values).
%   Pure function: no persistent state, no knowledge of a plant optimum.

global M2_ETA_APPLIED
if isempty(M2_ETA_APPLIED) || ~isfinite(M2_ETA_APPLIED)
    eta = 1.0;                       % safe default: passthrough identity
else
    eta = min(1.25, max(0.75, double(M2_ETA_APPLIED)));
end

PWM_MIN = 1000.0;
PWM_MAX = 2000.0;

if abs(eta - 1.0) < 1e-12
    pwm_out = double(pwm_in);
    return;
end

pwmIn = min(PWM_MAX, max(PWM_MIN, double(pwm_in)));
om = pwmIn - PWM_MIN;             % 0..1000 rad/s
cL = om(1:4) .^ 2;
cU = om(5:8) .^ 2;
cSum = cL + cU;                   % preserved per pair by construction
cL2 = cSum / (1.0 + eta * eta);
cU2 = eta * eta * cL2;
pwm_out = min(PWM_MAX, max(PWM_MIN, ...
    [PWM_MIN + sqrt(cL2); PWM_MIN + sqrt(cU2)]));
end
