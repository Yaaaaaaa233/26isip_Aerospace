function result = run_p2_chain_check()
%RUN_P2_CHAIN_CHECK P2 物理链条机器门检查（T2_ACCEPTANCE_CHECKLIST §2 单测级）。
%   覆盖：D6 合成恒等 / D7 分配自洽与 shortfall / D8 电池四门 / E 标准饱和负向
%   （bit4 与 bit0 分层）/ D5 台架域 / eta 方向 / 接口不变式。门槛数值即清单
%   §2 登记值；正式 T2 验收图集由 harness 导出（WP6），本检查是构建期机器门。
addpath(fileparts(mfilename('fullpath')));
res = local_run();
result = struct('pass', res.pass, 'checks', {res.rows});
if res.pass
    fprintf('P2 CHAIN CHECK PASS (%d gates)\n', numel(res.rows));
else
    fprintf('P2 CHAIN CHECK FAIL (%d gates, see rows above)\n', numel(res.rows));
end
end

function res = local_run()
rows = cell(0, 1);
pass = true;
    function ok(tag, name, gate, detail)
        pass = pass && gate;
        rows{end+1, 1} = struct('tag', tag, 'name', name, 'pass', gate, 'detail', detail); %#ok<AGROW>
        fprintf('%s %-6s %-46s %s\n', local_mark(gate), tag, name, detail);
    end
c = plane.config();
w0 = struct('time_s', 0, 'wind_truth_ne_mps', [0; 0], 'wind_measured_ne_mps', [0; 0], 'wind_valid', true);
pathC = struct('time_s', 0, 'trajectory_type', 'circle', 'circle_center_ne_m', [0; 0], ...
    'circle_radius_m', 100, 'path_phase_rad', 0, 'path_tangent_ne', [0; 1], ...
    'path_normal_ne', [-1; 0], 'path_valid', true);

% ---------- 接口不变式 + 悬停锚点 ----------
s = plane.reset(c);
cmd0 = struct('v_ref_applied_mps', 0, 'eta_ref_applied', 1, 'controller_mode', 'fixed');
[s, o0] = plane.step(s, w0, pathC, cmd0, 0.01, c);
req = {'power_w', 'power_sample_time_s', 'power_valid', 'tangential_ground_speed_mps', ...
    'position_ne_m', 'path_phase_rad', 'energy_electrical_J', 'soc', ...
    'constraint_flags', 'v_ref_applied_mps', 'eta_ref_applied', 'voltage_v', 'current_a'};
hasAll = all(isfield(o0, req));
ok('G-INT', '接口必填字段齐全(SIM_ALGO §5)', hasAll, sprintf('%d/%d', nnz(isfield(o0, req)), numel(req)));
ok('G-HOV', '悬停总推力 = mg（theta=0, v=0）', abs(o0.thrust_total_actual_n - c.mass_kg * c.gravity_mps2) < 1e-9, ...
    sprintf('T=%.6f N (mg=%.1f)', o0.thrust_total_actual_n, c.mass_kg * c.gravity_mps2));
Phover = o0.power_demand_w;
ok('G-HOV', '悬停功率量级锚定台架（400-650 W）', Phover > 400 && Phover < 650, sprintf('%.1f W', Phover));

% ---------- D6 合成恒等 + D7 非饱和自洽（巡航段仿真） ----------
c1 = c; c1.az_cmd_mps2 = 0;
s = plane.reset(c1);
cmd = struct('v_ref_applied_mps', 8, 'eta_ref_applied', 1, 'controller_mode', 'fixed');
N1 = 3000; satAny = false; socPrev = 1; socMono = true; eInt = 0; eMax = 0;
maxRpm = 0; minRpm = 1e9; ident = 0; d7a = 0; d7b = 0;
for k = 1:N1
    [s, o] = plane.step(s, w0, pathC, cmd, 0.01, c1);
    eInt = eInt + o.power_w * 0.01; eMax = max(eMax, abs(o.energy_electrical_J - eInt));
    stack = sum(o.motor_power_w);
    va = abs(o.tangential_ground_speed_mps);   % 切向空速（本场景 W=0：=切向地速）
    drag = 0.5 * c1.air_density_kgpm3 * c1.cda_m2 * va * va * abs(va);
    ident = max(ident, abs(stack + max(drag, 0) + c1.aux_power_W - o.power_demand_w) / max(o.power_demand_w, 1));
    d7a = max(d7a, abs(o.thrust_total_actual_n - o.thrust_total_demand_n));
    d7b = max(d7b, abs(o.thrust_total_demand_n - c1.mass_kg * c1.gravity_mps2 / max(cos(o.pitch_rad), 0.3)));
    if ~o.rpm_saturation && ~s.cutoff
        maxRpm = max(maxRpm, max(o.motor_rpm)); minRpm = min(minRpm, min(o.motor_rpm(o.motor_rpm > 0)));
    end
    satAny = satAny || o.rpm_saturation;
    socMono = socMono && (o.soc <= socPrev + 1e-14); socPrev = o.soc;
end
ok('G-D6', 'Σ每电机功率+废阻+辅助 = 总需求（≤1e-9 相对）', ident <= 1e-9, sprintf('%.2e', ident));
ok('G-D6', '能量对账 E vs ∫P dt（≤1e-6 相对）', eMax / max(eInt, 1) <= 1e-6, sprintf('%.2e', eMax / max(eInt, 1)));
ok('G-D8', 'SOC 单调', socMono, 'monotone');
ok('G-D5', '非饱和转速落在台架拟合域 [252,1140] RPM', ~satAny && maxRpm <= 1140 + 1e-9 && minRpm >= 252 - 1e-9, ...
    sprintf('[%.0f, %.0f] RPM, sat=%d', minRpm, maxRpm, satAny));
ok('G-D7', '非饱和 ΣT_actual = ΣT_demand（巡航全段 ≤1e-9 N）', d7a <= 1e-9, sprintf('%.1e N', d7a));
ok('G-D7', '需求推力 = m·g/cosθ（俯仰链守恒 ≤1e-9 N）', d7b <= 1e-9, sprintf('%.1e N', d7b));

% ---------- D8 电池链：OCV 恒等式 + 截止锁存 ----------
c2 = c; c2.battery_capacity_Ah = 0.15;   % 演示缩放：数分钟内呈现跌落全程
s = plane.reset(c2); s.voltage_v = c2.battery_n_ser * interp1(c2.battery_ocv_soc, c2.battery_ocv_cell_V, 1);
cmd = struct('v_ref_applied_mps', 8, 'eta_ref_applied', 1, 'controller_mode', 'fixed');
ocvMax = 0; vMin = 30; cutStep = -1; pAfterCut = -1; vAfter = -1; latchOK = true;
for k = 1:4000
    [s, o] = plane.step(s, w0, pathC, cmd, 0.01, c2);
    if ~s.cutoff   % IR 恒等式只在截止前成立（触发拍 V 钳窗沿、截止后 P=0）
        ocvMax = max(ocvMax, abs(o.voltage_v + o.current_a * c2.battery_resistance_ohm - o.open_circuit_V));
    end
    vMin = min(vMin, o.voltage_v);
    if s.cutoff && cutStep < 0, cutStep = k; pAfterCut = o.power_w; vAfter = o.voltage_v; end
    if cutStep > 0 && k > cutStep   % 触发拍 plant 完成功率结算（T1 bit7 同语义），闩锁从下拍起
        latchOK = latchOK && (o.power_w == 0) && (o.voltage_v <= c2.battery_cutoff_V + 1e-12);
    end
end
ok('G-D8', 'IR 压降恒等式 V+IR=OCV(soc)（≤1e-9 V）', ocvMax <= 1e-9, sprintf('%.1e V', ocvMax));
ok('G-D8', 'V_pack ∈ [19.6,29.4]（触发拍容差 0.05，窗沿显示归量化层）', vMin >= c.battery_cutoff_V - 0.05, sprintf('Vmin=%.4f', vMin));
ok('G-D8', '截止触发且 P=0 闩锁', cutStep > 0 && latchOK, sprintf('cut@%d, P=%.0f, V=%.2f', cutStep, pAfterCut, vAfter));

% ---------- E 标准饱和负向：满电 vs 亏电，同指令（含爬升需求 az=2） ----------
cmdAgg = struct('v_ref_applied_mps', 12, 'eta_ref_applied', 1, 'controller_mode', 'fixed');
cF = c; cF.az_cmd_mps2 = 2.0;
sF = plane.reset(cF);
satF = 0;
for k = 1:6000
    [sF, oF] = plane.step(sF, w0, pathC, cmdAgg, 0.01, cF);
    satF = satF + oF.rpm_saturation;
end
cE = c; cE.az_cmd_mps2 = 2.0; cE.battery_capacity_Ah = 0.55;  % 亏电臂：容量演示缩放
sE = plane.reset(cE);
% 预放电至深跌区（V<=20.6 V，平台场景注入；H9=38.8 时饱和触发窗为 V∈(19.6,~20.5)）
cmdD = struct('v_ref_applied_mps', 8, 'eta_ref_applied', 1, 'controller_mode', 'fixed');
for k = 1:20000
    [sE, ~] = plane.step(sE, w0, pathC, cmdD, 0.01, cE);
    if sE.voltage_v <= 20.6, break; end
end
vPre = sE.voltage_v;
satSteps = []; badCmd = 0; ceilErr = 0;
for k = 1:4000
    [sE, oE] = plane.step(sE, w0, pathC, cmdAgg, 0.01, cE);
    if oE.rpm_saturation
        satSteps(end+1) = k; %#ok<AGROW>
        badCmd = badCmd + (abs(oE.command_accel_mps2) >= cE.speed_rate_mps2 - 1e-12); % 指令位不得亮
        ceilErr = max(ceilErr, abs(oE.thrust_total_actual_n - oE.thrust_ceiling_n));  % 封顶精确
    end
    if sE.cutoff, break; end
end
ok('G-E', '满电臂（含爬升需求）零饱和', satF == 0, sprintf('sat=%d 步', satF));
ok('G-E', '亏电臂饱和触发（bit4）', ~isempty(satSteps), sprintf('V预放=%.2f V, %d 步饱和', vPre, numel(satSteps)));
ok('G-E', '饱和时指令限幅位不亮（分层）', badCmd == 0, sprintf('违规 %d 步', badCmd));
ok('G-E', '饱和时 ΣT 精确封顶在 H9 上限', ceilErr <= 1e-9, sprintf('%.1e N', ceilErr));

% ---------- eta 方向（D5 人工核对的机器侧） ----------
cE1 = c; cE1.eta_tau_s = 1e-3; cE1.eta_rate_s = 100;  % eta 快速到达，隔离比较
sA = plane.reset(cE1); sB = plane.reset(cE1);
cmdA = struct('v_ref_applied_mps', 8, 'eta_ref_applied', 1.0, 'controller_mode', 'fixed');
cmdB = struct('v_ref_applied_mps', 8, 'eta_ref_applied', 0.9, 'controller_mode', 'fixed');
for k = 1:500
    [sA, oA] = plane.step(sA, w0, pathC, cmdA, 0.01, cE1);
    [sB, oB] = plane.step(sB, w0, pathC, cmdB, 0.01, cE1);
end
dEta = abs(sB.eta_actual - 0.9);
diffB = max(oB.motor_rpm(1:2:end)) - min(oB.motor_rpm(2:2:end));   % 上-下转速差动
diffA = max(oA.motor_rpm(1:2:end)) - min(oA.motor_rpm(2:2:end));
ok('G-ETA', 'eta_ref=0.9 到位', dEta < 1e-6, sprintf('eta=%.6f', sB.eta_actual));
ok('G-ETA', 'eta<1 上下桨转速差动出现且方向正确（上快）', diffB > 0 && diffA == 0, ...
    sprintf('Δrpm=%.0f（eta=1 时 %.0f）', diffB, diffA));
% E5 重锚（T24 方案 §4；v1.1 删除回中项后谷底成为模型输出）：悬停三点序
% P(0.90)<P(1.00)<P(1.10) —— 左支右支方向 + 谷底低于 eta=1（文献锚 ~0.90）
hEta = [0.90, 1.00, 1.10]; hP = zeros(size(hEta));
for gi = 1:3
    sH = plane.reset(cE1);
    cmdH = struct('v_ref_applied_mps', 0, 'eta_ref_applied', hEta(gi), 'controller_mode', 'fixed');
    for k = 1:500
        [sH, oH] = plane.step(sH, w0, pathC, cmdH, 0.01, cE1);
    end
    hP(gi) = oH.power_demand_w;
end
ok('G-ETA', '悬停 P(0.90)<P(1.00)<P(1.10)（E5 重锚：谷底左移 ~0.90）', ...
    hP(1) < hP(2) && hP(2) < hP(3), ...
    sprintf('%.2f / %.2f / %.2f W', hP(1), hP(2), hP(3)));

% ---------- G-U U 形存在性（H3 前进比修正是否接入的机器门） ----------
% T2 清单 §2 D6"谷底形态合理"的机器化：稳态 P(v) 扫描（1 m/s 分辨率），
% 谷底必须严格内点且相对悬停降幅 >=3%。2026-09-08 全项目重验收时新增
% （此前 20 门未覆盖此性质，H3 缺口漏过即为该盲区后果）；2026-09-08
% 叶安拍板动量理论修复后本门转绿，正式门槛随 T2 清单 v1.1 登记。
vGrid = 0:1:14;
Pq = local_pcurve(c, vGrid, w0, pathC);
[Pmin, iMin] = min(Pq);
uShapeOK = (iMin > 1 && iMin < numel(vGrid)) && Pmin <= 0.97 * Pq(1);
ok('G-U', 'U 形存在性：v* 严格内点且 P(v*)<=0.97*P(0)', uShapeOK, ...
    sprintf('v*=%g m/s, Pmin=%.1f W, P(0)=%.1f W, 降幅=%.1f%%', ...
    vGrid(iMin), Pmin, Pq(1), 100 * (1 - Pmin / Pq(1))));
% H3 敏感性（报告值，不设门——缺省+敏感性等级，06 §3.1 H3 义务）
for gg = [0.7, 1.3]
    cg = c; cg.h3_induced_gain = gg;
    vg = 0:2:14;
    Pg = local_pcurve(cg, vg, w0, pathC);
    [~, ig] = min(Pg);
    ok('G-U', sprintf('H3 敏感性报告：gain=%.1f 的 v* 与降幅', gg), true, ...
        sprintf('v*=%g m/s, 降幅=%.1f%%', vg(ig), 100 * (1 - Pg(ig) / Pg(1))));
end

% ---------- G-B1n 法向风无功率后果（06 §2 决策 3 的机器门，2026-09-08 首跑发现
%           w_n 泄漏进功率（2D 模长）后增设） ----------
pathS = struct('time_s', 0, 'trajectory_type', 'straight', ...
    'circle_center_ne_m', [NaN; NaN], 'circle_radius_m', NaN, ...
    'path_phase_rad', 0, 'path_tangent_ne', [0; 1], ...
    'path_normal_ne', [-1; 0], 'path_valid', true);
sA = plane.reset(c);
sB = plane.reset(c);
wA0 = struct('time_s', 0, 'wind_truth_ne_mps', [0; 0], 'wind_measured_ne_mps', [0; 0], 'wind_valid', true);
wB0 = wA0; wB0.wind_truth_ne_mps = [3; 0];  % 纯法向（切向 [0;1] 的法向 = 东）
cmdB = struct('v_ref_applied_mps', 8, 'eta_ref_applied', 1, 'controller_mode', 'fixed');
for k = 1:3000
    [sA, oAn] = plane.step(sA, wA0, pathS, cmdB, 0.01, c);
    [sB, oBn] = plane.step(sB, wB0, pathS, cmdB, 0.01, c);
end
dPn = abs(oAn.power_w - oBn.power_w) / max(oAn.power_w, 1);
ok('G-B1n', '纯法向风功率后果 = 0（决策 3，≤1e-12 相对）', dPn <= 1e-12, sprintf('%.1e', dPn));

% ---------- 分块插值合理性 ----------
c3 = c; pc21 = local_p_coef_at(c3, 21); pc27 = local_p_coef_at(c3, 27); pc24 = local_p_coef_at(c3, 24);
p21 = polyval(pc21, 0.8); p27 = polyval(pc27, 0.8); p24 = polyval(pc24, 0.8);
ok('G-D6', 'P(n;V) 块间插值单调合理', p24 > min(p21, p27) && p24 < max(p21, p27), ...
    sprintf('P(0.8krpm): %.1f/%.1f/%.1f W @21/24/27V', p21, p24, p27));

res.rows = rows; res.pass = pass;
end

function m = local_mark(ok)
if ok, m = '[PASS]'; else, m = '[FAIL]'; end
end
function Pq = local_pcurve(c, vGrid, w0, pathC)
% 稳态 P(v) 扫描：每点 settle（|v-v_ref|<=0.05 连续 4 s）后取 0.5 s 静默窗均值
Pq = zeros(size(vGrid));
for gi = 1:numel(vGrid)
    sU = plane.reset(c);
    cmdU = struct('v_ref_applied_mps', vGrid(gi), 'eta_ref_applied', 1, 'controller_mode', 'fixed');
    holdCnt = 0; pbuf = [];
    for k = 1:15000
        [sU, oU] = plane.step(sU, w0, pathC, cmdU, 0.01, c);
        pbuf(end+1) = oU.power_w; %#ok<AGROW>
        if abs(sU.v_ground_mps - vGrid(gi)) <= 0.05
            holdCnt = holdCnt + 1;
            if holdCnt >= 400, break; end
        else
            holdCnt = 0;
        end
    end
    Pq(gi) = mean(pbuf(end-49:end));
end
end
function pc = local_p_coef_at(c, V)
V = min(max(V, c.bench_V_nom(1)), c.bench_V_nom(end));
i = find(c.bench_V_nom <= V, 1, 'last'); j = min(i + 1, numel(c.bench_V_nom));
if i == j, pc = c.bench_P_coef(i, :); return; end
w = (V - c.bench_V_nom(i)) / (c.bench_V_nom(j) - c.bench_V_nom(i));
pc = (1 - w) * c.bench_P_coef(i, :) + w * c.bench_P_coef(j, :);
end
