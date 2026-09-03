function flags = map_flags(out, platform)
%X8PHYS.MAP_FLAGS Map object diagnostics to repository M0-A/M0-B flags.
if nargin < 2, platform = struct(); end
flags=zeros(8,1); of=out.object_flags;
flags(1)=double(of.pwm_clipped||of.pwm_at_edge); flags(2)=double(of.rpm_at_edge);
attTol=0.523; yawTol=1.5; speedTol=1.0; pMax=1500;
if isfield(platform,'attitude_tol_rad'),attTol=platform.attitude_tol_rad;end
if isfield(platform,'yaw_rate_tol_radps'),yawTol=platform.yaw_rate_tol_radps;end
if isfield(platform,'speed_tol_mps'),speedTol=platform.speed_tol_mps;end
if isfield(platform,'max_power_W'),pMax=platform.max_power_W;end
flags(3)=double(any(abs(out.attitude_rad(1:2))>attTol)); flags(4)=double(abs(out.body_rate_radps(3))>yawTol);
observed=[out.velocity_ned_mps;out.attitude_rad;out.electrical_power_W;out.soc];
if isfield(platform,'v_ref_mps')
    flags(5)=double(abs(norm(out.velocity_ned_mps(1:2))-platform.v_ref_mps)>speedTol);
    observed=[observed;platform.v_ref_mps];
end
flags(6)=double(of.power_limited||of.low_voltage||out.electrical_power_W>pMax);
optionalFields={'time_s','energy_electrical_J','battery_voltage_V', ...
    'battery_current_A','rotor_omega_radps','pwm_applied_us'};
for k=1:numel(optionalFields)
    if isfield(out,optionalFields{k})
        value=out.(optionalFields{k});
        observed=[observed;value(:)]; %#ok<AGROW>
    end
end
flags(7)=double(~all(isfinite(observed))); flags(8)=0;
end
