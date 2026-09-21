function [s, out] = step(s, cmd, dt, c)
%QUAD_SIM.STEP 轨 B 四旋翼油门正向链推进一步(x8phys.step 结构 4 桨移植 + 台架标定)。
% 输入: cmd.pwm_us(4), cmd.wind_ned_mps(3 可选); 输出字段名对齐 x8phys.step。
% 链条: PWM -> throttle -> w_target = throttle*KV*V(固定点电压耦合, 4 次迭代)
%   -> 一阶电机滞后 tau -> n[krpm] -> 推力=台架T(n), 力矩=cm*w^2
%   -> 机体几何合成 + 逐轴废阻 -> 四元数刚体推进
%   电功率 = Σ max(0, 台架P(n;V)*loadFactor_i - H3_i) + aux
%   loadFactor_i = 1 + Jgain*J_i^2 + axialGain*Jax_i(J = 桨盘边缘速度/桨尖速度)
%   -> 电池链(OCV-内阻, V*I=P 恒等式构造)。
if nargin < 4 || isempty(c), c = quad_sim.config(); end
validateattributes(dt,{'numeric'},{'scalar','nonnegative','finite'});
assert(isfield(cmd,'pwm_us'),'quad_sim:Input','cmd.pwm_us is required.');
pwmRequested = double(cmd.pwm_us(:));
assert(numel(pwmRequested) == 4 && all(isfinite(pwmRequested)), ...
    'quad_sim:Input','pwm_us must be 4 finite values.');
if isfield(cmd,'wind_ned_mps'), wind = double(cmd.wind_ned_mps(:));
else, wind = zeros(3,1); end
assert(numel(wind) == 3 && all(isfinite(wind)),'quad_sim:Input',...
    'wind_ned_mps must be a finite 3-vector.');
pwmLimited = min(max(pwmRequested,c.pwm_min_us),c.pwm_max_us);
cutoffAtStart = logical(s.battery_cutoff);
if cutoffAtStart, pwmApplied = ones(4,1)*c.pwm_min_us;
else, pwmApplied = pwmLimited; end
throttle = min(1,max(0,(pwmApplied-c.pwm_min_us)/(c.pwm_max_us-c.pwm_min_us)));
Rbn = x8phys.quaternion_rotation(s.quaternion_bn);
velocity0 = s.velocity_ned_mps;
relativeAirBody0 = Rbn'*(velocity0 - wind);
openVoltage = local_ocv(s.soc,c);
voltageGuess = openVoltage;
omega0 = s.rotor_omega_radps(:);
omega = omega0;
for k = 1:4
    omegaTarget = throttle.*(c.kv_rpm_per_V*voltageGuess)*2*pi/60;
    if dt > 0
        alpha = 1-exp(-dt/c.motor_tau_s);
        omega = omega0 + alpha.*(omegaTarget-omega0);
    else
        omega = omega0;
    end
    omega = min(c.omega_max_radps,max(0,omega));
    nKrpm = omega/(2*pi)*60/1000;
    Pc = local_p_coef(c,voltageGuess);
    tipSpeed = max(omega*c.rotor_radius_m,1);
    diskSpeed = hypot(relativeAirBody0(1),relativeAirBody0(2));
    Jadv = diskSpeed./tipSpeed;
    Jax = abs(relativeAirBody0(3))./tipSpeed;
    loadFactor = 1 + c.rotor_advance_power_gain*Jadv.^2 + ...
        c.rotor_axial_power_gain*Jax;
    thrustKgf = max(0,polyval(c.bench_T_coef_desc,nKrpm));
    thrustN = thrustKgf*c.gravity_mps2;
    sav = local_ind_saving(c,thrustN,diskSpeed);      % H3(与轨 A 同式, 边缘速度)
    Pmot = max(0,polyval(Pc,nKrpm).*loadFactor - sav);
    % 电气记账与轨 A/P2 同口径: 机身废阻功计电功率(标量 |v_air|^3 口径, CdA 取
    % body-x 值)。x8phys 原结构只计桨+aux —— 轨 B 若沿用会在速度域系统性偏低,
    % M4' 对拍(<=1.5%)要求两轨同账。
    vAirMag = norm(velocity0 - wind);
    PdragElec = 0.5*c.air_density_kgpm3*c.drag_coefficient(1)* ...
        c.drag_area_m2(1)*vAirMag^3;
    electricalDemand = sum(Pmot) + PdragElec + c.aux_power_W;
    maxBatteryPower = openVoltage^2/(4*c.battery_resistance_ohm);
    electricalPower = min(electricalDemand,maxBatteryPower);
    disc = max(0,openVoltage^2-4*c.battery_resistance_ohm*electricalPower);
    current = 2*electricalPower/max(openVoltage+sqrt(disc),eps);
    voltageGuess = max(0,openVoltage-c.battery_resistance_ohm*current);
end
thrust = thrustN;
torque = c.cm_Nm_per_rad2*omega.^2;
angle = c.rotor_angle_rad(:); direction = c.rotor_direction(:);
forceBody = [0;0;-sum(thrust)];
momentBody = [sum(-c.arm_m*sin(angle).*thrust); ...
              sum( c.arm_m*cos(angle).*thrust); ...
              sum(-direction.*torque)];
dragBody = -0.5*c.air_density_kgpm3.*c.drag_coefficient(:).* ...
    c.drag_area_m2(:).*relativeAirBody0.*abs(relativeAirBody0);
forceNed = Rbn*(forceBody+dragBody) + [0;0;c.mass_kg*c.gravity_mps2];
acceleration = forceNed/c.mass_kg;
bodyRate0 = s.body_rate_radps;
angularAccel = c.inertia_kgm2\(momentBody-cross(bodyRate0,c.inertia_kgm2*bodyRate0));
if dt > 0
    s.position_ned_m = s.position_ned_m + velocity0*dt + 0.5*acceleration*dt^2;
    s.velocity_ned_mps = velocity0 + acceleration*dt;
    s.body_rate_radps = bodyRate0 + angularAccel*dt;
    midRate = 0.5*(bodyRate0+s.body_rate_radps);
    s.quaternion_bn = x8phys.quaternion_advance(s.quaternion_bn,midRate,dt);
    s.time_s = s.time_s + dt;
end
powerLimited = electricalDemand > maxBatteryPower;
if cutoffAtStart
    electricalPower = 0; electricalDemand = 0; current = 0; voltage = openVoltage;
else
    disc = max(0,openVoltage^2-4*c.battery_resistance_ohm*electricalPower);
    current = 2*electricalPower/(openVoltage+sqrt(disc));
    voltage = max(0,openVoltage-c.battery_resistance_ohm*current);
    if dt > 0
        s.battery_charge_Ah = max(0,s.battery_charge_Ah-current*dt/3600);
        s.soc = min(c.max_soc,max(c.min_soc,s.battery_charge_Ah/c.battery_capacity_Ah));
    end
    if dt > 0 && (voltage <= c.battery_cutoff_V || s.soc <= c.min_soc)
        s.battery_cutoff = true;
    end
end
energyStep = electricalPower*dt;
s.energy_electrical_J = s.energy_electrical_J + energyStep;
if dt > 0
    s.last_pwm_us = pwmApplied;
    s.rotor_omega_radps = omega;
end
attitude = x8phys.quaternion_to_euler(s.quaternion_bn);
objectFlags = struct( ...
    'pwm_clipped', any(pwmRequested ~= pwmLimited), ...
    'pwm_at_edge', any(pwmApplied <= c.pwm_min_us+c.pwm_edge_us | ...
        pwmApplied >= c.pwm_max_us-c.pwm_edge_us), ...
    'rpm_at_edge', any(omega <= c.pwm_edge_us*c.omega_max_radps/ ...
        (c.pwm_max_us-c.pwm_min_us) | ...
        omega >= c.omega_max_radps*(1-c.pwm_edge_us/(c.pwm_max_us-c.pwm_min_us))), ...
    'power_limited', powerLimited, ...
    'low_voltage', voltage <= c.battery_cutoff_V, ...
    'battery_cutoff', logical(s.battery_cutoff));
out = struct('time_s',s.time_s, ...
    'position_ned_m',s.position_ned_m,'velocity_ned_mps',s.velocity_ned_mps, ...
    'quaternion_bn',s.quaternion_bn,'attitude_rad',attitude, ...
    'body_rate_radps',s.body_rate_radps,'wind_ned_mps',wind, ...
    'relative_air_velocity_mps',s.velocity_ned_mps-wind, ...
    'pwm_requested_us',pwmRequested,'pwm_applied_us',pwmApplied, ...
    'rotor_omega_radps',omega,'motor_rpm',omega*60/(2*pi), ...
    'n_krpm',omega/(2*pi)*60/1000, ...
    'rotor_thrust_N',thrust,'moment_body_Nm',momentBody, ...
    'acceleration_mps2',acceleration, ...
    'electrical_power_demand_W',electricalDemand, ...
    'electrical_power_W',electricalPower, ...
    'load_factor',loadFactor,'h3_saving_W',sav, ...
    'battery_voltage_V',voltage,'battery_current_A',current,'soc',s.soc, ...
    'energy_step_J',energyStep,'energy_electrical_J',s.energy_electrical_J, ...
    'energy_electrical_Wh',s.energy_electrical_J/3600, ...
    'object_flags',objectFlags, ...
    'power_source',c.power_source);
end
function v = local_ocv(soc,c)
cellV = interp1(c.battery_ocv_soc,c.battery_ocv_cell_V, ...
    min(c.max_soc,max(c.min_soc,double(soc))),'linear','extrap');
v = c.battery_n_ser*cellV;
end
function pc = local_p_coef(c,V)
V = min(max(V,c.bench_V_nom(1)),c.bench_V_nom(end));
i = find(c.bench_V_nom <= V,1,'last'); j = min(i+1,numel(c.bench_V_nom));
if i == j, pc = c.bench_P_coef(i,:); return; end
w = (V-c.bench_V_nom(i))/(c.bench_V_nom(j)-c.bench_V_nom(i));
pc = (1-w)*c.bench_P_coef(i,:) + w*c.bench_P_coef(j,:);
end
function [vi,vi0] = local_vi(c,T_N,vair)
% 动量理论诱导速度(H3 公用形状, 与轨 A 同式; T_N 允许 4x1 向量, vair 标量)
vi = zeros(size(T_N)); vi0 = zeros(size(T_N));
A = pi*(c.prop_diameter_m^2)/4; k = T_N/(2*c.air_density_kgpm3*A);
ok = (T_N > 0) & (vair > 0);
vi0(ok) = sqrt(k(ok));
vi(ok) = sqrt((vair/2)^2+k(ok))-vair/2;
end
function sv = local_ind_saving(c,T_N,vair)
[vi,vi0] = local_vi(c,T_N,vair);
sv = max(0,c.h3_induced_gain.*T_N.*(vi0-vi));   % 逐元素(T_N 为 4x1)
end
