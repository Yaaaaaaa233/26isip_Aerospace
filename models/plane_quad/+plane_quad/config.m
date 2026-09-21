function c = config(varargin)
%PLANE_QUAD.CONFIG 四旋翼降阶链配置(Q2 轨 A, QUAD_MIGRATION_PLAN 20260921 §4-Q2)。
%   骨架复用 models/plane P2 链(冻结零改动), 差异按方案:
%     - 4 电机单桨: 删共轴上下桨分配与 H5 干扰项(对应参数键不存在, M3 静态
%       扫描门的对象);
%     - eta 恒 1: 接口字段保留(command.eta_ref_applied 仍必填), 值被强制 1;
%     - 保留: H6 俯仰内核 / H3 前飞诱导节省 / H4 废阻 / H9 涌现转速上限 /
%       battery_model_v1 电池链 / MN1005 台架分块拟合(与 P2 同一标定文件, 只读);
%     - 占位: 整机质量暂承 X8 10 kg, 电机/桨/电池沿用 MN1005+7S4P——老师参数
%       到位前全部数字挂 quad_placeholder 等级, 不可引用为四旋翼真实结论(P4)。
%   台架/电池标定从冻结的 models/plane/data/calibration/ 只读加载(单一事实源)。
c=struct('schema_version','0.3','plane_model_id','quad_placeholder_v1',...
 'power_model_id','bench_synth_v1','power_source','quad_placeholder',...
 'sample_time_s',0.01,'speed_bounds_mps',[0 20],'speed_rate_mps2',2.0,...
 'eta_bounds',[1 1],...
 'circle_radius_m',20,'mass_kg',10.0,'gravity_mps2',9.81,...
 'battery_capacity_Ah',96,'battery_cutoff_V',19.6,'battery_resistance_ohm',0.021,...
 'aux_power_W',30,'max_power_W',6000,...
 'altitude_m',10,'altitude_ref_m',10,'altitude_tol_m',1.0,'radial_tol_m',2.0,...
 'attitude_tol_rad',0.523,'yaw_rate_tol_radps',1.5);
% ---- H6 俯仰内核(与 P2 同参) ----
c.kp_speed=0.35;
c.pitch_tau_s=0.3;
c.pitch_max_deg=25.0;
c.az_cmd_mps2=0.0;
% ---- H4 废阻 / H3 前飞诱导(与 P2 同参, 占位口径) ----
c.air_density_kgpm3=1.225;
c.cda_m2=0.30;
c.prop_diameter_m=1.016;    % PAW 40X13.1R(占位: 四旋翼实桨待老师参数)
c.h3_induced_gain=1.0;
% ---- 电机拓扑(Q2 核心差异): 4 电机单桨, 无共轴 ----
c.motor_count=4;
% ---- H9 涌现转速上限(与 P2 同参) ----
c.ceiling_kn_rpm_per_V=1140/29.4;
% ---- 电池链(battery_model_v1, 与 P2 同参占位) ----
c.battery_n_ser=7;c.battery_n_par=4;
c.battery_r_cell_ohm=0.012;
c.battery_resistance_ohm=c.battery_n_ser*c.battery_r_cell_ohm/c.battery_n_par;
% ---- 占位声明(P4) ----
c.placeholder=true;
c.placeholder_tag='quad_placeholder';
c.placeholder_note=['整机质量暂承X8 10kg; 电机MN1005/桨40寸/电池7S4P 沿用小学期占位; ' ...
 '老师参数到位前全部数字不可引用为四旋翼真实节能/实飞结论(方案P4)'];
% ---- 标定加载(冻结源只读: models/plane/data/calibration/) ----
bat=local_load_json(fullfile(local_cal_dir,'battery_model_v1.json'));
c.battery_ocv_soc=bat.ocv_table.soc(:);
c.battery_ocv_cell_V=bat.ocv_table.ocv_V_cell(:);
fit=local_load_json(fullfile(local_cal_dir,'bench_motor_mn1005_fit.json'));
fn=fieldnames(fit.blocks);vn=zeros(numel(fn),1);pc=cell(numel(fn),1);
for k=1:numel(fn)
    b=fit.blocks.(fn{k});vn(k)=b.v_nom;
    pc{k}=fliplr(reshape(b.p_elec.coef,1,[]));
end
[vn,ix]=sort(vn);c.bench_V_nom=vn;
c.bench_P_coef=cell2mat(pc(ix));      % 5x4, P[n W]=polyval(coef, n_krpm)
c.bench_T_coef_desc=fliplr(reshape(fit.blocks.(fn{ix(end)}).thrust.coef,1,[]));
c.bench_rpm_domain=[fit.blocks.(fn{ix(1)}).rpm_min fit.blocks.(fn{ix(end)}).rpm_max];
if mod(numel(varargin),2)~=0,error('plane_quad:Config','Use name/value pairs.');end
for k=1:2:numel(varargin),n=char(varargin{k});if ~isfield(c,n),error('plane_quad:Config','Unknown parameter %s',n);end;c.(n)=varargin{k+1};end
assert(c.motor_count==4,'plane_quad:Config','quad chain requires motor_count=4.');
assert(c.speed_bounds_mps(1)<c.speed_bounds_mps(2),'plane_quad:Config','Invalid bounds.');
assert(c.battery_capacity_Ah>0,'plane_quad:Config','Invalid battery capacity.');
end
function p=local_cal_dir()
% 冻结标定只读: 本包位于 models/plane_quad/+plane_quad -> 3 级上级 = models
p=fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))),...
    'plane','data','calibration');
end
function d=local_load_json(p)
assert(exist(p,'file')==2,'plane_quad:Config','Calibration file missing: %s',p);
d=jsondecode(fileread(p));
end
