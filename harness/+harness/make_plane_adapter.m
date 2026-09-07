function ac = make_plane_adapter(c, pc)
%MAKE_PLANE_ADAPTER T1.2：用统一 Plane 对象替换 task2 静态黑箱代理。
% 把 models/plane/+plane 的 P0-P4 契约对象包装成 harness 的飞机接口：
%   ac.query(v)   -> P_meas  开环指令 v_ref=v（eta_ref=1，ZOH 保持），步进
%                    Plane 直到速度进入稳定带（|v-v_ref|<=settleTol 连续
%                    settleTau*speed_tau_s），返回稳定窗（quietWin 秒）内
%                    功率均值。每个评估点 = 平台闭环速度跟踪的一个稳态
%                    工作点（T1 口径：策略开环给参考，平台内部闭环）。
%   ac.gauges()   -> 结构体：speed(切向地速)/power(最近功率)/soc/energy_J。
%   ac.truth()    -> 评价侧：plane 代理功率模型在速度域的真值曲线 +
%                    数值 vStar/Pmin（只进评价日志，红线 1）。
%   ac.schemaLog()-> 逐查询的 schema 0.3 输出记录（验收机器指标用）。
%   ac.state()    -> 内部 Plane 状态（验收侧）。
% 与 task2 代理的差异（登记）：Plane 功率模型确定性（无 task2 噪声/崎岖项），
% 测量噪声属平台测量链，不在本适配器注入；风经 make_environment 注入 step。
if nargin < 2, pc = struct(); end
if isfield(c, 'planeCfg') && isstruct(c.planeCfg)
    f = fieldnames(c.planeCfg);
    for k = 1:numel(f), pc.(f{k}) = c.planeCfg.(f{k}); end
end
f = fieldnames(pc);
pairs = cell(1, 2 * numel(f));
for k = 1:numel(f), pairs{2*k-1} = f{k}; pairs{2*k} = pc.(f{k}); end
pc = plane.config(pairs{:});   % empty pc -> all defaults
settleTol = 0.05;                       % 速度稳定带 [m/s]
settleHold = round(4.0 * pc.speed_tau_s / pc.sample_time_s);  % 连续保持步数
quietWin = max(1, round(0.5 / pc.sample_time_s));             % 测量窗步数
maxSteps = 100000;
s = plane.reset(pc);
lastPower = NaN; lastSpeed = NaN;
log = struct('t', {}, 'v_cmd', {}, 'power_w', {}, 'energy_J', {}, ...
    'schema', {});
windSample = struct('time_s', 0, 'wind_truth_ne_mps', [0;0], ...
    'wind_measured_ne_mps', [0;0], 'wind_valid', true);
pathCommand = struct('time_s', 0, 'trajectory_type', 'straight', ...
    'circle_center_ne_m', [NaN;NaN], 'circle_radius_m', NaN, ...
    'path_phase_rad', 0, 'path_tangent_ne', [0;1], 'path_normal_ne', [-1;0], ...
    'path_valid', true);
ac = struct('query', @query, 'gauges', @gauges, 'truth', @truth, ...
    'schemaLog', @schemaLog, 'state', @state, 'planeCfg', pc);

    function Jm = query(v)
        v = min(pc.speed_bounds_mps(2), max(pc.speed_bounds_mps(1), double(v)));
        pbuf = []; holdCnt = 0;
        for it = 1:maxSteps
            cmd = struct('v_ref_applied_mps', v, 'eta_ref_applied', 1, ...
                'controller_mode', 'fixed');
            [s, out] = plane.step(s, windSample, pathCommand, cmd, ...
                pc.sample_time_s, pc);
            windSample.time_s = s.time_s; pathCommand.time_s = s.time_s;
            assert(all(isfinite([s.v_ground_mps, out.power_w])), ...
                'harness:PlaneAdapter', 'plane diverged at v_ref=%.2f', v);
            pbuf(end+1) = out.power_w; %#ok<AGROW>
            if abs(s.v_ground_mps - v) <= settleTol
                holdCnt = holdCnt + 1;
                if holdCnt >= settleHold, break; end
            else
                holdCnt = 0;
            end
        end
        assert(holdCnt >= settleHold, 'harness:PlaneAdapter', ...
            'speed did not settle at v_ref=%.2f', v);
        Jm = mean(pbuf(end-quietWin+1:end));
        lastPower = Jm; lastSpeed = s.v_ground_mps;
        log(end+1) = struct('t', s.time_s, 'v_cmd', v, 'power_w', Jm, ...
            'energy_J', s.energy_electrical_J, 'schema', out); %#ok<AGROW>
    end

    function g = gauges()
        g.speed = lastSpeed; g.power = lastPower;
        g.soc = s.soc; g.energy_J = s.energy_electrical_J;
    end

    function out = truth()
        % 评价侧真值: 与 plane.step 同一代理模型 (eta_actual=1, 静风):
        % P = hover + speed_gain*(v-6)^2 + drag_gain*v^2 + aux
        vv = linspace(pc.speed_bounds_mps(1), pc.speed_bounds_mps(2), 801);
        J = pc.hover_power_W + pc.speed_power_gain_W_per_mps2*(vv-6).^2 ...
            + pc.drag_power_gain_W_per_mps2*vv.^2 + pc.aux_power_W;
        [Jmin, i] = min(J);
        out.curveV = vv; out.curveJ = J;
        out.vStar = vv(i); out.PminW = Jmin;
        out.PminNorm = Jmin / c.powerScaleW;
    end

    function lg = schemaLog(), lg = log; end
    function st = state(), st = s; end
end
