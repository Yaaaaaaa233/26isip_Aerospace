function out = t2_openloop_run(mode, seed, plan, opts)
%T2_OPENLOOP_RUN T2 闭环物理化单次运行（P2/WP6，平台线）。驱动 P2 物理链
%   models/plane/+plane（默认配置=冻结的 P2 模型：俯仰内核/台架合成/H3 诱导
%   修正/H9 上限/battery_model_v1 电池链——无 T1 占位覆盖）：
%     mode='plan'    名义图 E_pred rollout（不驱 Plant）：内核 ODE 固定点迭代
%                    （含暂态），P_nom(v_air) 为解析稳态图（台架 T(n) 反解 +
%                    H3 动量理论节省 + 共轴 δ + 废阻 + 辅助，满 OCV 电压口径）
%                    ——非循环论证：图积分 vs Plant 真值，两臂共用分母。
%     mode='fixed'   固定地速开环臂：v_ref = V_FIX（默认 8）。
%     mode='nominal' 名义调度臂：v_ref(t) = clip(v*_air + w_t(φ), 0, 20)。
%   场景预登记（docs/T2_SCENARIO_PREREG.md，验收以登记为准）：
%     主任务 T=400 s, dt=0.01 s, Tc=0.5 s(ZOH), 圆 R=100 m, 世界风正东
%     W0=3 m/s（不进力平衡，唯一路径 w_t→v_air）, 每种子风幅抖动
%     W = W0·N(1, 0.05), 种子 1..20（seedBase=4200）。
%     v*_air 由 P2 解析名义图数值极小点导出（本函数内断言与登记值一致）。
%     电池：P2 物理链默认（7S4P 96 Ah OCV 链）；D2/E 注入场景用 soc0 初始
%     深放电（不使用容量缩放）。
%     测量链（T1 冻结语义）：0.2 s 延迟 FIFO + 电流 1 A/电压 0.1 V 量化 +
%     电流噪声 0.3 A + 功率噪声 1.2%；flags：bit0 夹断/ bit2 异常×1.3/
%     bit4 rpm 饱和（协议"转速异常"位，06 v1.2 §2 决策 4）/
%     bit6 信号缺失/ bit7 截止（锁存）。
%   注入（opts.inject）：anomaly/invalid/clamp 同 T1；opts.soc0 初始 SOC；
%   opts.cfgOver 传 plane.config 覆盖对（如 az_cmd_mps2，E 组爬升需求）。
if nargin < 4, opts = struct(); end
def = {'T', 400, 'dt', 0.01, 'Tc', 0.5, 'W0', 3, 'windAmpJitter', 0.05, ...
    'R', 100, 'inject', struct(), 'seedBase', 4200, ...
    'Vfix', 8.0, 'vStep', [], 'soc0', 1.0, 'cfgOver', {}};
for k = 1:2:numel(def)
    if ~isfield(opts, def{k}), opts.(def{k}) = def{k+1}; end
end
T = opts.T; dt = opts.dt; N = round(T/dt);
inj = opts.inject;
fHas = @(f) isfield(inj, f);
REG_VSTAR = 5.0;      % 登记值（T2_SCENARIO_PREREG；1 m/s 网格实测 5，解析复核）

c = plane.config(opts.cfgOver{:});

%% ---- 解析名义图（plan 分母；与 harness truth 同式，冻结口径）
vStar = local_vstar(c);
assert(abs(vStar - REG_VSTAR) <= 0.25, 't2:VStar', ...
    'v*=%.3f 与登记值 %.2f 偏离超容差（模型被改动？）', vStar, REG_VSTAR);

if strcmp(mode, 'plan')
    rng(opts.seedBase + seed, 'twister');
    W = opts.W0 * (1 + opts.windAmpJitter*randn);
    t = (0:N-1)*dt;
    vg = zeros(1, N); phi = zeros(1, N);
    phiPrev = zeros(1, N);
    EpPrev = Inf;
    for iter = 1:16
        vv = 0; theta = 0; sArc = 0; vcmd = 0;
        for k = 1:N
            tk = (k-1)*dt;
            if mod(tk, opts.Tc) < dt/2
                wt = -W*sin(phiPrev(k));
                vcmd = min(20, max(0, vStar + wt));
            end
            % 内核 ODE（与 plane.step 同式：指令限幅 + 废阻前馈 + 俯仰滞后）
            vair = vv + W*sin(phiPrev(k));
            aFb = min(c.speed_rate_mps2, max(-c.speed_rate_mps2, ...
                c.kp_speed*(vcmd - vv)));
            aD = 0.5*c.air_density_kgpm3*c.cda_m2*vair*abs(vair)/c.mass_kg;
            thCmd = min(deg2rad(c.pitch_max_deg), max(-deg2rad(c.pitch_max_deg), ...
                atan2(aFb + aD, c.gravity_mps2)));
            theta = theta + (thCmd - theta)*(1-exp(-dt/c.pitch_tau_s));
            vv = min(20, max(0, vv + aFb*dt));    % 废阻已由前馈补偿
            sArc = sArc + vv*dt;
            vg(k) = vv; phi(k) = sArc/opts.R;
        end
        phiPrev = phi;
        wtArr = -W*sin(phi(1:N));
        vAir = vg - wtArr;
        Pe = local_pmap(c, vAir);
        Epred = sum(Pe)*dt;
        % Picard 收敛判据（PREREG v1.1：圆周中性相位方向收敛慢，固定 4 次
        % 不够——2026-09-08 首跑发现 E_pred 高 2.2%，改收敛驱动）
        if abs(EpPrev - Epred)/Epred < 1e-3, break; end
        EpPrev = Epred;
    end
    out = struct('mode', 'plan', 'W', W, 'vStar', vStar, 't', t, ...
        'vPlan', vg, 'phiPlan', phi, 'wtPlan', wtArr, ...
        'Epred', Epred, 'PePlan', Pe, 'iters', iter);
    return
end

%% ---- Plant 运行（fixed / nominal）
rng(opts.seedBase + seed, 'twister');
W = opts.W0 * (1 + opts.windAmpJitter*randn);       % 与 plan 同种子同风
rng(opts.seedBase + seed + 5000, 'twister');        % 测量链独立噪声流
s = plane.reset(c, struct('soc', opts.soc0));
windS = struct('time_s', 0, 'wind_truth_ne_mps', [W; 0], ...
    'wind_measured_ne_mps', [W; 0], 'wind_valid', true);
pathC = struct('time_s', 0, 'trajectory_type', 'circle', ...
    'circle_center_ne_m', [0; 0], 'circle_radius_m', opts.R, ...
    'path_phase_rad', 0, 'path_tangent_ne', [0; 1], ...
    'path_normal_ne', [-1; 0], 'path_valid', true);

L = struct('t', zeros(1, N), 'vCmd', zeros(1, N), 'vApp', zeros(1, N), ...
    'vg', zeros(1, N), 'vair', zeros(1, N), 'wt', zeros(1, N), ...
    'Pe', zeros(1, N), 'Pmeas', nan(1, N), 'flags8', zeros(1, N), ...
    'soc', zeros(1, N), 'Vb', zeros(1, N), 'E', zeros(1, N), ...
    'pval', true(1, N), 'phi', zeros(1, N), 'phiU', zeros(1, N), ...
    'radial', zeros(1, N), 'mileage', zeros(1, N), 'Eplant', zeros(1, N), ...
    'nUp', zeros(1, N), 'nLo', zeros(1, N), ...
    'Tact', zeros(1, N), 'Tce', zeros(1, N));
dly = round(0.2/dt);
pbuf = nan(1, dly+1); vbuf = nan(1, dly+1); ibuf = nan(1, dly+1);
bbuf = true(1, dly+1);
E = 0; clampLatch = false; cutLatch = false; cutArmed = false;
mile = 0; vCmd = 0; phiPrevStep = 0;
for k = 1:N
    tk = (k-1)*dt;
    if mod(tk, opts.Tc) < dt/2        % ZOH 指令周期边界
        if strcmp(mode, 'nominal')
            vCmd = min(20, max(0, vStar + (-W*sin(s.phase_rad))));
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
    if abs(vApp - vCmdRaw) > 1e-12, clampLatch = true; end
    cmd = struct('v_ref_applied_mps', vApp, 'eta_ref_applied', 1, ...
        'controller_mode', 'fixed');
    [s, o] = plane.step(s, windS, pathC, cmd, dt, c);
    windS.time_s = tk + dt; pathC.time_s = tk + dt;
    pbuf = [pbuf(2:end), o.power_w]; %#ok<AGROW>
    vbuf = [vbuf(2:end), o.voltage_v]; %#ok<AGROW>
    ibuf = [ibuf(2:end), o.current_a]; %#ok<AGROW>
    bbuf = [bbuf(2:end), o.power_valid]; %#ok<AGROW>
    pval = bbuf(1) && ~(fHas('invalid') && tk >= inj.invalid(1) && tk < inj.invalid(2));
    anom = fHas('anomaly') && tk >= inj.anomaly(1) && tk < inj.anomaly(2);
    Pe = o.power_w;
    E = E + Pe*dt;
    mile = mile + o.tangential_ground_speed_mps*dt;
    pm = pbuf(1);
    if pval
        pm = pm*(1 + 0.012*randn);    % 评价不可见：仅测量链噪声口径
        if anom, pm = pm*1.3; end
    else
        pm = NaN;
    end
    Iq = round(ibuf(1)) + 0.3*randn;
    Vq = round(vbuf(1)*10)/10;
    f8 = zeros(1, 8, 'uint8');
    if clampLatch, f8(1) = 1; end     % bit0 夹断
    if anom, f8(3) = 1; end           % bit2
    if o.constraint_flags.power_anomaly || s.cutoff, f8(3) = 1; end
    if o.constraint_flags.rpm_saturation, f8(5) = 1; end  % bit4 rpm/PWM 饱和
    if ~pval, f8(7) = 1; end          % bit6
    if s.cutoff, f8(8) = 1; end       % bit7（plant 当拍完成功率结算后置位）
    if cutArmed && Pe > 0, error('t2:CutoffLatch', 'cutoff 后真值功率>0'); end
    if s.cutoff, cutArmed = true; cutLatch = true; end
    L.t(k) = tk; L.vCmd(k) = vCmdRaw; L.vApp(k) = vApp;
    L.vg(k) = o.tangential_ground_speed_mps;
    L.vair(k) = -o.air_velocity_ne_mps(1)*sin(s.phase_rad) ...
        + o.air_velocity_ne_mps(2)*cos(s.phase_rad);   % 切向投影（B1 恒等式口径）
    L.wt(k) = -W*sin(s.phase_rad);
    L.Pe(k) = Pe; L.Pmeas(k) = pm; L.flags8(k) = ...
        f8(1)*1 + f8(2)*2 + f8(3)*4 + f8(4)*8 + f8(5)*16 + f8(6)*32 + f8(7)*64 + f8(8)*128;
    L.soc(k) = s.soc; L.Vb(k) = Vq; L.E(k) = E; L.pval(k) = pval;
    L.phi(k) = s.phase_rad;
    if k == 1
        L.phiU(1) = L.phi(1);          % 首步相位增量（初始相位 0）
    else                           % 未回卷相位（里程恒等式用）
        dphi = s.phase_rad - L.phi(k-1);
        if dphi > pi, dphi = dphi - 2*pi; end
        if dphi < -pi, dphi = dphi + 2*pi; end
        L.phiU(k) = L.phiU(k-1) + dphi;
    end
    L.radial(k) = o.radial_error_m;
    L.mileage(k) = mile; L.Eplant(k) = o.energy_electrical_J;
    L.nUp(k) = o.motor_rpm(1); L.nLo(k) = o.motor_rpm(2);
    L.Tact(k) = o.thrust_total_actual_n; L.Tce(k) = o.thrust_ceiling_n;
end
out = struct('mode', mode, 'seed', seed, 'W', W, 'vStar', vStar, ...
    'Epred', plan.Epred, 'Eactual', E, ...
    'Percent', 100*(E - plan.Epred)/plan.Epred, 'L', L, 'pc', c, ...
    'T', T, 'dt', dt, 'Tc', opts.Tc, 'R', opts.R, 'Vfix', opts.Vfix);
end

function vs = local_vstar(c)
% P2 解析名义图数值极小点（0.05 m/s 网格，[0,10] 域）
vv = 0:0.05:10;
P = arrayfun(@(x) local_pmap(c, x), vv);
[~, i] = min(P);
vs = vv(i);
end

function P = local_pmap(c, vair)
% P2 解析稳态名义图（满 OCV 电压口径；与 harness truth 同式；矢量化）：
%   废阻前馈稳态俯仰 -> T=m g/cosθ/8 -> 台架 T(n) 解析反解 -> P(n;Vfull)
%   -> H3 诱导节省 -> 共轴 δ -> + 废阻 + 辅助
vair = abs(vair);
aD = 0.5*c.air_density_kgpm3*c.cda_m2*vair.*vair/c.mass_kg;
th = atan(aD/c.gravity_mps2);
Tkgf = c.mass_kg./(8*cos(th));
Vfull = c.battery_n_ser*interp1(c.battery_ocv_soc, c.battery_ocv_cell_V, 1);
b = c.bench_T_coef_desc;                       % b1 n^2 + b2 n + (b3-T) = 0
n = (-b(2) + sqrt(b(2)^2 - 4*b(1)*(b(3) - Tkgf)))/(2*b(1));
i = find(c.bench_V_nom <= Vfull, 1, 'last'); j = min(i+1, numel(c.bench_V_nom));
w = (Vfull - c.bench_V_nom(i))/(c.bench_V_nom(j) - c.bench_V_nom(i));
Pc = (1-w)*c.bench_P_coef(i, :) + w*c.bench_P_coef(j, :);
A = pi*(c.prop_diameter_m^2)/4; k = Tkgf*c.gravity_mps2/(2*c.air_density_kgpm3*A);
vi0 = sqrt(k); vi = sqrt((vair/2).^2 + k) - vair/2;
sav = max(0, c.h3_induced_gain*Tkgf*c.gravity_mps2.*(vi0 - min(vi, vi0)));
pro = polyval(Pc, n) - sav;
P = c.arm_count*(pro + pro*(1 + c.coaxial_delta_base)) ...
    + 0.5*c.air_density_kgpm3*c.cda_m2*vair.^3 + c.aux_power_W;
end

function s = local_ind_saving(c, T_N, vair)
if T_N <= 0 || vair <= 0, s = 0; return; end
A = pi*(c.prop_diameter_m^2)/4; k = T_N/(2*c.air_density_kgpm3*A);
vi0 = sqrt(k); vi = sqrt((vair/2)^2 + k) - vair/2;
s = max(0, c.h3_induced_gain*T_N*(vi0 - vi));
end

function pc = local_p_coef(c, V)
V = min(max(V, c.bench_V_nom(1)), c.bench_V_nom(end));
i = find(c.bench_V_nom <= V, 1, 'last'); j = min(i+1, numel(c.bench_V_nom));
if i == j, pc = c.bench_P_coef(i, :); return; end
w = (V - c.bench_V_nom(i))/(c.bench_V_nom(j) - c.bench_V_nom(i));
pc = (1-w)*c.bench_P_coef(i, :) + w*c.bench_P_coef(j, :);
end
