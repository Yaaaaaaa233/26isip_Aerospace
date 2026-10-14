function R = realism_run(c, opt)
%QUAD_SIM.REALISM_RUN P2 控制现实性任务运行器(现实性链 + 风扰剧本 + 估计链)。
% 链条(方案 §4 控制现实性清单; 全部参数来自 c, 全零默认=与 trim_run 同序逐位无操作):
%   时延链:   测量时延 meas_delay_s 只施于 GPS 级速度测量(外环; 勘误后语义, 见下) +
%             算法步 ctrl_period_s(控制更新周期, 其间指令保持) + 执行指令时延 cmd_delay_s
%   执行器链: PWM 分辨率 pwm_quant_us(目标量化) + PWM 速率限制 pwm_slew_us_per_s
%             (执行值斜坡) + 植物内既有饱和(PWM 上下限/rpm 帽/推力上限/俯仰限)
%   噪声链:   端电压测量噪声 meas_noise_V_pct(单一传感器流, ctrl 与估计链同源不同时延)
%             + 电流测量噪声 meas_noise_I_pct(仅 vi 档, 独立流 seed+8191, R8③)
%             + 估计链输出乘性噪声 est_noise_pct(T1 语义; vi 测量档不叠乘)
%   估计链:   est_model='l0': P̂ = L0 静态台架映射(pwm_applied, V_meas, 与 trim_run
%             的 PHatL0 同式); 'l1': +声明系数修正(D1, R7 空速口径); 'vi': P̂ =
%             V_meas×I_meas 直接测量(R8③ 电流采样器主档, 无反推链)。
%             全档同型 est_delay_s 输入时延。
%   风扰剧本: 头风 + 确定性正弦/阵风窗(opt 内预注册), 逐步注入 cmd.wind_ned_mps
% 噪声用运行器私有 RandStream(mt19937ar, 固定种子, 共同随机数), 不动全局 rng;
% 所有退化开关为 0 时不抽噪声不改数(逐位无操作)。
% 勘误(2026-10-11, 首评后重评前登记, 方案 §4.1): meas_delay_s 首评误施于整帧测量
% (含姿态/角速率), 0.2 s 陀螺滞后摧毁姿态内环(首评数据存档 quad_realism_firstfire_*)。
% 实机分层语义: 时延只在 GPS 级速度测量; IMU 姿态/角速率与电压传感毫秒级, 不滞后。
% 任务 profile:
%   'cruise'(默认): 悬停 hover_s -> 定速 vCmd_mps 飞 dist_m -> 减速 -> 悬停 hover_s;
%                   同一趟行程能量 E_wh 为策略比较口径(策略=巡航速度)
%   'step'        : stepFrom(1) 保持 step_secs/2 后阶跃 stepFrom(2), 测就位/超调
% 输出 R: E_wh/Ehat_wh/bias_pct/dist_m/completed/vMeanCruise/satDuty/
%         settleS/overshoot_mps/overshoot_pct + 降采样日志(tLog/vLog/PLog/PhatLog)。
% 口径: quad_placeholder 族(C9), 数字仅限内部相对比较。
if nargin < 2 || isempty(opt), opt = struct(); end
defs = struct('profile','cruise','vCmd_mps',6,'dist_m',200,'hover_s',5, ...
    'maxTime_s',240,'stepFrom',[5 8],'step_secs',60,'seed',20261011, ...
    'wind_base_mps',2.5,'wind_sin_amp',0.5,'wind_sin_T_s',23, ...
    'wind_gust_mps',1.5,'wind_gust_windows_s',[20 25; 45 50], ...
    'wind_profile','gust','windPhases_mps',[],'phaseBounds_s',[], ...
    'vref_policy',[]);
% profile='window'(P3): 固定时长窗, vRef 由 opt.vref_policy(info) 给出;
%   info 白名单字段 = t/v/x/Phat/Vmeas/Ehat/cmd(因果边界, 结构强制——真值/风
%   不进信息面; oracle 臂经闭包自带真值, 在 p3_arm 显式声明)。
if ~isempty(opt)
    fn = fieldnames(opt);
    for k = 1:numel(fn), defs.(fn{k}) = opt.(fn{k}); end
end
opt = defs;
dt = c.sample_time_s;
assert(dt > 0 && isfinite(dt),'quad_sim:RealismRun','sample_time_s must be positive.');
nHoverKrpm = local_n_of_t(c,c.mass_kg/4);
s = quad_sim.reset(c,struct('rotor_omega_radps',(nHoverKrpm*1000*2*pi/60)*ones(4,1)));
stream = RandStream('mt19937ar','Seed',opt.seed);
streamI = RandStream('mt19937ar','Seed',opt.seed+8191);  % 电流传感独立流(R8③, 不动电压流序列)
mDelay = round(c.meas_delay_s/dt); cDelay = round(c.cmd_delay_s/dt);
eDelay = round(c.est_delay_s/dt); ctrlEvery = max(1,round(c.ctrl_period_s/dt));
nMax = ceil(opt.maxTime_s/dt);
measBuf = zeros(13,nMax);      % [vel3; att3; rate3; Vmeas; vAir3] 每步写一列
cmdBuf = zeros(4,nMax);        % 控制器目标 PWM(逐列)
appBuf = zeros(4,nMax);        % 执行后 PWM(逐列, 估计链输入)
VmBuf = zeros(1,nMax);         % 电压测量流
ImBuf = zeros(1,nMax);         % 电流测量流(R8③, vi 档估计输入)
logEvery = 5; nLog = ceil(nMax/logEvery);
tLog = zeros(1,nLog); vLog = zeros(1,nLog); PLog = zeros(1,nLog); PhLog = zeros(1,nLog);
nL = 0; Ehat = 0; nApplied = 0; nSat = 0; pwmTarget = []; pwmPrev = [];
PhatPrev = 0; vRefCmd = 0;
phase = 1; tTail = NaN; tCruise = 0; vCruiseSum = 0; completed = false;
for k = 1:nMax
    wind = local_wind(opt,s.time_s);
    [~,out0] = quad_sim.step(s,struct('pwm_us',s.last_pwm_us,'wind_ned_mps',wind),0,c);
    Vtrue = out0.battery_voltage_V;
    if c.meas_noise_V_pct > 0
        Vmeas = Vtrue*(1+c.meas_noise_V_pct/100*randn(stream,1));
    else
        Vmeas = Vtrue;
    end
    Itrue = out0.battery_current_A;
    if strcmp(c.est_model,'vi') && c.meas_noise_I_pct > 0
        Imeas = Itrue*(1+c.meas_noise_I_pct/100*randn(streamI,1));  % R8③ 电流采样器
    else
        Imeas = Itrue;
    end
    kk = max(1,k-mDelay);
    measBuf(:,k) = [out0.velocity_ned_mps; out0.attitude_rad; ...
        out0.body_rate_radps; Vmeas; out0.relative_air_velocity_mps];
    VmBuf(k) = Vmeas;
    ImBuf(k) = Imeas;
    % ---- 控制周期(算法步) + 指令保持 ----
    if mod(k-1,ctrlEvery) == 0 || isempty(pwmTarget)
        m = struct('velocity_ned_mps',measBuf(1:3,kk), ...   % GPS 级: 时延通道
            'attitude_rad',measBuf(4:6,k), ...               % IMU 级: 无附加时延(勘误)
            'body_rate_radps',measBuf(7:9,k), ...
            'battery_voltage_V',measBuf(10,k), ...
            'relative_air_velocity_mps',measBuf(11:13,kk));  % R7: 内核空速(plane H6 同口径)
        if ~isempty(opt.vref_policy)
            info = struct('t',s.time_s,'v',norm(out0.velocity_ned_mps(1:2)), ...
                'x',s.position_ned_m(1),'Phat',PhatPrev,'Vmeas',Vmeas, ...
                'Ehat',Ehat,'cmd',vRefCmd);
            vRef = opt.vref_policy(info);
            vRefCmd = vRef;
        else
            vRef = local_vref(opt,phase,s.time_s);
        end
        pwmTarget = quad_sim.ctrl(s,m,vRef,c);
    end
    cmdBuf(:,k) = pwmTarget;
    tgt = cmdBuf(:,max(1,k-cDelay));
    if c.pwm_quant_us > 0, tgt = c.pwm_quant_us*round(tgt/c.pwm_quant_us); end
    tgt = min(max(tgt,c.pwm_min_us),c.pwm_max_us);
    if isempty(pwmPrev), pwmPrev = tgt; end
    if c.pwm_slew_us_per_s > 0
        maxStep = c.pwm_slew_us_per_s*dt;
        pwmApplied = pwmPrev + max(-maxStep,min(maxStep,tgt-pwmPrev));
        slewActive = any(abs(pwmApplied-pwmPrev) > 0) && any(abs(tgt-pwmApplied) > 0);
    else
        pwmApplied = tgt;
        slewActive = false;
    end
    pwmApplied = min(max(pwmApplied,c.pwm_min_us),c.pwm_max_us);
    pwmPrev = pwmApplied;
    appBuf(:,k) = pwmApplied;
    [s,out] = quad_sim.step(s,struct('pwm_us',pwmApplied,'wind_ned_mps',wind),dt,c);
    % ---- 估计链(P̂ 估计口径, 估计时延; 输入=执行 PWM + 电压测量流 或 V·I 测量) ----
    ke = max(1,k-eDelay);
    if strcmp(c.est_model,'vi')
        % vi 测量档(R8③ 电流采样器主档): P̂ = V_meas×I_meas 直接测量, 无反推链;
        % est_noise_pct 是反推链伪噪声, 不叠乘(测量档噪声源=两路传感器)。
        P0 = VmBuf(ke)*ImBuf(ke);
    else
        frac = (appBuf(:,ke)-1000)/1000;
        nHat = frac.*(c.kv_rpm_per_V*VmBuf(ke))/1000;
        Pmap = max(0,sum(polyval(local_p_coef(c,VmBuf(ke)),nHat)));
        if strcmp(c.est_model,'l1')
            % L1 声明系数修正(D1 档; 首评 L0 速度依赖偏差翻转排序, 勘误后 P3 口径):
            % P̂ = 台架映射 - H3 诱导节省 + 废阻 + aux —— 与植物同型分解(PM-L1=0 无 J 项),
            % 修正项全部来自 config 声明值, 无真值拟合。R7(2026-10-13): 代理项用
            % 【空速】(Q3 û 同口径), 地速代理为 Q2 遗留口径偏差(§4.5)。
            thrustHat = max(0,polyval(c.bench_T_coef_desc,nHat))*c.gravity_mps2;
            vAir = norm(measBuf(11:13,ke));
            savHat = local_ind_saving(c,thrustHat,vAir);
            PdragHat = 0.5*c.air_density_kgpm3*c.drag_coefficient(1)* ...
                c.drag_area_m2(1)*vAir^3;
            P0 = max(0,Pmap-sum(savHat)) + PdragHat + c.aux_power_W;
        else
            P0 = Pmap;
        end
    end
    if c.est_noise_pct > 0 && ~strcmp(c.est_model,'vi')
        Phat = max(0,P0*(1+c.est_noise_pct/100*randn(stream,1)));
    else
        Phat = P0;
    end
    Ehat = Ehat + Phat*dt;
    PhatPrev = Phat;
    nApplied = nApplied + 1;
    if out.object_flags.pwm_at_edge || slewActive, nSat = nSat + 1; end
    vNow = norm(s.velocity_ned_mps(1:2));
    if mod(k-1,logEvery) == 0 && nL < nLog
        nL = nL + 1;
        tLog(nL) = s.time_s; vLog(nL) = vNow;
        PLog(nL) = out.electrical_power_W; PhLog(nL) = Phat;
    end
    % ---- 任务状态机 ----
    tNow = s.time_s; xNow = s.position_ned_m(1);
    if strcmp(opt.profile,'window')
        if tNow >= opt.maxTime_s-0.5*dt, completed = true; break; end  % fp 容差(首评勘误)
    elseif strcmp(opt.profile,'cruise')
        switch phase
            case 1
                if tNow >= opt.hover_s, phase = 2; end
            case 2
                vCruiseSum = vCruiseSum + vNow*dt; tCruise = tCruise + dt;
                if xNow >= opt.dist_m, phase = 3; end
            case 3
                if vNow <= 0.1, phase = 4; tTail = tNow; end
            case 4
                if tNow >= tTail + opt.hover_s, completed = true; break; end
        end
        if tNow >= opt.maxTime_s, break; end
    else
        if tNow >= opt.step_secs, break; end
    end
end
tLog = tLog(1:nL); vLog = vLog(1:nL); PLog = PLog(1:nL); PhLog = PhLog(1:nL);
E_wh = s.energy_electrical_J/3600;
R = struct('profile',opt.profile,'completed',completed, ...
    'E_wh',E_wh,'Ehat_wh',Ehat/3600,'bias_pct',100*(Ehat/3600-E_wh)/E_wh, ...
    'dist_m',s.position_ned_m(1),'tEnd_s',s.time_s, ...
    'vMeanCruise',vCruiseSum/max(tCruise,eps),'satDuty',nSat/max(nApplied,eps), ...
    'settleS',NaN,'overshoot_mps',NaN,'overshoot_pct',NaN, ...
    'tLog',tLog,'vLog',vLog,'PLog',PLog,'PhatLog',PhLog);
if strcmp(opt.profile,'step')
    v0 = opt.stepFrom(1); v1 = opt.stepFrom(2); tStep = opt.step_secs/2;
    post = tLog >= tStep;
    R.overshoot_mps = max(0,max(vLog(post))-v1);
    R.overshoot_pct = 100*R.overshoot_mps/max(abs(v1-v0),eps);
    inBand = abs(vLog-v1) <= 0.1 & tLog >= tStep;
    holdNeed = max(1,round(2/(tLog(2)-tLog(1))));   % 2 s 连续在带(降采样折算)
    R.settleS = local_settle(tLog,inBand,tStep,holdNeed);
end
end
function w = local_wind(opt,t)
% 风扰剧本(预注册, 确定性): 头风(风矢量 -x) + 正弦 + 阵风窗;
% wind_profile='phases'(P3): 分段常值相位风, 风矢量 x = -windPhases_mps(p)
if strcmp(opt.wind_profile,'phases')
    p = find(t < opt.phaseBounds_s(2:end),1,'first');
    if isempty(p), p = numel(opt.windPhases_mps); end
    w = [-opt.windPhases_mps(p); 0; 0];
    return;
end
gust = 0;
gw = opt.wind_gust_windows_s;
for i = 1:size(gw,1)
    if t >= gw(i,1) && t <= gw(i,2), gust = opt.wind_gust_mps; end
end
w = [-(opt.wind_base_mps + opt.wind_sin_amp*sin(2*pi*t/opt.wind_sin_T_s) + gust); 0; 0];
end
function vRef = local_vref(opt,phase,t)
if strcmp(opt.profile,'step')
    if t < opt.step_secs/2, vRef = opt.stepFrom(1);
    else, vRef = opt.stepFrom(2); end
    return;
end
if phase == 2, vRef = opt.vCmd_mps; else, vRef = 0; end
end
function tS = local_settle(tLog,inBand,tStep,holdNeed)
% 就位判据与 trim_run 同式: |v-v1|<=0.1 连续 2 s, 记确认完成时刻
tS = NaN; run = 0;
for i = 1:numel(tLog)
    if tLog(i) < tStep, continue; end
    if inBand(i)
        run = run + 1;
        if run >= holdNeed, tS = tLog(i) - tStep; return; end
    else
        run = 0;
    end
end
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
% 动量理论诱导速度(与 step.m 同式; T_N 允许 4x1 向量, vair 标量)
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
