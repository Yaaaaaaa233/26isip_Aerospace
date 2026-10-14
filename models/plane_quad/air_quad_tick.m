function y = air_quad_tick(u)
%AIR_QUAD_TICK air_quad.slx 薄包装的一步推进(P4, MATLAB 权威链的 Simulink 外壳)。
% 输入 u = [v_ref_cmd; wind_ned(3); reset](5x1); 输出 y = 8x1:
%   y(1)=P_est_W(估计口径, est_model) y(2)=bus_V y(3)=bus_I y(4)=v_ground
%   y(5)=throttle1 y(6)=throttle2 y(7)=x_pos y(8)=soc
% 状态 = quad_sim 链的 s 结构(persistent); reset>0.5 或首次调用时重建。
% 配置: base 工作区变量 air_quad_config 可覆盖, 默认 quad_sim.baseline('b40')
%   (workbook 口径, C9 非老师参数)。MATLAB 链(quad_sim.ctrl/step)是唯一权威,
%   本函数与 .slx 不含任何自有动力学/功率模型(B2 薄包装口径)。
persistent s c
if isempty(s) || u(5) > 0.5
    if evalin('base','exist(''air_quad_config'',''var'')')
        c = evalin('base','air_quad_config');
    else
        c = quad_sim.config(quad_sim.baseline('b40'));
    end
    nHoverK = local_n_of_t(c,c.mass_kg/4);
    s = quad_sim.reset(c,struct('rotor_omega_radps', ...
        (nHoverK*1000*2*pi/60)*ones(4,1)));
end
dt = c.sample_time_s;
vRef = u(1); wind = u(2:4);
% 与 trim_run 同序: dt=0 采样 -> ctrl -> step(保证与 MATLAB 权威链逐位同序)
[~,out0] = quad_sim.step(s,struct('pwm_us',s.last_pwm_us,'wind_ned_mps',wind),0,c);
pwm = quad_sim.ctrl(s,out0,vRef,c);
[s,out] = quad_sim.step(s,struct('pwm_us',pwm,'wind_ned_mps',wind),dt,c);
frac = (out.pwm_applied_us-1000)/1000;
nHat = frac.*(c.kv_rpm_per_V*out.battery_voltage_V)/1000;
Pmap = max(0,sum(polyval(local_p_coef(c,out.battery_voltage_V),nHat)));
if strcmp(c.est_model,'l1')
    thrustHat = max(0,polyval(c.bench_T_coef_desc,nHat))*c.gravity_mps2;
    vAir = norm(out.relative_air_velocity_mps(1:2));
    savHat = local_ind_saving(c,thrustHat,vAir);
    Pmap = max(0,Pmap-sum(savHat)) + ...
        0.5*c.air_density_kgpm3*c.drag_coefficient(1)*c.drag_area_m2(1)*vAir^3 ...
        + c.aux_power_W;
end
y = [Pmap; out.battery_voltage_V; out.battery_current_A; ...
    norm(out.velocity_ned_mps(1:2)); ...
    max(0,min(1,frac(1))); max(0,min(1,frac(2))); ...
    out.position_ned_m(1); out.soc];
end
function n = local_n_of_t(c,t)
b = c.bench_T_coef_desc;
rr = roots([b(1),b(2),b(3)-t]); rr = rr(imag(rr)<1e-9 & real(rr)>0); n = min(real(rr));
if isempty(n) || ~isfinite(n), n = 0; end
end
function pc = local_p_coef(c,V)
V = min(max(V,c.bench_V_nom(1)),c.bench_V_nom(end));
i = find(c.bench_V_nom <= V,1,'last'); j = min(i+1,numel(c.bench_V_nom));
if i == j, pc = c.bench_P_coef(i,:); return; end
w = (V-c.bench_V_nom(i))/(c.bench_V_nom(j)-c.bench_V_nom(i));
pc = (1-w)*c.bench_P_coef(i,:) + w*c.bench_P_coef(j,:);
end
function [vi,vi0] = local_vi(c,T_N,vair)
vi = zeros(size(T_N)); vi0 = zeros(size(T_N));
A = pi*(c.prop_diameter_m^2)/4; k = T_N/(2*c.air_density_kgpm3*A);
ok = (T_N > 0) & (vair > 0);
vi0(ok) = sqrt(k(ok));
vi(ok) = sqrt((vair/2)^2+k(ok))-vair/2;
end
function sv = local_ind_saving(c,T_N,vair)
[vi,vi0] = local_vi(c,T_N,vair);
sv = max(0,c.h3_induced_gain.*T_N.*(vi0-vi));
end
