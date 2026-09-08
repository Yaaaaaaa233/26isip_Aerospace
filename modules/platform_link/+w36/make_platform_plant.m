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
% 功率归一: 除以平台悬停功率(真值曲线 J(0)), 算法侧 hover≈1 口径与 3.5 一致。
% 依赖: models/plane(+plane) 与 harness(+harness) 在 MATLAB path(平台线仓库)。
if nargin<1, c=w36.config(); end
root=fileparts(mfilename('fullpath')); repoRoot=fullfile(root,'..','..','..','26isip_Aerospace');
if exist('plane.config','file')~=2
    dst=fullfile(tempdir,'t36_plane_fallback');
    if exist(fullfile(dst,'+plane','config.m'),'file')~=2
        if exist(dst,'dir'), rmdir(dst,'s'); end
        copyfile(fullfile(repoRoot,'models','plane'),dst);
    end
    addpath(dst);
end
if exist('harness.make_plane_adapter','file')~=2
    dst2=fullfile(tempdir,'t36_harness_fallback');
    if exist(fullfile(dst2,'+harness','make_plane_adapter.m'),'file')~=2
        if exist(dst2,'dir'), rmdir(dst2,'s'); end
        copyfile(fullfile(repoRoot,'harness'),dst2);
    end
    addpath(dst2);
end
assert(exist('plane.config','file')==2,'w36:PlatformPlant','找不到平台对象 models/plane/+plane, 请检查仓库路径。');
assert(strcmp(c.backend,'platform'),'w36:PlatformPlant','本后端仅用于 backend=platform。');
assert(abs(c.tEval-1.0)<1e-12,'w36:PlatformPlant','平台后端要求 tEval=1.0s(预算按秒)。');
pc = plane.config('circle_radius_m', c.turnRadius);
dt = pc.sample_time_s;
stepPerSec = round(1.0/dt);
acT = harness.make_plane_adapter(struct('powerScaleW', 1), struct());
ttA = acT.truth();
uu = ttA.curveV(:); JJ = ttA.curveJ(:);
[PminW, ~] = min(JJ); vStarAir = uu(find(JJ==PminW,1));
hoverW = JJ(1); powerScale = hoverW;
cW = c; cW.duration = ceil((c.evalSeconds+240)/c.tEval);
scnW = w36.scenario('static', cW);
s = plane.reset(pc);
est = c.initialSpeed; lastTag = 'init'; curV = c.initialSpeed;
tHist = []; pHist = [];
rows = {}; rowCnt = 0; secMarker = floor(s.time_s);
accPeak = 0; vPrev = s.v_ground_mps;
plt = struct('q', @q, 'amendEstimate', @amendEstimate, 'count', @count, ...
    'table', @table, 'truth', @truth, 'windAt', @windAt, 'planeCfg', pc);
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
        Pm = adv(stepPerSec);
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
                    optGnd, PminW/powerScale, est, rad2deg(s.phase_rad), 0, 0, ...
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
