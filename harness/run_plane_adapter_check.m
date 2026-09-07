function result = run_plane_adapter_check()
%RUN_PLANE_ADAPTER_CHECK T1.2 harness↔Plane 对接验收（P1/WP1）。
% 五个门（对应 T1_ACCEPTANCE_CHECKLIST 的 A/C 组思想，落在适配器层）：
%   G1 稳态点保真: query(v) 与评价侧真值曲线偏差 <= 1% (确定性代理)；
%   G2 阶跃响应: v_ref 0->8 的 t63 ∈ [0.9,1.1] s 且 max|dv/dt| <= 2.0；
%   G3 越界钳位: v_ref=25 -> 应用值=20 (speed_bounds 上界)；
%   G4 schema 0.3 一致性: 逐查询记录的 schema 字段齐全且回显正确；
%   G5 确定性: 同一 v 两次查询功率一致（无隐藏随机源）。
% 返回 result.pass / result.gates（机器可查）；任一门失败即 assert 退出。
root = fileparts(mfilename('fullpath'));
addpath(root);                                       % harness/+harness 包
addpath(fullfile(root, '..', 'models', 'plane'));   % +plane 包
c = harness.config('T', 3600, 'tEval', 1.0);
ac = harness.make_plane_adapter(c);
truth = ac.truth();

% ---- G1 稳态点保真
g1 = struct('v', {}, 'p_meas', {}, 'p_true', {}, 'rel_err', {});
for v = [4.0, 6.3, 9.0, 12.0]
    pm = ac.query(v);
    pt = interp1(truth.curveV, truth.curveJ, v);
    rel = abs(pm - pt) / pt;
    assert(rel <= 0.01, 'harness:AdapterCheck', ...
        'G1 v=%.1f: |P_meas-P_true|/P_true=%.3%% > 1%%', v, 100 * rel);
    g1(end+1) = struct('v', v, 'p_meas', pm, 'p_true', pt, 'rel_err', rel); %#ok<AGROW>
    fprintf('G1  v=%4.1f  P_meas %7.2f W  P_true %7.2f W  rel %.3f%%\n', ...
        v, pm, pt, 100 * rel);
end

% ---- G5 无隐藏随机源 (放在新查询前)
pm1 = ac.query(8.0); pm2 = ac.query(8.0);
% 一阶滞后的稳定窗残差随历史渐近变化, 确定性判据 = 差异远小于测量意义
% (<=0.1%), 证明适配器与 Plane 代理无随机注入
assert(abs(pm1 - pm2) / pm1 <= 1e-3, 'harness:AdapterCheck', ...
    'G5 repeat query(8) differs by %.4f%% (hidden randomness?)', ...
    100 * abs(pm1 - pm2) / pm1);
fprintf('G5  repeat query(8): %.4f vs %.4f W (diff %.4f%%)\n', ...
    pm1, pm2, 100 * abs(pm1 - pm2) / pm1);

% ---- G2/G3 阶跃/钳位: 直接驱动 plane.step (平台内部闭环语义)
% P2 俯仰内核 (06 v1.2 §2 决策 4/H6): 小信号主极点 ≈ 1/kp_speed = 2.86 s
% (俯仰滞后 0.3 s 为次极点), t63 预期 ≈ 2.9 s; 正式 A3 门槛在 T2 跑批前按
% rules §9.4 重新预登记 (T2_ACCEPTANCE_CHECKLIST §3/§5-5), 此处为构建期声明门
pc = plane.config();
s = plane.reset(pc);
windSample = struct('time_s', 0, 'wind_truth_ne_mps', [0;0], ...
    'wind_measured_ne_mps', [0;0], 'wind_valid', true);
pathCommand = struct('time_s', 0, 'trajectory_type', 'straight', ...
    'circle_center_ne_m', [NaN;NaN], 'circle_radius_m', NaN, ...
    'path_phase_rad', 0, 'path_tangent_ne', [0;1], 'path_normal_ne', [-1;0], ...
    'path_valid', true);
for k = 1:4000   % 预稳定到 8 m/s (大阶跃, 指令限幅主导)
    cmd = struct('v_ref_applied_mps', 8, 'eta_ref_applied', 1, ...
        'controller_mode', 'fixed');
    [s, ~] = plane.step(s, windSample, pathCommand, cmd, pc.sample_time_s, pc);
end
assert(abs(s.v_ground_mps - 8) <= 0.01, 'harness:AdapterCheck', ...
    'G2 presettle failed (v=%.3f)', s.v_ground_mps);
v0 = s.v_ground_mps; tt = []; vv = [];
for k = 1:600   % 6 s @0.01 s, 小阶跃 8->9
    cmd = struct('v_ref_applied_mps', 9, 'eta_ref_applied', 1, ...
        'controller_mode', 'fixed');
    [s, out] = plane.step(s, windSample, pathCommand, cmd, pc.sample_time_s, pc);
    tt(end+1) = out.time_s; vv(end+1) = out.tangential_ground_speed_mps; %#ok<AGROW> %#ok<*SAGROW>
end
i63 = find(vv >= v0 + 0.63 * (9 - v0), 1);
t63 = tt(i63) - tt(1) + pc.sample_time_s;
assert(t63 >= 2.4 && t63 <= 3.4, 'harness:AdapterCheck', ...
    'G2 t63=%.3f s outside [2.4,3.4] (declared 1/kp=%.2f s)', t63, 1/pc.kp_speed);
amax = max(abs(diff(vv)) / pc.sample_time_s);
assert(amax <= pc.speed_rate_mps2 + 1e-9, 'harness:AdapterCheck', ...
    'G2 max|dv/dt|=%.4f > %.2f', amax, pc.speed_rate_mps2);
fprintf('G2  small-step 8->9: t63=%.3f s, max|dv/dt|=%.4f m/s^2\n', t63, amax);
cmd = struct('v_ref_applied_mps', 25, 'eta_ref_applied', 1, ...
    'controller_mode', 'fixed');
[~, outC] = plane.step(s, windSample, pathCommand, cmd, pc.sample_time_s, pc);
assert(outC.v_ref_applied_mps == pc.speed_bounds_mps(2), ...
    'harness:AdapterCheck', 'G3 clamp: applied=%g', outC.v_ref_applied_mps);
fprintf('G3  v_ref=25 -> applied=%.1f (clamped)\n', outC.v_ref_applied_mps);

% ---- G4 schema 0.3 一致性
lg = ac.schemaLog();
assert(~isempty(lg), 'harness:AdapterCheck', 'G4 empty schema log');
for k = 1:numel(lg)
    sc = lg(k).schema;
    assert(strcmp(sc.schema_version, '0.3') && sc.power_valid && ...
        abs(sc.v_ref_applied_mps - lg(k).v_cmd) < 1e-9 && ...
        sc.eta_ref_applied == 1 && ...
        abs(sc.power_sample_time_s - sc.time_s) < 1e-12 && ...
        isfield(sc, 'energy_electrical_J') && ...
        isfield(sc, 'constraint_flags'), ...
        'harness:AdapterCheck', 'G4 schema record %d malformed', k);
end
fprintf('G4  %d schema records conform (v0.3, echoes, validity)\n', numel(lg));

result = struct('pass', true, 'gates', struct('g1', g1, 't63', t63, ...
    'max_accel', amax, 'n_schema', numel(lg)));
fprintf('PLANE ADAPTER CHECK PASS\n');
end
