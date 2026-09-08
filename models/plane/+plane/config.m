function c = config(varargin)
%PLANE.CONFIG P2 unified Plane physical-chain configuration.
%   P2 (06 方案 v1.2 / P2_T2_WORK_PLAN)：接口不变，内部实现由 proxy 升级为
%   物理化链条 —— 俯仰飞控内核（H6）+ 台架每电机功率合成（WP2）+ H9 涌现
%   上限 + battery_model_v1 电池链（WP1）。标定文件从 models/plane/data/
%   calibration/ 实时读取（bench_motor_mn1005_fit.json / battery_model_v1.json）。
%   proxy 时代字段（hover_power_W/speed_power_gain_W_per_mps2/eta_power_gain_W/
%   drag_power_gain_W_per_mps2/battery_full_V/battery_empty_V）保留仅为冻结的
%   T1 证据运行器兼容，P2 链不使用。
c=struct('schema_version','0.3','plane_model_id','plane_p2_phys_v1',...
 'power_model_id','bench_synth_v1',...
 'sample_time_s',0.01,'speed_tau_s',1.0,'eta_tau_s',0.5,...
 'speed_bounds_mps',[0 20],'speed_rate_mps2',2.0,'eta_bounds',[0.75 1.25],...
 'eta_rate_s',0.10,'circle_radius_m',20,'mass_kg',10.0,'gravity_mps2',9.81,...
 'hover_power_W',251,'speed_power_gain_W_per_mps2',1.8,'eta_power_gain_W',80,...
 'drag_power_gain_W_per_mps2',0.35,'battery_capacity_Ah',96,'battery_full_V',29.4,...
 'battery_empty_V',19.75,'battery_cutoff_V',19.6,'battery_resistance_ohm',0.021,...
 'aux_power_W',30,'battery_efficiency',0.95,'max_power_W',6000,...
 'altitude_m',10,'altitude_ref_m',10,'altitude_tol_m',1.0,'radial_tol_m',2.0,...
 'attitude_tol_rad',0.523,'yaw_rate_tol_radps',1.5);
% ---- P2 飞控内核（H6：指令级限幅为转写对象，物理上限涌现） ----
c.kp_speed=0.35;            % 速度误差->指令加速度（1/s）
c.pitch_tau_s=0.3;          % 俯仰一阶滞后 s（H6）
c.pitch_max_deg=25.0;       % 指令级俯仰限（声明值，H6）
c.az_cmd_mps2=0.0;          % 高度保持的垂直加速度需求（平台场景注入，算法接口无此字段）
% ---- P2 机体与废阻（H4 缺省，敏感性必做） ----
c.air_density_kgpm3=1.225;
c.cda_m2=0.30;              % 废阻面积缺省（H4，literature/model 等级）
% ---- P2 H3 前进比修正（动量理论诱导功率，2026-09-08 叶安拍板） ----
% 台架为静推数据（v_air=0）；前飞时桨盘诱导速度按动量理论下降：
%   vi(v)=sqrt((v/2)^2+T/(2*rho*A))-v/2, vi0=sqrt(T/(2*rho*A))
%   每桨节省 s=T*(vi0-vi(v))，从静态台架电功率中扣除（v=0 时 s=0，悬停不变）
c.prop_diameter_m=1.016;    % PAW 40X13.1R 桨径（40 寸），桨盘面积 pi*D^2/4
c.h3_induced_gain=1.0;      % 修正强度（敏感性旋钮：0.7/1.3 报告带，0=关闭）
% ---- P2 分配与每电机合成（eta 路径 v1.1，T24 方案 D3） ----
c.motor_count=8;c.arm_count=4;
c.eta_split_gain=0.55;       % s_up = 0.5 + gain*(1-eta)（v1.1: 0.3->0.55，谷底=模型输出）
c.coaxial_delta_base=0.111; % H5 缺省：效率 0.90 -> 下桨功率惩罚 0.111
c.coaxial_decay_kappa=0.5;  % H5 v1.1: delta(v)=delta0*(vi(v)/vi0)^kappa 前飞衰减
                             %      （敏感性带 0.3-1.0；悬停 v=0 严格=delta0）
                             % v1.0 回中项 coaxial_delta_split_gain 已废弃删除（谷底
                             % 不再人为钉在 eta=1，eta*(v) 成为模型预测输出）
% ---- P2 涌现转速上限（H9：台架域顶 1140 RPM@29.4V 随电压线性缩放，全程落在
%      已验证拟合域内、不外推；敏感性带上沿 42.2 RPM/V 即 1140@27V 口径） ----
c.ceiling_kn_rpm_per_V=1140/29.4;
% ---- P2 电池链（battery_model_v1，电芯级换算 n_ser/n_par） ----
c.battery_n_ser=7;c.battery_n_par=4;
c.battery_r_cell_ohm=0.012; % 电芯内阻（图像数字化粗估，literature/rough）
c.battery_resistance_ohm=c.battery_n_ser*c.battery_r_cell_ohm/c.battery_n_par; % 0.021
bat=local_load_json(fullfile(local_cal_dir,'battery_model_v1.json'));
c.battery_ocv_soc=bat.ocv_table.soc(:);
c.battery_ocv_cell_V=bat.ocv_table.ocv_V_cell(:);
% ---- P2 台架拟合（bench_motor_mn1005_fit.json，27V 块 T(n) 形状 + 分块 P(n;V)） ----
fit=local_load_json(fullfile(local_cal_dir,'bench_motor_mn1005_fit.json'));
fn=fieldnames(fit.blocks);vn=zeros(numel(fn),1);pc=cell(numel(fn),1);
for k=1:numel(fn)
    b=fit.blocks.(fn{k});vn(k)=b.v_nom;
    pc{k}=fliplr(reshape(b.p_elec.coef,1,[]));   % 列向量防御->行, 升序->降序（polyval）
end
[vn,ix]=sort(vn);c.bench_V_nom=vn;
c.bench_P_coef=cell2mat(pc(ix));      % 5x4，P[n W]=polyval(coef, n_krpm)
c.bench_T_coef_desc=fliplr(reshape(fit.blocks.(fn{ix(end)}).thrust.coef,1,[])); % 最高压块 T[n kgf]（升序->降序）
c.bench_rpm_domain=[fit.blocks.(fn{ix(1)}).rpm_min fit.blocks.(fn{ix(end)}).rpm_max];
if mod(numel(varargin),2)~=0,error('plane:Config','Use name/value pairs.');end
for k=1:2:numel(varargin),n=char(varargin{k});if ~isfield(c,n),error('plane:Config','Unknown parameter %s',n);end;c.(n)=varargin{k+1};end
assert(c.speed_tau_s>0&&c.eta_tau_s>0&&c.battery_capacity_Ah>0,'plane:Config','Invalid time/battery parameters.');
assert(c.speed_bounds_mps(1)<c.speed_bounds_mps(2)&&c.eta_bounds(1)<c.eta_bounds(2),'plane:Config','Invalid bounds.');
end
function p=local_cal_dir()
p=fullfile(fileparts(fileparts(mfilename('fullpath'))),'data','calibration');
end
function d=local_load_json(p)
assert(exist(p,'file')==2,'plane:Config','Calibration file missing: %s',p);
d=jsondecode(fileread(p));
end
