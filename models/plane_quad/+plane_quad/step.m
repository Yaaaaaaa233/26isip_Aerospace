function [s,out]=step(s,windSample,pathCommand,command,dt,c)
%PLANE_QUAD.STEP Advance quad-rotor reduced chain (Q2 track A) by one causal step.
%   骨架 = models/plane/+plane/step.m (P2, 冻结); 差异仅两处(方案 §4-Q2):
%     1) 4 电机单桨: T_i = T_need/4 各自受 T_ce(V) 封顶, 无 sUp/sLo 分配、
%        无 H5 共轴 delta——P_i = polyval(bench, n_i) - H3_saving(T_i, v_air);
%     2) eta 恒 1: command.eta_ref_applied 仍必填(接口字段保留), 值强制 1。
%   其余(风/路径/俯仰内核 H6/废阻前馈/饱和 shortfall/H9 上限/电池链/
%   能量记账/约束位/诊断字段名)与 P2 step 同式同序, 逐位可对拍。
%   口径: power_source='quad_placeholder'(P4 占位, 数字不可外引)。
 if nargin<6||isempty(c),c=plane_quad.config();end;validateattributes(dt,{'numeric'},{'scalar','nonnegative','finite'});
assert(isfield(command,'v_ref_applied_mps')&&isfield(command,'eta_ref_applied'),'plane_quad:Input','Applied v_ref and eta_ref are required.');
vRef=min(c.speed_bounds_mps(2),max(c.speed_bounds_mps(1),double(command.v_ref_applied_mps)));etaRef=1;   % eta 接口字段保留, 值恒 1
 assert(isfield(windSample,'wind_truth_ne_mps'),'plane_quad:Input','Physical wind truth is required by the quad object.');
 wind=double(windSample.wind_truth_ne_mps(:));assert(numel(wind)==2&&all(isfinite(wind)),'plane_quad:Input','wind_truth_ne_mps must be a finite 2-vector.');
 assert(isstruct(pathCommand)&&isfield(pathCommand,'trajectory_type')&&...
  isfield(pathCommand,'path_tangent_ne')&&isfield(pathCommand,'path_normal_ne')&&...
  isfield(pathCommand,'path_valid')&&logical(pathCommand.path_valid),...
  'plane_quad:Input','A valid PathCommand is required.');
 traj=char(pathCommand.trajectory_type);
 tangent=double(pathCommand.path_tangent_ne(:));
 assert(numel(tangent)==2&&all(isfinite(tangent))&&norm(tangent)>eps,...
  'plane_quad:Input','path_tangent_ne must be a finite nonzero 2-vector.');
 tangent=tangent/norm(tangent);normal=double(pathCommand.path_normal_ne(:));
 assert(numel(normal)==2&&all(isfinite(normal)),'plane_quad:Input','path_normal_ne must be a finite 2-vector.');
 if norm(normal)<eps,normal=[-tangent(2);tangent(1)];else,normal=normal/norm(normal);end
 turnSign=sign(tangent(1)*normal(2)-tangent(2)*normal(1));if turnSign==0,turnSign=1;end
 circleRadius=c.circle_radius_m;circleCenter=zeros(2,1);
 if strcmpi(traj,'circle')
  assert(isfield(pathCommand,'circle_radius_m')&&isfield(pathCommand,'circle_center_ne_m'),...
   'plane_quad:Input','Circle PathCommand requires radius and center.');
  circleRadius=double(pathCommand.circle_radius_m);circleCenter=double(pathCommand.circle_center_ne_m(:));
  assert(isscalar(circleRadius)&&isfinite(circleRadius)&&circleRadius>0&&...
   numel(circleCenter)==2&&all(isfinite(circleCenter)),'plane_quad:Input',...
   'Circle radius and center must be finite.');
 end
v0=s.v_ground_mps;eta0=1;etaTarget=1;
deta=0;                                                 % eta 恒 1, 无动态
% ---- 空速与废阻前馈(上一拍状态; 与 P2 同式) ----
if strcmpi(traj,'circle')
    tangentPre=turnSign*[-sin(s.phase_rad);cos(s.phase_rad)];
else
    tangentPre=tangent;
end
groundPrev=tangentPre*v0;airPrev=groundPrev-wind;airSpeedPrev=abs(dot(airPrev,tangentPre));
aDragFf=0.5*c.air_density_kgpm3*c.cda_m2*airSpeedPrev*abs(airSpeedPrev)/c.mass_kg;
% ---- 俯仰内核(H6, 与 P2 同式) ----
aFb=min(c.speed_rate_mps2,max(-c.speed_rate_mps2,c.kp_speed*(vRef-v0)));
thetaCmd=atan2(aFb+aDragFf,c.gravity_mps2);
thetaCmd=max(-deg2rad(c.pitch_max_deg),min(deg2rad(c.pitch_max_deg),thetaCmd));
theta=s.theta_rad+(thetaCmd-s.theta_rad)*(1-exp(-dt/c.pitch_tau_s));
% ---- 分配需求与 H9 涌现上限(4 电机单桨: Q2 核心差异处) ----
az=0;if isfield(c,'az_cmd_mps2')&&~isempty(c.az_cmd_mps2),az=double(c.az_cmd_mps2);end
Vprev=s.voltage_v;                                  % 上一拍端电压(因果)
nce=c.ceiling_kn_rpm_per_V*Vprev;                   % H9: n_max(V) [RPM]
TceKgf=max(0,polyval(c.bench_T_coef_desc,nce/1000));
TavailN=c.motor_count*TceKgf*c.gravity_mps2;
costh=max(cos(theta),0.3);
TneedN=c.mass_kg*(c.gravity_mps2+az)/costh;
satNow=(~s.cutoff)&&(TneedN>TavailN*(1+1e-12));
TmotKgf=min(TneedN/(c.motor_count*c.gravity_mps2),TceKgf);   % 每电机各自受 T_ce 封顶
TactN=c.motor_count*TmotKgf*c.gravity_mps2;
aKin=aFb;                                           % 废阻已由前馈补偿
if satNow                                           % 推力不足: 保高度优先, 切向 shortfall
  costhAct=min(1,c.mass_kg*(c.gravity_mps2+az)/TactN);
  aKin=min(aKin,c.gravity_mps2*tan(acos(max(0,min(1,costhAct)))));
end
if s.cutoff,aKin=-1.0;end                           % 截止: 旋翼停转
 if dt>0
 s.v_ground_mps=min(c.speed_bounds_mps(2),max(c.speed_bounds_mps(1),v0+aKin*dt));
 s.eta_actual=1;s.v_ref_mps=vRef;s.eta_ref=1;s.theta_rad=theta;
 if strcmpi(traj,'circle')
  s.phase_rad=mod(s.phase_rad+turnSign*s.v_ground_mps*dt/circleRadius,2*pi);
  s.position_ne_m=circleCenter+circleRadius*[cos(s.phase_rad);sin(s.phase_rad)];
  tangent=turnSign*[-sin(s.phase_rad);cos(s.phase_rad)];
 else
  s.position_ne_m=s.position_ne_m+tangent*s.v_ground_mps*dt;
 end
 s.time_s=s.time_s+dt;s.last_command=command;
end
ground=tangent*s.v_ground_mps;air=ground-wind;airSpeed=abs(dot(air,tangent));radialErr=0;if strcmpi(traj,'circle'),radialErr=norm(s.position_ne_m-circleCenter)-circleRadius;end
% ---- 每电机功率合成(4 电机单桨: 台架 P(n;V) - H3 诱导节省, 无共轴 delta) ----
nMot=max(0,local_n_of_t(c,TmotKgf));
Pc=local_p_coef(c,Vprev);
savMot=local_ind_saving(c,TmotKgf*c.gravity_mps2,airSpeed);    % H3 [W/桨]
Pmot1W=max(0,polyval(Pc,nMot)-savMot);
PmotW=c.motor_count*Pmot1W;
PdragW=0.5*c.air_density_kgpm3*c.cda_m2*airSpeed*airSpeed*abs(airSpeed); % H4
powerDemand=PmotW+max(PdragW,0)+c.aux_power_W;power=powerDemand;
openV=c.battery_n_ser*interp1(c.battery_ocv_soc,c.battery_ocv_cell_V,min(1,max(0,s.soc)));
flags=struct('pwm_saturation',false,'rpm_saturation',satNow,'attitude_excess',false,'yaw_rate_excess',false,'speed_miss',abs(s.v_ground_mps-vRef)>1,'power_anomaly',power>c.max_power_W,'signal_missing',false,'reserved',false);
 if s.cutoff
  power=0;current=0;voltage=c.battery_cutoff_V;flags.power_anomaly=true;
 else
  maxBatteryPower=openV^2/(4*c.battery_resistance_ohm);
  if power>maxBatteryPower,power=maxBatteryPower;flags.power_anomaly=true;end
  disc=max(0,openV^2-4*c.battery_resistance_ohm*power);
  current=2*power/(openV+sqrt(disc));voltage=max(0,openV-c.battery_resistance_ohm*current);
  if dt>0&&voltage<=c.battery_cutoff_V,s.cutoff=true;flags.power_anomaly=true;end
  if dt>0
   s.battery_charge_Ah=max(0,s.battery_charge_Ah-current*dt/3600);
   s.soc=s.battery_charge_Ah/c.battery_capacity_Ah;
   if s.soc<=0,s.cutoff=true;end
  end
 end
if dt>0,s.voltage_v=voltage;end                       % 下一拍的因果电压记忆
eStep=power*dt;s.energy_electrical_J=s.energy_electrical_J+eStep;s.energy_electrical_Wh=s.energy_electrical_J/3600;
 centripetalAcceleration=0;yawRate=0;roll=0;
 if strcmpi(traj,'circle'),centripetalAcceleration=s.v_ground_mps^2/circleRadius;yawRate=turnSign*s.v_ground_mps/circleRadius;roll=atan2(turnSign*centripetalAcceleration,c.gravity_mps2);end
 att=[roll;theta;atan2(ground(2),ground(1))];stateValid=all(isfinite([s.position_ne_m;s.v_ground_mps;s.eta_actual;power;s.soc]));
 motorRpm=zeros(c.motor_count,1);motorPw=zeros(c.motor_count,1);motorPwm=zeros(c.motor_count,1);
for i=1:c.motor_count
 motorRpm(i)=nMot*1000;motorPw(i)=Pmot1W;motorPwm(i)=1000+1000*min(1,nMot*1000/max(nce,eps));
end
 out=struct('schema_version',c.schema_version,'plane_model_id',c.plane_model_id,'time_s',s.time_s,'position_ne_m',s.position_ne_m,'altitude_m',s.altitude_m,'ground_velocity_ne_mps',ground,'air_velocity_ne_mps',air,'tangential_ground_speed_mps',dot(ground,tangent),'attitude_rpy_rad',att,'body_rate_rpy_radps',[0;0;yawRate],'radial_error_m',radialErr,'centripetal_acceleration_mps2',centripetalAcceleration,'power_demand_w',powerDemand,'power_w',power,'power_sample_time_s',s.time_s,'power_source',c.power_source,'power_model_id',c.power_model_id,'power_valid',stateValid,'voltage_v',voltage,'current_a',current,'soc',s.soc,'motor_pwm_us',motorPwm,'motor_rpm',motorRpm,'motor_power_w',motorPw,'thrust_total_demand_n',TneedN,'thrust_total_actual_n',TactN,'thrust_ceiling_n',TavailN,'rpm_ceiling',nce,'pitch_rad',theta,'command_accel_mps2',aFb,'actual_accel_mps2',aKin,'rpm_saturation',satNow,'open_circuit_V',openV,'constraint_flags',flags,'state_valid',stateValid,'eta_actual',s.eta_actual,'v_ref_applied_mps',s.v_ref_mps,'eta_ref_applied',s.eta_ref,'path_phase_rad',s.phase_rad,'energy_electrical_J',s.energy_electrical_J,'energy_electrical_Wh',s.energy_electrical_Wh);
end
function n=local_n_of_t(c,t)
% 台架 T(n) 反解(正根); t 单位 kgf
b=c.bench_T_coef_desc;
r=roots([b(1),b(2),b(3)-t]);r=r(imag(r)<1e-9&real(r)>0);n=min(real(r));
if isempty(n)||~isfinite(n),n=0;end
end
function [vi,vi0]=local_vi(c,T_N,vair)
% 动量理论诱导速度(H3 公用形状, 与 P2 同式)
vi=0;vi0=0;
if T_N<=0||vair<=0,return;end
A=pi*(c.prop_diameter_m^2)/4;k=T_N/(2*c.air_density_kgpm3*A);
vi0=sqrt(k);vi=sqrt((vair/2)^2+k)-vair/2;
end
function s=local_ind_saving(c,T_N,vair)
% H3 动量理论诱导功率节省 [W/桨](与 P2 同式; v=0 严格 0, 悬停=台架值)
[vi,vi0]=local_vi(c,T_N,vair);
s=max(0,c.h3_induced_gain*T_N*(vi0-vi));
end
function pc=local_p_coef(c,V)
% 分块 P(n;V): 电压块间线性插值(与 P2 同式)
V=min(max(V,c.bench_V_nom(1)),c.bench_V_nom(end));
i=find(c.bench_V_nom<=V,1,'last');j=min(i+1,numel(c.bench_V_nom));
if i==j,pc=c.bench_P_coef(i,:);return;end
w=(V-c.bench_V_nom(i))/(c.bench_V_nom(j)-c.bench_V_nom(i));
pc=(1-w)*c.bench_P_coef(i,:)+w*c.bench_P_coef(j,:);
end
