function diagOut = m2_alloc_diag(pwm_in)
%M2_ALLOC_DIAG M2 allocator diagnostics on the same input (single output).
%   pwm_in is identical to m2_eta_allocator's input: the 8-channel mixer
%   output. The current eta reference is read from the global
%   M2_ETA_APPLIED (see m2_eta_allocator for why it is not an input line).
%   Returns diagOut = [sat; dmz]:
%     sat : 1 when eta was clamped into [0.75,1.25] or the re-mapped
%           commands hit the [1000,2000] pwm rails (gates M2 ESC validity;
%           the project 8-bit flag bus and its hard list stay untouched)
%     dmz : exact yaw-moment change vs the eta=1 mixer output, N*m
%           (M_z(pair) = dir_L * C_M * (c_upper - c_lower)); zero for
%           balanced commands, absorbed by the existing yaw inner loop
%   Pure function; the allocation math mirrors m2_eta_allocator.

global M2_ETA_APPLIED
if isempty(M2_ETA_APPLIED) || ~isfinite(M2_ETA_APPLIED)
    etaRef = 1.0;
else
    etaRef = double(M2_ETA_APPLIED);
end
PWM_MIN = 1000.0;
PWM_MAX = 2000.0;
C_M = 2.51e-7;                    % plant reaction-torque coefficient
DIR_L = [-1.0; 1.0; -1.0; 1.0];   % spin sign of lower motors 1..4

eta = min(1.25, max(0.75, etaRef));
sat = abs(etaRef - eta) > 1e-12;
dmz = 0.0;

if ~sat && abs(eta - 1.0) < 1e-12
    diagOut = [sat; dmz];
    return;
end

pwmIn = min(PWM_MAX, max(PWM_MIN, double(pwm_in)));
om = pwmIn - PWM_MIN;
cL = om(1:4) .^ 2;
cU = om(5:8) .^ 2;
cSum = cL + cU;
cL2 = cSum / (1.0 + eta * eta);
cU2 = eta * eta * cL2;
pwmNew = [PWM_MIN + sqrt(cL2); PWM_MIN + sqrt(cU2)];
if any(pwmNew < PWM_MIN | pwmNew > PWM_MAX)
    sat = true;
end
dmz = C_M * sum(DIR_L .* ((cU2 - cL2) - (cU - cL)));
diagOut = [sat; dmz];
end
