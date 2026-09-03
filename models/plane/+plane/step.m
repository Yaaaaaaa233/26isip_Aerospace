function [s,out]=step(s,windSample,pathCommand,command,dt,c)
%PLANE.STEP Advance unified Plane proxy by one causal time step.
 if nargin<6||isempty(c),c=plane.config();end;validateattributes(dt,{'numeric'},{'scalar','nonnegative','finite'});
assert(isfield(command,'v_ref_applied_mps')&&isfield(command,'eta_ref_applied'),'plane:Input','Applied v_ref and eta_ref are required.');
vRef=min(c.speed_bounds_mps(2),max(c.speed_bounds_mps(1),double(command.v_ref_applied_mps)));etaRef=min(c.eta_bounds(2),max(c.eta_bounds(1),double(command.eta_ref_applied)));
 assert(isfield(windSample,'wind_truth_ne_mps'),'plane:Input','Physical wind truth is required by the Plane object.');
 wind=double(windSample.wind_truth_ne_mps(:));assert(numel(wind)==2&&all(isfinite(wind)),'plane:Input','wind_truth_ne_mps must be a finite 2-vector.');
 assert(isstruct(pathCommand)&&isfield(pathCommand,'trajectory_type')&&...
  isfield(pathCommand,'path_tangent_ne')&&isfield(pathCommand,'path_normal_ne')&&...
  isfield(pathCommand,'path_valid')&&logical(pathCommand.path_valid),...
  'plane:Input','A valid PathCommand is required.');
 traj=char(pathCommand.trajectory_type);
 tangent=double(pathCommand.path_tangent_ne(:));
 assert(numel(tangent)==2&&all(isfinite(tangent))&&norm(tangent)>eps,...
  'plane:Input','path_tangent_ne must be a finite nonzero 2-vector.');
 tangent=tangent/norm(tangent);normal=double(pathCommand.path_normal_ne(:));
 assert(numel(normal)==2&&all(isfinite(normal)),'plane:Input','path_normal_ne must be a finite 2-vector.');
 if norm(normal)<eps,normal=[-tangent(2);tangent(1)];else,normal=normal/norm(normal);end
 turnSign=sign(tangent(1)*normal(2)-tangent(2)*normal(1));if turnSign==0,turnSign=1;end
 circleRadius=c.circle_radius_m;circleCenter=zeros(2,1);
 if strcmpi(traj,'circle')
  assert(isfield(pathCommand,'circle_radius_m')&&isfield(pathCommand,'circle_center_ne_m'),...
   'plane:Input','Circle PathCommand requires radius and center.');
  circleRadius=double(pathCommand.circle_radius_m);circleCenter=double(pathCommand.circle_center_ne_m(:));
  assert(isscalar(circleRadius)&&isfinite(circleRadius)&&circleRadius>0&&...
   numel(circleCenter)==2&&all(isfinite(circleCenter)),'plane:Input',...
   'Circle radius and center must be finite.');
 end
 v0=s.v_ground_mps;eta0=s.eta_actual;vTarget=vRef;etaTarget=etaRef;
 dvLag=(vTarget-v0)*(1-exp(-dt/c.speed_tau_s));
 detaLag=(etaTarget-eta0)*(1-exp(-dt/c.eta_tau_s));
 dv=max(-c.speed_rate_mps2*dt,min(c.speed_rate_mps2*dt,dvLag));
 deta=max(-c.eta_rate_s*dt,min(c.eta_rate_s*dt,detaLag));
 if dt>0
  s.v_ground_mps=v0+dv;s.eta_actual=eta0+deta;s.v_ref_mps=vRef;s.eta_ref=etaRef;
  if strcmpi(traj,'circle')
   s.phase_rad=mod(s.phase_rad+turnSign*s.v_ground_mps*dt/circleRadius,2*pi);
   s.position_ne_m=circleCenter+circleRadius*[cos(s.phase_rad);sin(s.phase_rad)];
   tangent=turnSign*[-sin(s.phase_rad);cos(s.phase_rad)];
  else
   s.position_ne_m=s.position_ne_m+tangent*s.v_ground_mps*dt;
  end
  s.time_s=s.time_s+dt;s.last_command=command;
 end
ground=tangent*s.v_ground_mps;air=ground-wind;airSpeed=norm(air);radialErr=0;if strcmpi(traj,'circle'),radialErr=norm(s.position_ne_m-circleCenter)-circleRadius;end
% Joint proxy P(v_air,eta): speed/eta slices retain existing proxy baselines.
 pEta=c.eta_power_gain_W*(s.eta_actual-1)^2;pSpeed=c.speed_power_gain_W_per_mps2*(airSpeed-6)^2;pDrag=c.drag_power_gain_W_per_mps2*airSpeed^2;
 powerDemand=c.hover_power_W+pSpeed+pEta+pDrag+c.aux_power_W;power=powerDemand;
 openV=c.battery_empty_V+(c.battery_full_V-c.battery_empty_V)*s.soc;flags=struct('pwm_saturation',false,'rpm_saturation',false,'attitude_excess',false,'yaw_rate_excess',false,'speed_miss',abs(s.v_ground_mps-vRef)>1,'power_anomaly',power>c.max_power_W,'signal_missing',false,'reserved',false);
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
eStep=power*dt;s.energy_electrical_J=s.energy_electrical_J+eStep;s.energy_electrical_Wh=s.energy_electrical_J/3600;
 centripetalAcceleration=0;yawRate=0;roll=0;
 if strcmpi(traj,'circle'),centripetalAcceleration=s.v_ground_mps^2/circleRadius;yawRate=turnSign*s.v_ground_mps/circleRadius;roll=atan2(turnSign*centripetalAcceleration,c.gravity_mps2);end
 att=[roll;0;atan2(ground(2),ground(1))];stateValid=all(isfinite([s.position_ne_m;s.v_ground_mps;s.eta_actual;power;s.soc]));
 out=struct('schema_version',c.schema_version,'plane_model_id',c.plane_model_id,'time_s',s.time_s,'position_ne_m',s.position_ne_m,'altitude_m',s.altitude_m,'ground_velocity_ne_mps',ground,'air_velocity_ne_mps',air,'tangential_ground_speed_mps',dot(ground,tangent),'attitude_rpy_rad',att,'body_rate_rpy_radps',[0;0;yawRate],'radial_error_m',radialErr,'centripetal_acceleration_mps2',centripetalAcceleration,'power_demand_w',powerDemand,'power_w',power,'power_sample_time_s',s.time_s,'power_source','proxy','power_model_id',c.power_model_id,'power_valid',stateValid,'voltage_v',voltage,'current_a',current,'soc',s.soc,'motor_pwm_us',nan(8,1),'motor_rpm',nan(8,1),'constraint_flags',flags,'state_valid',stateValid,'eta_actual',s.eta_actual,'v_ref_applied_mps',s.v_ref_mps,'eta_ref_applied',s.eta_ref,'path_phase_rad',s.phase_rad,'energy_electrical_J',s.energy_electrical_J,'energy_electrical_Wh',s.energy_electrical_Wh);
end
