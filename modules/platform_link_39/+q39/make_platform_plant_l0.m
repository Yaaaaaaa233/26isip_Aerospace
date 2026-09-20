function plt = make_platform_plant_l0(scn, c, opt)
%MAKE_PLATFORM_PLANT_L0 Q1 估计链 plant(以 3.8 号 +w36/make_platform_plant 为基底)。
% 与基底的唯一语义差异 = 算法可见功率的来源(QUAD_MIGRATION_PLAN 20260921 Q1):
%   estMode='l0':    q() 返回 L0 静态台架估计 P_hat(q39.est_l0), 输入取植物诊断
%                    motor_pwm_us + voltage_v——实机"指令侧+传感器侧"可观测量的
%                    仿真对应物。真功率只留日志/评价列(P3 双口径), 植物物理层零改动。
%   estMode='truth': 与 3.8 号基底逐位同语义(用于复现 moe38 锚点)。
% 场景偏差注入(合成"台架标定误差", 非估计器知识):
%   P_hat_meas = P_map * (1 + s1_pct/100) * (1 + s2_pct_mps/100 * |u_air|)
%   V_hat      = V * (1 + s4_vpct/100)      (反解与查表同时被污染, S4)
% S3 结构性偏差 = estMode='l0' 且偏差全零(H3/H5/废阻/辅助缺失的物理内置项)。
% 驻留场景 S5: dwell_s>0 时就位委托制替换为"指令后固定驻留 dwell_s 秒再采样"
% (实机无 q() 委托便利, 驻留时间照计预算)。
% 逐秒日志: powerMeas 列 = 估计链经 0.2s 延迟 + 1.2% 噪声(T1 语义搬到估计口径);
% 追加 powerEstN(无延迟无噪声的逐秒估计)/voltV 两列诊断。真值口径列(powerTrue/
% minPowerTrue 滑动电压参照)与基底逐位一致。
% 预算/种子/就位语义/三原语与基底完全一致(红线 2 不变); rng(c.seed) 照旧。
if nargin < 3 || isempty(opt)
    opt = struct('estMode','l0','s1_pct',0,'s2_pct_mps',0,'s4_vpct',0,...
        'dwell_s',0,'pretrainCache',false);
    opt.arms = {};   % struct() 收到空 cell 会生成 0x0 空结构体, 必须后补字段
end
root = fileparts(mfilename('fullpath'));
cands = {fullfile(root,'..','..','..'), ...
         fullfile(root,'..','..','..','26isip_Aerospace'), ...
         fullfile(root,'..','..','26isip_Aerospace'), ...
         fullfile(root,'..','..','..','..','26isip_Aerospace')};
needPlane = isempty(which('plane.config'));
needHarness = isempty(which('harness.make_plane_adapter'));
repoRoot = '';
if needPlane || needHarness
    for i = 1:numel(cands)
        if isfile(fullfile(cands{i},'models','plane','+plane','config.m'))
            repoRoot = cands{i}; break;
        end
    end
    assert(~isempty(repoRoot),'q39:PlatformPlantL0', ...
        ['未找到26isip_Aerospace仓库根(已试: ' strjoin(cands,' ; ') ')。']);
end
if needPlane
    dst = fullfile(tempdir,'t36_plane_fallback');
    if exist(fullfile(dst,'+plane','config.m'),'file') ~= 2
        if exist(dst,'dir'), rmdir(dst,'s'); end
        copyfile(fullfile(repoRoot,'models','plane'),dst);
    end
    addpath(dst);
end
if needHarness
    dst2 = fullfile(tempdir,'t36_harness_fallback');
    if exist(fullfile(dst2,'+harness','make_plane_adapter.m'),'file') ~= 2
        if exist(dst2,'dir'), rmdir(dst2,'s'); end
        copyfile(fullfile(repoRoot,'harness'),dst2);
    end
    addpath(dst2);
end
assert(~isempty(which('plane.config')),'q39:PlatformPlantL0','找不到平台对象 models/plane/+plane。');
assert(strcmp(c.backend,'platform'),'q39:PlatformPlantL0','本后端仅用于 backend=platform。');
assert(abs(c.tEval-1.0)<1e-12,'q39:PlatformPlantL0','平台后端要求 tEval=1.0s(预算按秒)。');
assert(any(strcmp(opt.estMode,{'truth','l0'})),'q39:PlatformPlantL0','estMode must be truth or l0.');
rng(c.seed);   % 平台后端可复现性(F4): 与基底同语义
pc = plane.config('circle_radius_m', c.turnRadius);
dt = pc.sample_time_s;
acT = harness.make_plane_adapter(struct('powerScaleW', 1), struct());
ttA = acT.truth();
uu = ttA.curveV(:); JJ = ttA.curveJ(:);
[PminW, ~] = min(JJ); vStarAir = uu(find(JJ==PminW,1));
hoverW = JJ(1); powerScale = hoverW;
% ---- 任务3.8 滑动电压参照(照抄基底, 真值口径评价列不变) ----
Vfull = pc.battery_n_ser * interp1(pc.battery_ocv_soc, pc.battery_ocv_cell_V, 1);
Vlo   = max(pc.battery_cutoff_V, min(pc.bench_V_nom));
Vgrid = linspace(Vlo, Vfull, 41);
PminNormV = zeros(size(Vgrid));
for iv = 1:numel(Vgrid)
    [~, JVv] = local_curveJV(pc, Vgrid(iv));
    PminNormV(iv) = min(JVv) / powerScale;
end
PminNormAtV = @(V) interp1(Vgrid, PminNormV, min(max(V, Vgrid(1)), Vgrid(end)));
cW = c; cW.duration = ceil((c.evalSeconds+240)/c.tEval);
scnW = w36.scenario('static', cW);
s = plane.reset(pc);
est = c.initialSpeed; lastTag = 'init'; curV = c.initialSpeed;
tHist = []; pHist = []; eHist = [];
lastPwm = zeros(pc.motor_count,1); lastV = s.voltage_v; lastUair = 0;
rows = {}; rowCnt = 0; secMarker = floor(s.time_s);
accPeak = 0; vPrev = s.v_ground_mps;
plt = struct('q', @q, 'amendEstimate', @amendEstimate, 'count', @count, ...
    'table', @table, 'truth', @truth, 'windAt', @windAt, 'planeCfg', pc, ...
    'settleDelegated', true, ...   % 委托制/驻留制都满足"返回前测量已有效"契约(RL 更新门依据; 驻留模式的 d 秒延迟照计预算并由 ψ̂ 死推如实推进)
    'estOpt', opt, ...
    'phase', @phase);
    function p = phase()
        p = s.phase_rad;
    end
    function [Wx, Wy] = windAt(t, psi)
        [Wx, Wy] = w36.wind_field(scnW, t, psi);
    end
    function tf = truth()
        tf.uu = uu; tf.JJ = JJ; tf.vStarAir = vStarAir;
        tf.PminW = PminW; tf.hoverW = hoverW; tf.PminNorm = PminW/powerScale;
    end
    function v = count()
        v = s.time_s;
    end
    function amendEstimate(v)
        est = v;
    end
    function Pest = est_now()
        % L0 估计(含场景偏差), 取最近一拍植物诊断(指令侧 pwm + 传感器侧 V)
        Vhat = lastV * (1 + opt.s4_vpct/100);
        Pmap = q39.est_l0(pc, lastPwm, Vhat);
        Pest = Pmap * (1 + opt.s1_pct/100) * (1 + opt.s2_pct_mps/100 * lastUair);
    end
    function mult = local_mult(uair)
        % truth 口径的合成标定误差乘子(S1/S2): "估计器已抓住曲线形状, 残差为
        % 常数/倾斜"。s1=s2=0 时恒等 1.0(ANCHOR 幕逐位复现 moe38 的前提)。
        mult = (1 + opt.s1_pct/100) * (1 + opt.s2_pct_mps/100 * uair);
    end
    function Pm = q(v, tag)
        vref = min(pc.speed_bounds_mps(2), max(pc.speed_bounds_mps(1), double(v)));
        curV = vref; lastTag = char(tag);
        if opt.dwell_s > 0
            % S5 驻留语义: 指令后固定驻留 d 秒再采样(替换就位委托制)
            d = max(1, round(opt.dwell_s));
            for i = 1:d
                Pm = adv(1.0);
            end
        else
            % 就位委托制(与基底一致): adv(1.0) 循环至 |v_ground-v_ref|<=settleTol
            settledK = 0; guard = 0; %#ok<NASGU> % settledK 保留基底注释语境
            while true
                Pm = adv(1.0); guard = guard + 1;
                if abs(s.v_ground_mps - vref) <= c.settleTol, break; end
                if guard >= 30, break; end
            end
        end
        if strcmp(opt.estMode, 'l0')
            Pm = est_now() / powerScale;   % 算法可见口径 = L0 估计(归一不变)
        else
            Pm = Pm * local_mult(lastUair) / powerScale;   % 真值口径 + S1/S2 合成残差
        end
    end
    function PmChunk = adv(dtChunk)
        nInner = round(dtChunk/dt);
        psum = 0;
        for k = 1:nInner
            tNext = s.time_s + dt;
            [Wx, Wy] = w36.wind_field(scnW, tNext, s.phase_rad);
            windSample = struct('time_s', tNext, ...
                'wind_truth_ne_mps', [Wx;Wy], 'wind_measured_ne_mps', [Wx;Wy], ...
                'wind_valid', true);
            pathCommand = struct('trajectory_type', 'circle', ...
                'circle_center_ne_m', [0;0], 'circle_radius_m', pc.circle_radius_m, ...
                'path_phase_rad', s.phase_rad, 'path_tangent_ne', [0;1], ...
                'path_normal_ne', [-1;0], 'path_valid', true);
            cmd = struct('v_ref_applied_mps', curV, 'eta_ref_applied', 1, ...
                'controller_mode', 'fixed');
            [s, out] = plane.step(s, windSample, pathCommand, cmd, dt, pc);
            assert(all(isfinite([s.v_ground_mps, out.power_w])), ...
                'q39:PlatformPlantL0', 'plane diverged at v_ref=%.2f', curV);
            tHist(end+1) = out.time_s; %#ok<AGROW>
            pHist(end+1) = out.power_w; %#ok<AGROW>
            psum = psum + out.power_w;
            tangentNow = [-sin(s.phase_rad); cos(s.phase_rad)];
            lastPwm = out.motor_pwm_us;
            lastV = out.voltage_v;
            lastUair = abs(dot(out.air_velocity_ne_mps, tangentNow));
            eHist(end+1) = est_now(); %#ok<AGROW>
            accPeak = max(accPeak, abs(s.v_ground_mps - vPrev)/dt);
            vPrev = s.v_ground_mps;
            if floor(s.time_s) > secMarker
                secMarker = floor(s.time_s);
                rowCnt = rowCnt + 1;
                tq = max(0, s.time_s - 0.2);
                if strcmp(opt.estMode, 'l0')
                    edel = interp1(tHist, eHist, tq, 'linear', 'extrap');
                    PmeasW = max(0, edel*(1 + 0.012*randn));
                else
                    Pdel = interp1(tHist, pHist, tq, 'linear', 'extrap');
                    PmeasW = max(0, Pdel*(1 + 0.012*randn)) * local_mult(lastUair);
                end
                [Wx2, Wy2] = w36.wind_field(scnW, s.time_s, s.phase_rad);
                wt = Wx2*tangentNow(1) + Wy2*tangentNow(2);
                optGnd = min(max(vStarAir + wt, pc.speed_bounds_mps(1)), ...
                    pc.speed_bounds_mps(2));
                rows(end+1,:) = {rowCnt, s.time_s, s.v_ground_mps, curV, ...
                    lastTag, PmeasW/powerScale, out.power_w/powerScale, ...
                    optGnd, PminNormAtV(s.voltage_v), est, rad2deg(s.phase_rad), 0, 0, ...
                    accPeak, abs(dot(out.air_velocity_ne_mps, tangentNow)), ...
                    Wx2, Wy2, s.position_ne_m(1), s.position_ne_m(2), ...
                    eHist(end)/powerScale, out.voltage_v}; %#ok<AGROW>
                accPeak = 0;
            end
        end
        PmChunk = psum/nInner;
    end
    function tb = table()
        tb = cell2table(rows, 'VariableNames', {'step','time','speed','speedCmd', ...
            'tag','powerMeas','powerTrue','optimumTrue','minPowerTrue','estimate', ...
            'headingDeg','shiftDx','shiftDy','accelMax','airspeed','windX','windY', ...
            'posX','posY','powerEstN','voltV'});
    end
end

function [uuV, JV] = local_curveJV(pc, V)
% 参数化电压的真值曲线(照抄 3.8 号基底, 与 harness adapter truth() 同式)
vv = linspace(pc.speed_bounds_mps(1), pc.speed_bounds_mps(2), 801);
nce = pc.ceiling_kn_rpm_per_V * V;
Tce = polyval(pc.bench_T_coef_desc, nce / 1000);
J = zeros(size(vv));
for i = 1:numel(vv)
    aD = 0.5 * pc.air_density_kgpm3 * pc.cda_m2 * vv(i)^2 / pc.mass_kg;
    th = atan(aD / pc.gravity_mps2);
    Trot = pc.mass_kg * pc.gravity_mps2 / (8 * cos(th) * pc.gravity_mps2);
    n = local_n_of_t(pc, min(Trot, Tce));
    Pc = q39.p_coef(pc, V);
    pro = polyval(Pc, n) - local_ind_saving(pc, Trot * pc.gravity_mps2, vv(i));
    dLo = pc.coaxial_delta_base * local_vi_ratio(pc, Trot * pc.gravity_mps2, vv(i))^pc.coaxial_decay_kappa;
    Pmot = pc.arm_count * (pro + pro * (1 + dLo));
    Pdrag = 0.5 * pc.air_density_kgpm3 * pc.cda_m2 * vv(i)^3;
    J(i) = Pmot + Pdrag + pc.aux_power_W;
end
uuV = vv; JV = J;
end
function n = local_n_of_t(pc, t)
b = pc.bench_T_coef_desc;
r = roots([b(1), b(2), b(3) - t]); r = r(imag(r) < 1e-9 & real(r) > 0); n = min(real(r));
if isempty(n) || ~isfinite(n), n = 0; end
end
function [vi, vi0] = local_vi(pc, T_N, vair)
vi = 0; vi0 = 0;
if T_N <= 0 || vair <= 0, return; end
A = pi * (pc.prop_diameter_m^2) / 4; k = T_N / (2 * pc.air_density_kgpm3 * A);
vi0 = sqrt(k); vi = sqrt((vair/2)^2 + k) - vair/2;
end
function ratio = local_vi_ratio(pc, T_N, vair)
[vi, vi0] = local_vi(pc, T_N, vair);
if vi0 > 0, ratio = vi / vi0; else, ratio = 0; end
end
function sv = local_ind_saving(pc, T_N, vair)
[vi, vi0] = local_vi(pc, T_N, vair);
sv = max(0, pc.h3_induced_gain * T_N * (vi0 - vi));
end
