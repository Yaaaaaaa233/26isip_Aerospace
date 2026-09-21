function [pwm, diag] = ctrl(s, out, vRef, c)
%QUAD_SIM.CTRL 轨 B 内环控制器(v_ref -> 4xPWM 的"飞控模拟")。
% 传感器集 = 实机 FC 可观测量: 地速(GPS/INS)、姿态/角速度(IMU)、端电压(V 传感器);
% 不读真功率/真风。结构与轨 A 的 H6 内核同型, 保证 M4' 对拍在控制器层面公平:
%   垂直通道:  az_fb = -kvz*vz(NED), T_tot = m(g+az_fb)/max(cos(pitch),0.3)
%   前向通道:  aFb = clamp(kp*(vRef-v), +-rate), aDrag_ff = rho*CDA*v|v|/2m
%              thetaA = atan2(aFb+aDrag_ff, g) 限 +-25deg; NED321 中加速前飞
%              = 低头 = 负俯仰 -> pitchCmd = -thetaA
%   姿态 PD:   M_cmd = [kp(0-roll)-kd*p; kp(pitchCmd-pitch)-kd*q; kpY*(0-r)]
%   混控:      A(3x4) = [-arm*sin(a); arm*cos(a); -dir*km_hover] 线性化在悬停,
%              thrust_i = T_tot/4 + pinv(A)*M_cmd -> 台架 T^-1 -> RPM -> 油门
%   油门->PWM:  pwm_i = 1000+1000*RPM_i/(KV*V_hat)(与植物正向图逐位互逆, 非饱和域)
if nargin < 4 || isempty(c), c = quad_sim.config(); end
v = norm(out.velocity_ned_mps(1:2));
vz = out.velocity_ned_mps(3);
roll = out.attitude_rad(1); pitch = out.attitude_rad(2);
p = out.body_rate_radps(1); q = out.body_rate_radps(2); r = out.body_rate_radps(3);
Vhat = out.battery_voltage_V;
% ---- 垂直通道 ----
% NED 下正: 下降(vz>0)需要向上制动(z 加速度<0), 而实现路径是抬推力:
% az = g - T*cos/m = -az_fb -> az_fb = +kvz*vz 才能在 vz>0 时给出 az<0
az_fb = c.kvz_damp*vz;
T_tot = c.mass_kg*(c.gravity_mps2+az_fb)/max(cos(pitch),0.3);
% ---- 前向通道(H6 型) ----
aFb = min(c.speed_rate_mps2,max(-c.speed_rate_mps2,c.kp_speed*(vRef-v)));
aDrag_ff = 0.5*c.air_density_kgpm3*c.drag_coefficient(1)*c.drag_area_m2(1)*v*abs(v)/c.mass_kg;
thetaA = atan2(aFb+aDrag_ff,c.gravity_mps2);
thetaA = max(-deg2rad(c.pitch_max_deg),min(deg2rad(c.pitch_max_deg),thetaA));
pitchCmd = -thetaA;                     % NED321: 前飞加速 = 低头(负俯仰)
% ---- 姿态 PD ----
M_cmd = [c.kp_att*(0-roll)-c.kd_att*p; ...
         c.kp_att*(pitchCmd-pitch)-c.kd_att*q; ...
         c.kp_yaw*(0-r)];
% ---- 混控(悬停线性化) ----
nHoverKrpm = local_n_of_t(c,c.mass_kg/4);            % 悬停转速 krpm
ThoverN = polyval(c.bench_T_coef_desc,nHoverKrpm)*c.gravity_mps2;
Qhover = c.cm_Nm_per_rad2*(nHoverKrpm*1000*2*pi/60)^2;
km = Qhover/ThoverN;
angle = c.rotor_angle_rad(:); direction = c.rotor_direction(:);
A = [-c.arm_m*sin(angle), c.arm_m*cos(angle), -direction*km]';  % 3x4(每桨一列)
thrustN = T_tot/4 + pinv(A)*M_cmd;
thrustN = max(thrustN,0);
% ---- 反查 PWM(台架 T^-1 + KV 正向图互逆) ----
nce_rpm = c.kv_rpm_per_V*Vhat;                      % nce [RPM](KV*V, 满电 ~1140)
rpmCmd = zeros(4,1);
for i = 1:4
    rpmCmd(i) = 1000*local_n_of_t(c,thrustN(i)/c.gravity_mps2);
end
pwm = c.pwm_min_us + (c.pwm_max_us-c.pwm_min_us)*min(1,max(0,rpmCmd/max(nce_rpm,eps)));
pwm = min(max(pwm,c.pwm_min_us),c.pwm_max_us);
diag = struct('v',v,'vz',vz,'pitchCmd',pitchCmd,'pitch',pitch,'T_tot',T_tot, ...
    'thrustN',thrustN,'rpmCmd',rpmCmd,'aFb',aFb,'aDrag_ff',aDrag_ff, ...
    'loadFactorHoverApprox',1);
end
function n = local_n_of_t(c,t)
% 台架 T(n) 反解(正根); t 单位 kgf
b = c.bench_T_coef_desc;
rr = roots([b(1),b(2),b(3)-t]); rr = rr(imag(rr)<1e-9 & real(rr)>0); n = min(real(rr));
if isempty(n) || ~isfinite(n), n = 0; end
end
