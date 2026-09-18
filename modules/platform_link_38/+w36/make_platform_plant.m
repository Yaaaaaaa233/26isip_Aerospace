function plt = make_platform_plant(scn, c)
%MAKE_PLATFORM_PLANT 平台后端plant(任务3.6, 薄交互层)。
% 算法侧三原语不变(红线2), 底层数据全部来自平台 P2 物理链 models/plane/+plane:
%   q(v,tag):      向平台发本时刻目标速度 v_ref(每时刻一次, 平台自行闭环执行),
%                  推进平台一个时刻(1s), 回读平台输出: 位置/真实速度/功率。
%   count():       任务窗已消耗仿真秒数(预算按秒丈量, 2026-09-08 拍板1)。
%   amendEstimate: 算法估计值记账(进日志列)。
% 测量链(T1 平台冻结语义): 算法可见功率 = 平台功率经 0.2s 延迟 FIFO + 1.2% 噪声;
%   位置/真实速度/真值功率只进日志与评价列(红线1: 控制器不读, 仅供 UI/评价)。
% 评价器真值曲线(MOE 的理论最低功率列与 UI 真值曲线)取自平台线权威源
%   harness.make_plane_adapter().truth()——非本模块自造模型。
% 任务3.8(2026-09-11) 评价参照修复: 该曲线钉在满电OCV的稳态解析, 而实时链
%   plane.step 按逐拍跌落电压插值台架分块系数——实测实时链比满电曲线便宜
%   ~1%(3600s)~1.65%(9000s), 恒定 minPowerTrue 在平台上不是真下界(26-90%
%   的秒数"低于理论最低", excess 被系统性美化)。修复: minPowerTrue 逐秒取
%   "按当前端电压重算的真值曲线谷底"(滑动电压参照, 见 PminNormAtV), 恢复
%   真下界语义; UI 真值曲线仍为满电口径(显示用)。
% 功率归一: 除以平台悬停功率(真值曲线 J(0)), 算法侧 hover≈1 口径与 3.5 一致。
% 依赖: models/plane(+plane) 与 harness(+harness) 在 MATLAB path(平台线仓库)。
if nargin<1, c=w36.config(); end
root=fileparts(mfilename('fullpath'));
% 部署修复(2026-09-09 15:40): 同一代码可能从两种布局运行——
%   a) 仓库模块 26isip_Aerospace/modules/platform_link/+w36 (3级上级=仓库根)
%   b) 工作目录 控制寻优/speed_esc_matlab/3.6_platform_link/+w36
%      (3级上级=控制寻优, 仓库根=控制寻优/26isip_Aerospace)
% 单一相对候选在 b) 下解析到 控制寻优\models\plane(不存在)使 copyfile 直接
% 抛"找不到匹配文件"。改为逐候选探测 models/plane/+plane/config.m 文件存在性。
cands={fullfile(root,'..','..','..'), ...
       fullfile(root,'..','..','..','26isip_Aerospace'), ...
       fullfile(root,'..','..','26isip_Aerospace'), ...
       fullfile(root,'..','..','..','..','26isip_Aerospace')};
needPlane=isempty(which('plane.config'));
needHarness=isempty(which('harness.make_plane_adapter'));
repoRoot='';
if needPlane || needHarness
    for i=1:numel(cands)
        if isfile(fullfile(cands{i},'models','plane','+plane','config.m'))
            repoRoot=cands{i}; break;
        end
    end
    assert(~isempty(repoRoot),'w36:PlatformPlant', ...
        ['未找到26isip_Aerospace仓库根(已试: ' strjoin(cands,' ; ') ...
         ')。请用 open_3_6_demo 启动, 或确认仓库已git clone/pull到上述任一位置。']);
end
if needPlane
    dst=fullfile(tempdir,'t36_plane_fallback');
    if exist(fullfile(dst,'+plane','config.m'),'file')~=2
        if exist(dst,'dir'), rmdir(dst,'s'); end
        copyfile(fullfile(repoRoot,'models','plane'),dst);
    end
    addpath(dst);
end
if needHarness
    dst2=fullfile(tempdir,'t36_harness_fallback');
    if exist(fullfile(dst2,'+harness','make_plane_adapter.m'),'file')~=2
        if exist(dst2,'dir'), rmdir(dst2,'s'); end
        copyfile(fullfile(repoRoot,'harness'),dst2);
    end
    addpath(dst2);
end
assert(~isempty(which('plane.config')),'w36:PlatformPlant','找不到平台对象 models/plane/+plane, 请检查仓库路径。');
assert(strcmp(c.backend,'platform'),'w36:PlatformPlant','本后端仅用于 backend=platform。');
assert(abs(c.tEval-1.0)<1e-12,'w36:PlatformPlant','平台后端要求 tEval=1.0s(预算按秒)。');
rng(c.seed);   % 平台后端可复现性(F4, 2026-09-09): 与本地后端 make_plant 同语义
pc = plane.config('circle_radius_m', c.turnRadius);
dt = pc.sample_time_s;
acT = harness.make_plane_adapter(struct('powerScaleW', 1), struct());
ttA = acT.truth();
uu = ttA.curveV(:); JJ = ttA.curveJ(:);
[PminW, ~] = min(JJ); vStarAir = uu(find(JJ==PminW,1));
hoverW = JJ(1); powerScale = hoverW;
% ---- 任务3.8: 滑动电压参照(见文件头说明) ----
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
tHist = []; pHist = [];
rows = {}; rowCnt = 0; secMarker = floor(s.time_s);
accPeak = 0; vPrev = s.v_ground_mps;
plt = struct('q', @q, 'amendEstimate', @amendEstimate, 'count', @count, ...
    'table', @table, 'truth', @truth, 'windAt', @windAt, 'planeCfg', pc, ...
    'settleDelegated', true, ...   % 就位委托制(2026-09-09): q()返回前已就位, RL更新门据此放行
    'phase', @phase);     % 任务3.8: 真实相位句柄(嵌套函数读实时 s.phase_rad; 匿名函数会按值捕获s, 严禁)
    function p = phase()
        p = s.phase_rad;   % 评价侧参照(known oracle)读真相位用
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
    function Pm = q(v, tag)
        vref = min(pc.speed_bounds_mps(2), max(pc.speed_bounds_mps(1), double(v)));
        curV = vref; lastTag = char(tag);
        % F1(2026-09-09): adv 参数是秒数(原误传步数致每查询100s, 标定永不执行)。
        % D3条件阶段5落地(2026-09-09 用户确认触发): 后端就位委托制——每次查询
        % 内部循环 adv(1.0) 直至 |v_ground-v_ref|<=c.settleTol, 或30秒安全上限;
        % 等待秒数照计预算(count()=s.time_s), 返回就位后末秒功率(即接手方案§3的
        % "适配器稳态查询制"原草案, 不加严保持条件)。原因: settled_q 的就位模型
        % 按本地动力学标定, 平台慢俯仰(t63≈2.9s)下采样带瞬态, 实测标定迟滞
        % ±0.3-0.4 m/s——平台寻优质量与本地不对等。逐秒日志保持1行/秒。
        settledK = 0; guard = 0;
        while true
            Pm = adv(1.0); guard = guard + 1;
            if abs(s.v_ground_mps - vref) <= c.settleTol, break; end
            if guard >= 30, break; end
        end
        % 功率归一(2026-09-09 补漏): adv 返回原始瓦数, q() 必须除以平台悬停功率
        % (与逐秒日志口径一致, 也与本地plant hover≈1口径一致——数据源一致性)。
        % 此前返回路径漏除: sweepcal 拟合系数为瓦特量纲, demo按归一化绘制导致
        % 拟合线始终在图范围外(用户报告的现象1)。
        Pm = Pm / powerScale;
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
                'w36:PlatformPlant', 'plane diverged at v_ref=%.2f', curV);
            tHist(end+1) = out.time_s; %#ok<AGROW>
            pHist(end+1) = out.power_w; %#ok<AGROW>
            psum = psum + out.power_w;
            accPeak = max(accPeak, abs(s.v_ground_mps - vPrev)/dt);
            vPrev = s.v_ground_mps;
            if floor(s.time_s) > secMarker
                secMarker = floor(s.time_s);
                rowCnt = rowCnt + 1;
                tq = max(0, s.time_s - 0.2);
                Pdel = interp1(tHist, pHist, tq, 'linear', 'extrap');
                PmeasW = max(0, Pdel*(1 + 0.012*randn));
                tangent = [-sin(s.phase_rad); cos(s.phase_rad)];
                [Wx2, Wy2] = w36.wind_field(scnW, s.time_s, s.phase_rad);
                wt = Wx2*tangent(1) + Wy2*tangent(2);
                optGnd = min(max(vStarAir + wt, pc.speed_bounds_mps(1)), ...
                    pc.speed_bounds_mps(2));
                rows(end+1,:) = {rowCnt, s.time_s, s.v_ground_mps, curV, ...
                    lastTag, PmeasW/powerScale, out.power_w/powerScale, ...
                    optGnd, PminNormAtV(s.voltage_v), est, rad2deg(s.phase_rad), 0, 0, ...
                    accPeak, abs(dot(out.air_velocity_ne_mps, tangent)), ...
                    Wx2, Wy2, s.position_ne_m(1), s.position_ne_m(2)}; %#ok<AGROW>
                accPeak = 0;
            end
        end
        PmChunk = psum/nInner;
    end
    function tb = table()
        tb = cell2table(rows, 'VariableNames', {'step','time','speed','speedCmd', ...
            'tag','powerMeas','powerTrue','optimumTrue','minPowerTrue','estimate', ...
            'headingDeg','shiftDx','shiftDy','accelMax','airspeed','windX','windY', ...
            'posX','posY'});
    end
end

function [uuV, JV] = local_curveJV(pc, V)
% 任务3.8: 参数化电压的真值曲线(与 harness adapter truth() 同式, 端电压显式传入)
vv = linspace(pc.speed_bounds_mps(1), pc.speed_bounds_mps(2), 801);
nce = pc.ceiling_kn_rpm_per_V * V;
Tce = polyval(pc.bench_T_coef_desc, nce / 1000);
J = zeros(size(vv));
for i = 1:numel(vv)
    aD = 0.5 * pc.air_density_kgpm3 * pc.cda_m2 * vv(i)^2 / pc.mass_kg;
    th = atan(aD / pc.gravity_mps2);
    Trot = pc.mass_kg * pc.gravity_mps2 / (8 * cos(th) * pc.gravity_mps2);
    n = local_n_of_t38(pc, min(Trot, Tce));
    Pc = local_p_coef38(pc, V);
    pro = polyval(Pc, n) - local_ind_saving38(pc, Trot * pc.gravity_mps2, vv(i));
    dLo = pc.coaxial_delta_base * local_vi_ratio38(pc, Trot * pc.gravity_mps2, vv(i))^pc.coaxial_decay_kappa;
    Pmot = pc.arm_count * (pro + pro * (1 + dLo));
    Pdrag = 0.5 * pc.air_density_kgpm3 * pc.cda_m2 * vv(i)^3;
    J(i) = Pmot + Pdrag + pc.aux_power_W;
end
uuV = vv; JV = J;
end
function n = local_n_of_t38(pc, t)
b = pc.bench_T_coef_desc;
r = roots([b(1), b(2), b(3) - t]); r = r(imag(r) < 1e-9 & real(r) > 0); n = min(real(r));
if isempty(n) || ~isfinite(n), n = 0; end
end
function Pc = local_p_coef38(pc, V)
V = min(max(V, pc.bench_V_nom(1)), pc.bench_V_nom(end));
i = find(pc.bench_V_nom <= V, 1, 'last'); j = min(i + 1, numel(pc.bench_V_nom));
if i == j, Pc = pc.bench_P_coef(i, :); return; end
w = (V - pc.bench_V_nom(i)) / (pc.bench_V_nom(j) - pc.bench_V_nom(i));
Pc = (1 - w) * pc.bench_P_coef(i, :) + w * pc.bench_P_coef(j, :);
end
function [vi, vi0] = local_vi38(pc, T_N, vair)
vi = 0; vi0 = 0;
if T_N <= 0 || vair <= 0, return; end
A = pi * (pc.prop_diameter_m^2) / 4; k = T_N / (2 * pc.air_density_kgpm3 * A);
vi0 = sqrt(k); vi = sqrt((vair/2)^2 + k) - vair/2;
end
function ratio = local_vi_ratio38(pc, T_N, vair)
[vi, vi0] = local_vi38(pc, T_N, vair);
if vi0 > 0, ratio = vi / vi0; else, ratio = 0; end
end
function sv = local_ind_saving38(pc, T_N, vair)
[vi, vi0] = local_vi38(pc, T_N, vair);
sv = max(0, pc.h3_induced_gain * T_N * (vi0 - vi));
end
