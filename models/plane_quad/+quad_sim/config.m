function c = config(varargin)
%QUAD_SIM.CONFIG 轨 B 四旋翼油门正向链配置(Q2, QUAD_MIGRATION_PLAN 20260921 §4-Q2)。
%   融合(方案 §0 讨论第 2 条): x8phys 的结构(见 models/px4_x8/+x8phys, 冻结只读)
%     - PWM -> throttle -> 目标转速 = throttle*KV_eff*V(电压耦合), 一阶电机滞后 tau
%     - 四元数刚体(NED/FRD) + 逐轴废阻 + 动量/欧拉方程
%     - 前进比功率负载因子 loadFactor = 1 + Jgain*J^2(x8phys 声明级代理, 默认 3.0;
%       M4' 对拍模式置 0 —— 轨 A 无此项, 对拍须隔离结构差 vs 声明物理差)
%   + plane 链的台架标定(冻结 models/plane/data/calibration/ 只读):
%     - 推力图 T(n) = MN1005 台架拟合(替代 x8phys 的 ct*w^2 代理)
%     - 电功率图 P(n;V) = 分块台架拟合(替代 x8phys 的 linear+cubic 代理)
%     - H3 前飞诱导节省(动量理论, 与轨 A 同式)
%     - battery_model_v1 电池链(V*I=P 恒等式构造)
%   KV_eff = ceiling_kn_rpm_per_V: 满油门转速 = n_ce(V), 与 P2/轨 A 的 PWM 派生式
%   及 H9 涌现上限逐位同义(电压跌落 -> 上限线性缩放)。
%   口径: quad_placeholder(P4)——整机 10 kg 承 X8、MN1005/40寸/7S4P 占位, 老师参数
%   到位前全部数字不可引用为四旋翼真实结论。tau/Jgain/inertia/arm 为声明级占位。
c = struct('schema_version','0.3','plane_model_id','quad_sim_b_placeholder_v1',...
    'power_model_id','bench_synth_v1','power_source','quad_placeholder',...
    'mass_kg',10.0,'gravity_mps2',9.81,...
    'arm_m',0.65,'rotor_radius_m',0.508,...
    'rotor_angle_rad',[pi/4; 3*pi/4; 5*pi/4; 7*pi/4],...
    'rotor_direction',[1; -1; 1; -1],...
    'inertia_kgm2',diag([0.35 0.35 0.60]),...
    'pwm_min_us',1000,'pwm_max_us',2000,...
    'motor_tau_s',0.08,...                      % x8phys 代理值(声明级, 待老师参数)
    'rotor_advance_power_gain',3.0,...          % x8phys 声明级代理; M4' 对拍模式置 0
    'rotor_axial_power_gain',0.5,...            % 同上(轴向爬升功率项, 本批配平不用)
    'cm_Nm_per_rad2',1.0188e-4,...              % x8phys 代理(仅力矩/偏航通道)
    'air_density_kgpm3',1.225,...
    'drag_coefficient',[1.0; 1.0; 1.1],...
    'drag_area_m2',[0.30; 0.30; 0.273],...      % body-x 有效 CDA=0.30 对齐轨 A 标量
    'aux_power_W',30.0,'max_power_W',6000,...
    'prop_diameter_m',1.016,'h3_induced_gain',1.0,...
    'battery_capacity_Ah',96,'battery_n_ser',7,'battery_n_par',4,...
    'battery_cutoff_V',19.6,'battery_r_cell_ohm',0.012,...
    'omega_max_radps',2*pi/60*1163,...          % 30V 台架域顶安全硬帽(主上限=KV*V)
    'pwm_edge_us',5.0,...
    'max_soc',1.0,'min_soc',0.0,...
    'sample_time_s',0.01,...
    'speed_rate_mps2',2.0,'kp_speed',0.35,'pitch_max_deg',25.0,...
    'kvz_damp',0.5,'kp_att',25.0,'kd_att',10.0,'kp_yaw',2.0,...
    'placeholder',true,'placeholder_tag','quad_placeholder');
c.battery_resistance_ohm = c.battery_n_ser*c.battery_r_cell_ohm/c.battery_n_par;
% ---- 冻结标定只读加载(models/plane/data/calibration, 单一事实源) ----
calDir = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))),...
    'plane','data','calibration');
bat = local_load_json(fullfile(calDir,'battery_model_v1.json'));
c.battery_ocv_soc = bat.ocv_table.soc(:);
c.battery_ocv_cell_V = bat.ocv_table.ocv_V_cell(:);
fit = local_load_json(fullfile(calDir,'bench_motor_mn1005_fit.json'));
fn = fieldnames(fit.blocks); vn = zeros(numel(fn),1); pc = cell(numel(fn),1);
for k = 1:numel(fn)
    b = fit.blocks.(fn{k}); vn(k) = b.v_nom;
    pc{k} = fliplr(reshape(b.p_elec.coef,1,[]));
end
[vn,ix] = sort(vn); c.bench_V_nom = vn; c.bench_P_coef = cell2mat(pc(ix));
c.bench_T_coef_desc = fliplr(reshape(fit.blocks.(fn{ix(end)}).thrust.coef,1,[]));
c.ceiling_kn_rpm_per_V = 1140/29.4;             % H9 同源常数(台架域顶@29.4V)
c.kv_rpm_per_V = c.ceiling_kn_rpm_per_V;        % 满油门 = n_ce(V), 与 P2 派生式同义
if ~isempty(varargin) && isempty(varargin{1}), varargin(1) = []; end   % trim_run([],...) 约定
if ~isempty(varargin) && isstruct(varargin{1})   % struct 基底覆盖(在默认值之后合并)
    base = varargin{1}; varargin(1) = [];
    fn = fieldnames(base);
    for k = 1:numel(fn), c.(fn{k}) = base.(fn{k}); end
end
if mod(numel(varargin),2) ~= 0
    error('quad_sim:Config','Use name/value pairs.');
end
for k = 1:2:numel(varargin)
    name = char(varargin{k});
    if ~isfield(c,name), error('quad_sim:Config','Unknown parameter: %s',name); end
    c.(name) = varargin{k+1};
end
assert(c.motor_tau_s > 0 && c.kv_rpm_per_V > 0 && c.rotor_advance_power_gain >= 0, ...
    'quad_sim:Config','Invalid actuator/load parameters.');
assert(numel(c.rotor_angle_rad) == 4 && numel(c.rotor_direction) == 4, ...
    'quad_sim:Config','Four rotor angles and directions are required.');
end
function d = local_load_json(p)
assert(exist(p,'file') == 2,'quad_sim:Config','Calibration file missing: %s',p);
d = jsondecode(fileread(p));
end
