function tests = tests_quad_sim()
%TESTS_QUAD_SIM Q2 轨 B 机器门(QUAD_MIGRATION_PLAN 20260921 §5-M4' + M2 式不变量):
%   - 悬停稳态: v->0, 功率 vs 轨 A 悬停恒等式(同电压处) <=1.5%
%   - V*I=P <=1e-12 与能量积分 <=1e-12(电池链构造式)
%   - 一阶电机滞后: 阶跃后 t=tau 处到达 63.2%(±2%)
%   - M4' 对拍: 6 配平点(2..10 m/s)准稳态 P(v) vs 轨 A 解析曲线 <=1.5%(Jgain=0)
%   - M4' 就位: 5->8 m/s 阶跃, 轨 B/轨 A 就位时间比 <=2x
%   - n 效应复核(声明级, Jgain=3): L0 偏差为正且随空速增大(数据落档, 非门)
%   - 截止行为: SOC 耗尽 -> cutoff
tests = functiontests(localfunctions);
end

function setupOnce(tc)  %#ok<INUSD>
here = fileparts(fileparts(mfilename('fullpath')));   % models/plane_quad
repo = fileparts(here);
addpath(here);
addpath(fullfile(repo,'models','px4_x8'));
end

function test_hover_steady(tc)
R = quad_sim.trim_run([], 0, 20);
tc.verifyLessThan(abs(R.vMean), 0.2, '悬停地速应->0');
P_A = local_trackA_hover(R.Vmean);
tc.verifyLessThan(abs(R.Pmean-P_A)/P_A, 0.015, ...
    '悬停功率 vs 轨 A 恒等式 <=1.5%');
end

function test_battery_identities(tc)
c = quad_sim.config();
s = quad_sim.reset(c,struct('rotor_omega_radps',...
    (local_n_hover(c)*1000*2*pi/60)*ones(4,1)));
dt = c.sample_time_s; worstVI = 0; Esum = 0;
for k = 1:3000
    [~,out0] = quad_sim.step(s,struct('pwm_us',s.last_pwm_us),0,c);
    pwm = quad_sim.ctrl(s,out0,4,c);
    [s,out] = quad_sim.step(s,struct('pwm_us',pwm),dt,c);
    Esum = Esum + out.electrical_power_W*dt;
    if out.electrical_power_W > 0
        worstVI = max(worstVI,abs(out.battery_voltage_V* ...
            out.battery_current_A-out.electrical_power_W)/out.electrical_power_W);
    end
end
tc.verifyLessThan(worstVI,1e-12,'V*I=P <=1e-12');
tc.verifyLessThan(abs(Esum-out.energy_electrical_J)/out.energy_electrical_J,1e-12, ...
    '能量积分 <=1e-12');
end

function test_motor_first_order_lag(tc)
% 两段法: 先跑到收敛得 wT(消电压跌落对目标转速的影响), 再从同初态走 t=tau
% 检查 63.2%(离散几何级数精确等于 1-exp(-1))
c = quad_sim.config();
nH = local_n_hover(c);
wH = nH*1000*2*pi/60;
s = quad_sim.reset(c,struct('rotor_omega_radps',wH*ones(4,1)));
pwmHover = 1000+1000*(nH*1000)/(c.kv_rpm_per_V*29.4);
pwmStep = pwmHover*1.05;
dt = c.sample_time_s;
for k = 1:round(1.0/dt)   % 1 s >> 4*tau, 收敛
    [s,out] = quad_sim.step(s,struct('pwm_us',pwmStep*ones(4,1)),dt,c); %#ok<ASGUU>
end
wT = out.rotor_omega_radps(1);
s2 = quad_sim.reset(c,struct('rotor_omega_radps',wH*ones(4,1)));
for k = 1:round(c.motor_tau_s/dt)
    [s2,out2] = quad_sim.step(s2,struct('pwm_us',pwmStep*ones(4,1)),dt,c); %#ok<ASGUU>
end
frac = (out2.rotor_omega_radps(1)-wH)/(wT-wH);
tc.verifyLessThan(abs(frac-(1-exp(-1))),0.02, ...
    sprintf('t=tau 处应到 63.2%%(实测 %.1f%%)',100*frac));
end

function test_m4p_parity(tc)
vs = [2 4 5 6 8 10];
rel = zeros(size(vs)); Rw = cell(size(vs));
for i = 1:numel(vs)
    Rw{i} = quad_sim.trim_run([],vs(i),40);
    A = plane_quad.steady_curve(plane_quad.config(),Rw{i}.Vmean);
    P_A = interp1(A.v,A.P,Rw{i}.vMean);
    rel(i) = abs(Rw{i}.Pmean-P_A)/P_A;
end
tc.verifyLessThan(max(rel),0.015, ...
    sprintf('M4prime 对拍 6 点最大相对差 %.3f%%',100*max(rel)));
end

function test_m4p_settle_ratio(tc)
RB = quad_sim.trim_run([],8,60,struct('settleFrom',[5 8]));
tA = local_trackA_settle(5,8);
tc.verifyTrue(isfinite(RB.settleS) && isfinite(tA), ...
    sprintf('两侧就位时间有限(B=%.2fs A=%.2fs)',RB.settleS,tA));
tc.verifyLessThan(RB.settleS/tA,2.0, ...
    sprintf('M4'' 就位时间比 %.2f(轨 B %.2fs / 轨 A %.2fs)',RB.settleS/tA,RB.settleS,tA));
end

function test_neffect_declared(tc)
% 声明级代理(Jgain=3, x8phys 前进比功率项)下的 L0 盲性确认:
%   (1) P_L0 在 2-10 m/s 全程平坦(<1.5% 极差) —— 静态映射看不到谷(与 Q1/S3 互证);
%   (2) bias 为驼峰: 谷区(4-6)峰值 > +15%(H3 缺失主导), 高速端翻负(J^2/废阻主导);
%   (3) J^2 项把真值谷底下压(vStar_B(Jgain=3) < 轨 A 的 5.65)。
% 声明边界: 推力侧 n 效应(真实桨前飞转速下降, pwm 携带空速信息的可能来源)
% 不在 x8phys 结构内, 待老师参数(C2) —— 本断言只锁功率侧结论。
vq = [0 2 4 5 6 8 10]; R = cell(size(vq));
for i = 1:numel(vq)
    R{i} = quad_sim.trim_run([],vq(i),40,struct('Jgain',3));
end
PL0 = cellfun(@(x)x.PHatL0,R); bias = cellfun(@(x)x.biasL0_pct,R); Pt = cellfun(@(x)x.Pmean,R);
inBand = vq >= 2 & vq <= 10;
tc.verifyLessThan((max(PL0(inBand))-min(PL0(inBand)))/min(PL0(inBand)),0.015, ...
    sprintf('P_L0 应全程平坦(实测极差 %.2f%%)', ...
    100*(max(PL0(inBand))-min(PL0(inBand)))/min(PL0(inBand))));
tc.verifyGreaterThan(max(bias(vq>=4 & vq<=6)),15, ...
    sprintf('谷区 bias 峰值应 >15%%(实测 %.1f%%)',max(bias(vq>=4 & vq<=6))));
tc.verifyLessThan(bias(vq==10),0, ...
    sprintf('高速端 bias 应翻负(实测 %.1f%%)',bias(vq==10)));
[~,iv] = min(Pt);
tc.verifyLessThan(vq(iv),5.65, ...
    sprintf('Jgain=3 谷底应下压到 <5.65(实测 %.2f)',vq(iv)));
end

function test_cutoff(tc)
c = quad_sim.config();
nH = local_n_hover(c);
s = quad_sim.reset(c,struct('soc',1e-9, ...
    'rotor_omega_radps',(nH*1000*2*pi/60)*ones(4,1)));
[s,out] = quad_sim.step(s,struct('pwm_us',1600*ones(4,1)),0.01,c);   % 触发拍
[~,out] = quad_sim.step(s,struct('pwm_us',1600*ones(4,1)),0.01,c);   % 截止生效拍
tc.verifyTrue(out.object_flags.battery_cutoff,'SOC 耗尽应触发截止');
tc.verifyEqual(out.electrical_power_W,0,'截止后电功率=0');
end

%% ---------- 工具 ----------
function n = local_n_hover(c)
b = c.bench_T_coef_desc; t = c.mass_kg/4;
rr = roots([b(1),b(2),b(3)-t]); rr = rr(imag(rr)<1e-9 & real(rr)>0); n = min(real(rr));
if isempty(n)||~isfinite(n), n = 0; end
end

function P = local_trackA_hover(V)
cA = plane_quad.config();
n = local_n_hover(cA);
P = 4*polyval(local_pcoef(cA,V),n) + cA.aux_power_W;
end

function pc = local_pcoef(c,V)
V = min(max(V,c.bench_V_nom(1)),c.bench_V_nom(end));
i = find(c.bench_V_nom<=V,1,'last'); j = min(i+1,numel(c.bench_V_nom));
if i==j, pc = c.bench_P_coef(i,:); return; end
w = (V-c.bench_V_nom(i))/(c.bench_V_nom(j)-c.bench_V_nom(i));
pc = (1-w)*c.bench_P_coef(i,:)+w*c.bench_P_coef(j,:);
end

function tSettle = local_trackA_settle(v0,v1)
cA = plane_quad.config();
dt = cA.sample_time_s;
s = plane_quad.reset(cA);
ws = struct('time_s',0,'wind_truth_ne_mps',[0;0],'wind_measured_ne_mps',[0;0],'wind_valid',true);
pcmd = struct('trajectory_type','line','path_tangent_ne',[0;1], ...
    'path_normal_ne',[-1;0],'path_valid',true);
for k = 1:round(30/dt)                                 % 先在 v0 配平(无匿名捕获)
    s = local_runA(s,cA,ws,pcmd,v0,1,dt);
end
t0 = s.time_s; runOk = 0; tSettle = NaN;
for k = 1:round(60/dt)
    s = local_runA(s,cA,ws,pcmd,v1,1,dt);
    if abs(s.v_ground_mps-v1) <= 0.1
        runOk = runOk+1;
        if runOk >= round(2/dt), tSettle = s.time_s-t0; break; end
    else
        runOk = 0;
    end
end
end

function s = local_runA(s,c,ws,pcmd,v,ns,dt)
cmd = struct('v_ref_applied_mps',v,'eta_ref_applied',1,'controller_mode','fixed');
for k = 1:ns
    ws.time_s = s.time_s+dt;
    [s,~] = plane_quad.step(s,ws,pcmd,cmd,dt,c); %#ok<ASGUU>
end
end
