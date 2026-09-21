function R = trim_run(c, vRef, secs, opt)
%QUAD_SIM.TRIM_RUN 轨 B 配平保持运行(v_ref 恒指令, 无风), 返回末窗统计与 L0 口径。
% opt.Jgain: 覆盖 rotor_advance_power_gain(默认 0 = M4' 对拍模式; 3 = n 效应复核);
% opt.settleFrom = [v0 v1]: 速度阶跃就位测量(先在 v0 配平半程, 再阶跃到 v1)。
% 时序(每控制周期): ctrl 读当前态(dt=0 采样) -> 植物推进一步 dt —— 与轨 A 的
% 指令时序一致, 无双推进。
% 统计窗 = 末 25% 时长。L0 口径 P_hat = Σ bench P(n_hat(pwm,V)), 估计器输入 =
% 植物诊断 pwm_applied + battery_voltage(与 Q1 估计器同构, 不含 J 项/H3/废阻/aux)。
if nargin < 4, opt = struct(); end
if ~isfield(opt,'Jgain'), opt.Jgain = 0; end
c = quad_sim.config(c,'rotor_advance_power_gain',opt.Jgain);
dt = c.sample_time_s;
nHoverKrpm = local_n_of_t(c,c.mass_kg/4);
s = quad_sim.reset(c,struct('rotor_omega_radps',(nHoverKrpm*1000*2*pi/60)*ones(4,1)));
haveStep = isfield(opt,'settleFrom') && ~isempty(opt.settleFrom);
if haveStep
    v0 = opt.settleFrom(1); vTarget = opt.settleFrom(2);
    for k = 1:round(secs/2/dt)                    % 先在 v0 配平
        out0 = local_sample(s,c);
        pwm = quad_sim.ctrl(s,out0,v0,c);
        s = local_step1(s,pwm,dt,c);
    end
    stepT = s.time_s;
else
    vTarget = vRef;
end
nSteps = round(secs/dt);
vHist = zeros(nSteps,1); PHist = zeros(nSteps,1); PtHist = zeros(nSteps,1);
VHist = zeros(nSteps,1); thHist = zeros(nSteps,1); LFhist = zeros(nSteps,1);
settleS = NaN; settledRun = 0;
for k = 1:nSteps
    out0 = local_sample(s,c);
    pwm = quad_sim.ctrl(s,out0,vRef,c);
    [s,out] = quad_sim.step(s,struct('pwm_us',pwm),dt,c);
    vHist(k) = norm(s.velocity_ned_mps(1:2));
    PHist(k) = out.electrical_power_W;
    VHist(k) = out.battery_voltage_V;
    thHist(k) = out.attitude_rad(2);
    LFhist(k) = mean(out.load_factor);
    frac = (out.pwm_applied_us-1000)/1000;
    nHat = frac.*(c.kv_rpm_per_V*VHist(k))/1000;           % krpm
    PtHist(k) = max(0,sum(polyval(local_p_coef(c,VHist(k)),nHat)));
    if haveStep && isnan(settleS)
        if abs(vHist(k)-vTarget) <= 0.1
            settledRun = settledRun+1;
            if settledRun >= round(2/dt), settleS = s.time_s-stepT; end
        else
            settledRun = 0;
        end
    end
end
w = max(1,floor(0.25*nSteps)):nSteps;
R = struct('vMean',mean(vHist(w)),'vStd',std(vHist(w)), ...
    'Pmean',mean(PHist(w)),'Pstd',std(PHist(w)), ...
    'PHatL0',mean(PtHist(w)),'biasL0_pct',100*(mean(PtHist(w))-mean(PHist(w)))/mean(PHist(w)), ...
    'Vmean',mean(VHist(w)),'pitchDeg',rad2deg(mean(thHist(w))), ...
    'loadFactorMean',mean(LFhist(w)),'settleS',settleS, ...
    'socEnd',s.soc,'cutoff',s.battery_cutoff);
end
function out = local_sample(s,c)
[~,out] = quad_sim.step(s,struct('pwm_us',s.last_pwm_us),0,c);
end
function s = local_step1(s,pwm,dt,c)
[s,~] = quad_sim.step(s,struct('pwm_us',pwm),dt,c); %#ok<ASGUU>
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
