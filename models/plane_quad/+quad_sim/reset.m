function s = reset(c, initial)
%QUAD_SIM.RESET 轨 B 状态初始化(x8phys.reset 结构 4 桨移植; 可选 initial 覆盖)。
if nargin < 1 || isempty(c), c = quad_sim.config(); end
if nargin < 2, initial = struct(); end
s = struct('time_s',0, ...
    'position_ned_m',zeros(3,1),'velocity_ned_mps',zeros(3,1), ...
    'quaternion_bn',[1;0;0;0],'body_rate_radps',zeros(3,1), ...
    'soc',c.max_soc,'battery_charge_Ah',c.battery_capacity_Ah*c.max_soc, ...
    'energy_electrical_J',0, ...
    'last_pwm_us',ones(4,1)*c.pwm_min_us, ...
    'battery_cutoff',false, ...
    'rotor_omega_radps',zeros(4,1));
allowed = [fieldnames(s); {'attitude_rad'}];
names = fieldnames(initial);
for k = 1:numel(names)
    if ~ismember(names{k},allowed)
        error('quad_sim:Reset','Unknown initial field %s.',names{k});
    end
end
assert(~(isfield(initial,'attitude_rad') && isfield(initial,'quaternion_bn')), ...
    'quad_sim:Reset','Specify attitude_rad or quaternion_bn, not both.');
hasSoc = isfield(initial,'soc'); hasCharge = isfield(initial,'battery_charge_Ah');
if hasSoc && hasCharge
    assert(abs(initial.battery_charge_Ah-c.battery_capacity_Ah*initial.soc) < 1e-9, ...
        'quad_sim:Reset','Initial SOC and charge are inconsistent.');
elseif hasSoc
    initial.battery_charge_Ah = c.battery_capacity_Ah*initial.soc;
elseif hasCharge
    initial.soc = initial.battery_charge_Ah/c.battery_capacity_Ah;
end
names = fieldnames(initial);
for k = 1:numel(names)
    if ~strcmp(names{k},'attitude_rad'), s.(names{k}) = initial.(names{k}); end
end
s.soc = double(s.soc);
assert(isfinite(s.soc) && s.soc >= c.min_soc && s.soc <= c.max_soc, ...
    'quad_sim:Reset','Initial SOC is outside configured bounds.');
if isfield(initial,'attitude_rad')
    s.quaternion_bn = x8phys.euler_to_quaternion(initial.attitude_rad);
end
s.battery_charge_Ah = c.battery_capacity_Ah*s.soc;
s.quaternion_bn = double(s.quaternion_bn(:));
s.quaternion_bn = s.quaternion_bn/norm(s.quaternion_bn);
s.battery_cutoff = logical(s.battery_cutoff) || s.soc <= c.min_soc;
assert(isequal(size(s.rotor_omega_radps),[4 1]) && all(isfinite(s.rotor_omega_radps)) ...
    && all(s.rotor_omega_radps >= 0) && all(s.rotor_omega_radps <= c.omega_max_radps), ...
    'quad_sim:Reset','Initial rotor speed state is invalid (4x1, [0 omega_max]).');
end
