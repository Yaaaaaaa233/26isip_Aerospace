function tests = tests_quad()
%TESTS_QUAD Q2 轨 A 机器门(QUAD_MIGRATION_PLAN 20260921 §5):
%   M2 四旋翼物理不变量(单元):
%     - 悬停恒等式: v=0/无风/theta=0 时 power_w = 4*polyval(bench(V), n(mg/4)) + aux
%       (H3 在 v=0 严格为 0, 悬停=纯台架, 相对差 <=1e-12);
%     - 能量积分: sum(power*dt) vs energy_electrical_J 累计, 相对差 <=1e-12;
%     - 功率平衡: V*I = P 恒等式(电池链构造), 相对差 <=1e-12(对标 x8phys 2.01e-16 先例);
%     - H9 电压跌落上限触发: 低初始电压下 T_ce < T_need -> rpm_saturation=true 且
%       TactN=Tce*4*g(封顶恒等式);
%     - 截止行为: cutoff 后 power=0 / voltage=cutoff_V / aKin=-1;
%   M3 eta/共轴清除完整性:
%     - 静态扫描: +plane_quad 包源码无 eta_split/coaxial 引用;
%     - 行为锚点: motor_* 字段长度 4, 输出无上/下桨成对字段, eta 恒 1(指令 1.2 也被强制 1);
%   附: PWM 诊断派生式与 L0 反解口径一致性(给 Q3 估计链预铺)。
tests = functiontests(localfunctions);
end

%% ---------- M2: 物理不变量 ----------
function test_m2_hover_identity(tc)
% reset 的 dt=0 采样拍 = 精确悬停点(theta=0, V=满电 OCV, 无状态更新),
% 恒等式 4*polyval(bench(V), n(mg/4)) + aux == power_w 可逐位口径验证
pc = plane_quad.config();
[s, sample] = plane_quad.reset(pc);
n = local_n_of_t(pc, pc.mass_kg/pc.motor_count);
Pbench = 4*polyval(local_pcoef(pc, s.voltage_v), n) + pc.aux_power_W;
tc.verifyLessThan(abs(sample.power_w-Pbench)/Pbench, 1e-12, ...
    'M2: 悬停恒等式 4x单桨台架(相对差<=1e-12)');
tc.verifyEqual(max(sample.motor_power_w)-min(sample.motor_power_w), 0, ...
    'M2: 4 电机单桨对称(每电机功率严格相等)');
end

function test_m2_energy_integral(tc)
pc = plane_quad.config();
[s, out] = local_trim(pc, 6, 400); %#ok<NASGU>
% 重跑累计: 逐步推进并积分 power*dt, 与植物能量记账比对
s2 = plane_quad.reset(pc);
dt = pc.sample_time_s; Esum = 0;
for k = 1:round(400/dt)
    [s2, out2] = local_step(s2, pc, 6);
    Esum = Esum + out2.power_w*dt;
end
tc.verifyLessThan(abs(Esum-out.energy_electrical_J)/out.energy_electrical_J, 1e-12, ...
    'M2: 能量积分恒等式(相对差<=1e-12)');
end

function test_m2_power_balance(tc)
% V*I = P 恒等式(电池链构造式), 全程任意拍成立
pc = plane_quad.config();
s = plane_quad.reset(pc);
dt = pc.sample_time_s; worst = 0;
for k = 1:round(200/dt)
    [s, out] = local_step(s, pc, 6);
    if out.power_w > 0
        worst = max(worst, abs(out.voltage_v*out.current_a-out.power_w)/out.power_w);
    end
end
tc.verifyLessThan(worst, 1e-12, 'M2: V*I=P 功率平衡(相对差<=1e-12)');
end

function test_m2_h9_ceiling_trigger(tc)
% 满电下用过载需求推过 T_ce(az_cmd 平台场景注入, 算法接口无此字段):
% T_need/motor = m(g+az)/4 > Tce(full)=3.158 kgf -> rpm_saturation 且推力封顶
pc = plane_quad.config('az_cmd_mps2', 3.0);
s = plane_quad.reset(pc);
[s, out] = local_hold(s, pc, 0, 50);   %#ok<NASGU>
% 用植物末拍实际使用的 nce(out.rpm_ceiling)反推 Tce, 避免参照电压一拍偏差
Tce = max(0, polyval(pc.bench_T_coef_desc, out.rpm_ceiling/1000));
tc.verifyTrue(out.rpm_saturation, 'M2: 过载需求下 H9 上限应触发');
tc.verifyLessThan(abs(out.thrust_total_actual_n-pc.motor_count*Tce*pc.gravity_mps2), 1e-9, ...
    'M2: 触发后实际总推力 = 4*Tce*g(封顶恒等式)');
end

function test_m2_cutoff_behavior(tc)
pc = plane_quad.config();
s = plane_quad.reset(pc, struct('soc', 1e-9));   % SOC 耗尽 -> 截止
[s, out] = local_hold(s, pc, 0, 50); %#ok<NASGU>
tc.verifyTrue(s.cutoff, 'M2: SOC 耗尽应触发截止');
tc.verifyEqual(out.power_w, 0, 'M2: 截止后功率=0');
tc.verifyEqual(out.voltage_v, pc.battery_cutoff_V, 'M2: 截止后端电压=cutoff');
end

%% ---------- M3: eta/共轴清除完整性 ----------
function test_m3_no_eta_coaxial_references(tc)
% 静态扫描门: 只扫 +plane_quad 包源码(测试自身与入口不在扫描域)
pkgDir = fullfile(fileparts(mfilename('fullpath')), '+plane_quad');
srcFiles = [dir(fullfile(pkgDir,'*.m')); dir(fullfile(pkgDir,'private','*.m'))];
tc.verifyGreaterThan(numel(srcFiles), 0, 'M3: 应至少扫描到包内源文件');
tok1 = ['eta' '_split'];   tok2 = ['co' 'axial'];   % 拼接避免测试源码自含敏感词
for i = 1:numel(srcFiles)
    txt = fileread(fullfile(srcFiles(i).folder, srcFiles(i).name));
    tc.verifyFalse(contains(txt, tok1), ...
        sprintf('M3: %s 不得引用 %s', srcFiles(i).name, tok1));
    tc.verifyFalse(contains(txt, tok2), ...
        sprintf('M3: %s 不得引用 %s', srcFiles(i).name, tok2));
end
end

function test_m3_behavioral_anchors(tc)
pc = plane_quad.config();
[~, out] = local_hover(pc, 100);
tc.verifyEqual(numel(out.motor_pwm_us), 4, 'M3: 4 电机单桨, 诊断字段长度=4');
tc.verifyEqual(numel(out.motor_rpm), 4, 'M3: motor_rpm 长度=4');
tc.verifyEqual(numel(out.motor_power_w), 4, 'M3: motor_power_w 长度=4');
fn = fieldnames(out);
% 词元匹配(_up/_lo 作为独立词元; 子串匹配会误中 velocity 的 'lo')
tc.verifyFalse(any(~cellfun(@isempty, regexp(fn, '(^|_)(up|lo)(_|$)'))), ...
    'M3: 输出不得有上/下桨成对字段');
% eta 恒 1: 指令给 1.2 也被强制 1(接口字段保留)
s = plane_quad.reset(pc);
dt = pc.sample_time_s;
ws = struct('time_s',0,'wind_truth_ne_mps',[0;0],'wind_measured_ne_mps',[0;0],'wind_valid',true);
pcmd = struct('trajectory_type','line','path_tangent_ne',[0;1],'path_normal_ne',[-1;0],'path_valid',true);
cmd = struct('v_ref_applied_mps',6,'eta_ref_applied',1.2,'controller_mode','fixed');
for k = 1:100
    ws.time_s = s.time_s + dt;
    [s, out] = plane_quad.step(s, ws, pcmd, cmd, dt, pc);
end
tc.verifyEqual(out.eta_actual, 1, 'M3: eta_actual 恒 1');
tc.verifyEqual(out.eta_ref_applied, 1, 'M3: eta_ref 输出恒 1(指令 1.2 被强制)');
tc.verifyEqual(s.eta_actual, 1, 'M3: 状态 eta 恒 1');
end

%% ---------- 附: PWM 诊断派生式(L0 反解口径, Q3 预铺) ----------
function test_pwm_diagnostic_consistency(tc)
% 植物诊断 pwm = 1000+1000*min(1, RPM/nce) 与 Q1 的 L0 反解口径互逆
pc = plane_quad.config();
[~, out] = local_hover(pc, 100);
frac = (out.motor_pwm_us(1)-1000)/1000;
nHat = frac * out.rpm_ceiling / 1000;   % krpm
tc.verifyLessThan(abs(nHat-out.motor_rpm(1)/1000), 1e-9, ...
    'PWM 诊断与 L0 反解口径一致(非饱和域)');
end

%% ---------- 工具 ----------
function [s, out] = local_hover(pc, secs)
% v=0 悬停推进 secs 秒, 返回末拍
local_check_secs(secs);
s = plane_quad.reset(pc);
[s, out] = local_hold(s, pc, 0, secs);
end

function [s, out] = local_hold(s, pc, vref, secs)
dt = pc.sample_time_s;
out = [];
for k = 1:round(secs/dt)
    [s, out] = local_step(s, pc, vref);
end
end

function [s, out] = local_trim(pc, vref, secs)
s = plane_quad.reset(pc);
[s, out] = local_hold(s, pc, vref, secs);
end

function local_check_secs(secs)
assert(secs>0, 'secs must be positive');
end

function [s, out] = local_step(s, pc, vref)
dt = pc.sample_time_s;
ws = struct('time_s', s.time_s+dt, 'wind_truth_ne_mps',[0;0], ...
    'wind_measured_ne_mps',[0;0],'wind_valid',true);
pcmd = struct('trajectory_type','line','path_tangent_ne',[0;1], ...
    'path_normal_ne',[-1;0],'path_valid',true);
cmd = struct('v_ref_applied_mps',vref,'eta_ref_applied',1,'controller_mode','fixed');
[s, out] = plane_quad.step(s, ws, pcmd, cmd, dt, pc);
end

function n = local_n_of_t(c,t)
b = c.bench_T_coef_desc;
r = roots([b(1),b(2),b(3)-t]); r = r(imag(r)<1e-9 & real(r)>0); n = min(real(r));
if isempty(n)||~isfinite(n), n = 0; end
end

function pc = local_pcoef(c, V)
V = min(max(V, c.bench_V_nom(1)), c.bench_V_nom(end));
i = find(c.bench_V_nom<=V,1,'last'); j = min(i+1, numel(c.bench_V_nom));
if i==j, pc = c.bench_P_coef(i,:); return; end
w = (V-c.bench_V_nom(i))/(c.bench_V_nom(j)-c.bench_V_nom(i));
pc = (1-w)*c.bench_P_coef(i,:) + w*c.bench_P_coef(j,:);
end
