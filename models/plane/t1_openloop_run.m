function out = t1_openloop_run(mode, seed, plan, opts)
%T1_OPENLOOP_RUN T1 开环单次运行（P1/WP1+WP3，平台线）。
%   ⚠ T1 冻结口径提示（P2 起登记）：本运行器按 T1 冻结证据口径驱动"proxy 时代"
%   的 plane（其 plan 模式复算的 E_pred 仍用 proxy 功率公式）。自 P2 提交起
%   models/plane/+plane 内部实现已升级为物理链（06 v1.2），T1 验收证据固定于
%   其冻结提交（bb5e232/d25cb03），本文件在 HEAD 仅作历史复现入口，禁止用于
%   T2 验收（T2 用 t2/harness 入口，见 P2_T2_WORK_PLAN WP6）。
%     mode='plan'    离线名义调度 rollout（不驱 Plant）：固定点迭代含跟踪器
%                    暂态，返回 vPlan/E_pred/φPlan（两臂共用同一 E_pred 分母，
%                    T1_ACCEPTANCE_CHECKLIST §4 冻结口径）。
%     mode='fixed'   固定地速开环臂：v_ref = 常值 V_FIX。
%     mode='nominal' 名义调度开环臂：v_ref(t) = clip(v*_air + w_t(φ), 0, 20)
%                    （保持空速恒等于最优空速 —— 风已知口径，三步走①）。
%   预登记场景（P1 场景预登记，验收以本登记为准）：
%     主任务 T=400 s（保证 ≥2 个完整摆动周期：2πR/v̄≈126 s）, dt=0.01 s
%     （plane.sample_time_s）, 指令周期 Tc=0.5 s（ZOH）,
%     圆 R=100 m（圆心原点）, 世界风正东 W0=3 m/s（风不进力平衡，唯一路径
%     w_t→v_air）, 每种子风幅抖动 W = W0·N(1, 0.05),
%     电池参数覆盖（仅对齐 7S 窗口/内阻的 T1 占位，容量按任务缩放；完整 OCV
%     表接入属 P2）：full 29.4 V / empty 19.75 V / cutoff 19.6 V /
%     R_int 0.003 Ω（组级）/ capacity 20 Ah·capScale,
%     测量链：0.2 s 延迟 + 电流 1 A/电压 0.1 V 量化 + 电流噪声 0.3 A，
%     flags 位：bit0 夹断（按指令周期锁存）/bit2 异常×1.3/bit6 信号缺失/
%     bit7 截止（锁存）。
%   注入窗（opts.inject，默认关闭）：anomaly [t0 t1]（bit2），invalid [t0 t1]
%   （bit6+pval=false），clamp [t0 t1]（v_cmd=25→夹断 20+bit0）。
%   out: 日志结构（t/vCmd/vApp/vg/vair/wt/Pe/Pmeas/flags8/soc/Vb/E/pval）+
%   E_actual/Percent/V星/E_pred/场景指纹。Percent 用评价侧真值能量（红线 1：
%   真值只进评价日志）。
if nargin < 4, opts = struct(); end
def = {'T', 200, 'dt', 0.01, 'Tc', 0.5, 'W0', 3, 'windAmpJitter', 0.05, ...
    'R', 100, 'capScale', 1, 'inject', struct(), 'seedBase', 4100, ...
    'Vfix', 8.0, 'vStep', []};   % vStep=[t0,vLo,vHi]: fixed 臂在 t0 由 vLo→vHi
for k = 1:2:numel(def)
    if ~isfield(opts, def{k}), opts.(def{k}) = def{k+1}; end
end
T = opts.T; dt = opts.dt; N = round(T/dt);
vStar = 6*1.8/(1.8+0.35);   % 代理功率模型最优空速（解析）≈5.023 m/s
inj = opts.inject;
fHas = @(f) isfield(inj, f);

% 电池参数覆盖（预登记，见头注）
pc = plane.config('battery_full_V', 29.4, 'battery_empty_V', 19.75, ...
    'battery_cutoff_V', 19.6, 'battery_resistance_ohm', 0.003, ...
    'battery_capacity_Ah', 20*opts.capScale);

if strcmp(mode, 'plan')
    rng(opts.seedBase + seed, 'twister');
    W = opts.W0 * (1 + opts.windAmpJitter*randn);
    % 固定点迭代：v_g 由跟踪器决定，φ 由 v_g 积分，w_t 依赖 φ
    t = (0:N)*dt;
    vg = vStar*ones(1, N+1);
    phi = zeros(1, N+1);
    for iter = 1:4
        phiv = zeros(1, N+1);
        vgh = zeros(1, N+1);
        vv = 0; sArc = 0;
        for k = 1:N
            wt = -W*sin(phiv(k));
            vCmd = min(20, max(0, vStar + wt));
            dvLag = (vCmd - vv)*(1-exp(-dt/pc.speed_tau_s));
            dvMax = 2.0*dt;
            vv = vv + max(-dvMax, min(dvMax, dvLag));  % 与 plane.step 同式
            sArc = sArc + vv*dt;
            vgh(k+1) = vv;
            phiv(k+1) = sArc/opts.R;
        end
        vg = vgh; phi = phiv;
    end
    wt = -W*sin(phi);
    vAir = vg(1:N) - wt(1:N);
    Pe = pc.hover_power_W + pc.speed_power_gain_W_per_mps2*(vAir-6).^2 ...
        + pc.drag_power_gain_W_per_mps2*vAir.^2 + pc.aux_power_W;
    out = struct('mode', 'plan', 'W', W, 'vStar', vStar, 't', t, ...
        'vPlan', vg(1:N), 'phiPlan', phi(1:N), 'wtPlan', wt(1:N), ...
        'Epred', sum(Pe)*dt, 'PePlan', Pe);
    return
end

% ---- Plant 运行（fixed / nominal）
rng(opts.seedBase + seed, 'twister');
W = opts.W0 * (1 + opts.windAmpJitter*randn);       % 与 plan 同种子同风
rng(opts.seedBase + seed + 5000, 'twister');        % 测量链独立噪声流
s = plane.reset(pc);
windS = struct('time_s', 0, 'wind_truth_ne_mps', [W; 0], ...
    'wind_measured_ne_mps', [W; 0], 'wind_valid', true);
pathC = struct('time_s', 0, 'trajectory_type', 'circle', ...
    'circle_center_ne_m', [0; 0], 'circle_radius_m', opts.R, ...
    'path_phase_rad', 0, 'path_tangent_ne', [0; 1], ...
    'path_normal_ne', [-1; 0], 'path_valid', true);

L = struct('t', zeros(1, N), 'vCmd', zeros(1, N), 'vApp', zeros(1, N), ...
    'vg', zeros(1, N), 'vair', zeros(1, N), 'wt', zeros(1, N), ...
    'Pe', zeros(1, N), 'Pmeas', zeros(1, N), 'flags8', zeros(1, N), ...
    'soc', zeros(1, N), 'Vb', zeros(1, N), 'E', zeros(1, N), ...
    'pval', true(1, N), 'phi', zeros(1, N), 'phiU', zeros(1, N), ...
    'radial', zeros(1, N), 'mileage', zeros(1, N), 'Eplant', zeros(1, N));
dly = round(0.2/dt);                  % 测量延迟 0.2 s
pbuf = nan(1, dly+1); vbuf = nan(1, dly+1); ibuf = nan(1, dly+1);
bbuf = true(1, dly+1);
E = 0; clampLatch = false; cutArmed = false;
mile = 0; phiU = 0;
for k = 1:N
    tk = (k-1)*dt;
    if mod(tk, opts.Tc) < dt/2        % ZOH 指令周期边界
        if strcmp(mode, 'nominal')
            phik = s.phase_rad;
            vCmd = min(20, max(0, plan.vStar + (-W*sin(phik))));
        else
            vCmd = opts.Vfix;
            if ~isempty(opts.vStep)
                if tk < opts.vStep(1), vCmd = opts.vStep(2);
                else, vCmd = opts.vStep(3); end
            end
        end
    end
    if fHas('clamp') && tk >= inj.clamp(1) && tk < inj.clamp(2)
        vCmdRaw = 25;                 % 越界注入
    else
        vCmdRaw = vCmd;
    end
    vApp = min(20, max(0, vCmdRaw));
    clampNow = abs(vApp - vCmdRaw) > 1e-12;
    if clampNow, clampLatch = true; end
    cmd = struct('v_ref_applied_mps', vApp, 'eta_ref_applied', 1, ...
        'controller_mode', 'fixed');
    [s, o] = plane.step(s, windS, pathC, cmd, dt, pc);
    windS.time_s = tk + dt; pathC.time_s = tk + dt;
    % 测量链缓冲（延迟前真值入队；异常 ×1.3 属 plant 侧，作用于入队信号）
    anomEnq = fHas('anomaly') && tk >= inj.anomaly(1) && tk < inj.anomaly(2);
    pbuf = [pbuf(2:end), o.power_w*(1 + 0.3*anomEnq)]; %#ok<AGROW>
    vbuf = [vbuf(2:end), o.voltage_v]; %#ok<AGROW>
    ibuf = [ibuf(2:end), o.current_a]; %#ok<AGROW>
    bbuf = [bbuf(2:end), o.power_valid]; %#ok<AGROW>
    pval = bbuf(1) && ~(fHas('invalid') && tk >= inj.invalid(1) && tk < inj.invalid(2));
    anom = anomEnq;                   % bit2 记账窗与异常窗一致（log 时刻）
    Pe = o.power_w;                   % 评价侧真值
    E = E + Pe*dt;
    mile = mile + o.tangential_ground_speed_mps*dt;
    phiU = phiU + o.tangential_ground_speed_mps*dt/opts.R;  % 未回卷相位
    pm = pbuf(1);
    if pval
        pm = pm*(1 + 0.012*randn);    % 评价不可见：仅测量链噪声口径（不动真值）
    else
        pm = NaN;
    end
    Iq = round(ibuf(1)) + 0.3*randn;  % 1 A 量化 + 噪声（协议分辨率）
    Vq = round(vbuf(1)*10)/10;        % 0.1 V 量化
    f8 = zeros(1, 8, 'uint8');
    if clampLatch, f8(1) = 1; end     % bit0 夹断（指令周期锁存）
    if anom, f8(3) = 1; end           % bit2
    if o.constraint_flags.power_anomaly || s.cutoff, f8(3) = 1; end
    if ~pval, f8(7) = 1; end          % bit6
    if s.cutoff, f8(8) = 1; end       % bit7（plant 当拍完成功率结算后置位）
    if cutArmed && Pe > 0, error('t1:CutoffLatch', 'cutoff 后真值功率>0'); end
    if s.cutoff, cutArmed = true; end % 从下一拍起武装锁存检查
    L.t(k) = tk; L.vCmd(k) = vCmdRaw; L.vApp(k) = vApp;
    L.vg(k) = o.tangential_ground_speed_mps;
    % B1 恒等式是切向口径（06 §6 B 组：w_t + v_air − v = 0）；法向风分量
    % 无动力学后果（声明式丢弃），不入恒等式
    L.vair(k) = -o.air_velocity_ne_mps(1)*sin(s.phase_rad) + ...
        o.air_velocity_ne_mps(2)*cos(s.phase_rad);
    L.wt(k) = -W*sin(s.phase_rad);
    L.Pe(k) = Pe; L.Pmeas(k) = pm; L.flags8(k) = ...
        f8(1)*1 + f8(2)*2 + f8(3)*4 + f8(4)*8 + f8(5)*16 + f8(6)*32 + f8(7)*64 + f8(8)*128;
    L.soc(k) = s.soc; L.Vb(k) = Vq; L.E(k) = E; L.pval(k) = pval;
    L.phi(k) = s.phase_rad; L.phiU(k) = phiU; L.radial(k) = o.radial_error_m;
    L.mileage(k) = mile; L.Eplant(k) = o.energy_electrical_J;
end
out = struct('mode', mode, 'seed', seed, 'W', W, 'vStar', plan.vStar, ...
    'Epred', plan.Epred, 'Eactual', E, ...
    'Percent', 100*(E - plan.Epred)/plan.Epred, 'L', L, 'pc', pc, ...
    'T', T, 'dt', dt, 'Tc', opts.Tc, 'R', opts.R, 'Vfix', opts.Vfix);
end
