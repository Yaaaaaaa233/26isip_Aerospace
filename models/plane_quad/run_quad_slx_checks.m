function result = run_quad_slx_checks()
%RUN_QUAD_SLX_CHECKS P4 air_quad.slx 薄包装冒烟验收(开发级 smoke, 2026-10-13)。
% 运行: cd models/plane_quad && run_quad_slx_checks
% 正式验收 = 接口审查(叶安, AIR_QUAD_INTERFACE.md, Proposed)。
% 门(全部硬断言, 失败携带归档路径退出):
%   S-B1 构建: air_quad.slx 生成并可加载(薄包装, 模型内无自有动力学)
%   S-B2 对拍: slx 仿真 vs MATLAB 权威链直接循环, V/v/x/soc 逐位一致
%      (激励: 悬停 5 s + 6 m/s 阶跃 15 s, 头风 2.5 m/s; 证明 slx 管道透明)
%   S-B3 确定性: 同会话两遍 sim 逐位一致(reset 首拍重建状态)
%   S-B4 组帧接口位: 0xF2 副帧 24 字节/标识 0xF2/量化回读 <=1 LSB/校验和自洽
%   S-B5 估计映射: slx P̂ 对权威链 P_true 偏差 <=3%(est_model='l1', C3/C7 报告)
root = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(root));
addpath(root); addpath(fullfile(repo,'models','px4_x8'));
resDir = fullfile(root,'results');
if ~exist(resDir,'dir'), mkdir(resDir); end
cfg = quad_sim.config(quad_sim.baseline('b40'),'est_model','l1');
dt = cfg.sample_time_s; T = 20; t = (0:dt:T)';
cmd = struct('t',t,'vref',6*double(t>=5),'wind',repmat([-2.5 0 0],numel(t),1), ...
    'reset',double(t==0));
fails = {};
% ---- S-B1 构建 ----
file = build_air_quad(cfg,T,cmd);
if exist(file,'file') ~= 2
    fails{end+1} = 'S-B1: air_quad.slx not created';
end
% ---- 权威链参考循环(独立于 tick, trim_run 同序) ----
assignin('base','air_quad_config',cfg);
cleanupBase = onCleanup(@()evalin('base','clear air_quad_config')); %#ok<NASGU>
clear air_quad_tick                                          % 清 persistent
nHoverK = local_n_of_t(cfg,cfg.mass_kg/4);
s = quad_sim.reset(cfg,struct('rotor_omega_radps', ...
    (nHoverK*1000*2*pi/60)*ones(4,1)));
ref = zeros(numel(t),6);                                     % [Ptrue V v x soc tsim]
for k = 1:numel(t)
    wind = cmd.wind(k,:)';
    [~,out0] = quad_sim.step(s,struct('pwm_us',s.last_pwm_us,'wind_ned_mps',wind),0,cfg);
    pwm = quad_sim.ctrl(s,out0,cmd.vref(k),cfg);
    [s,out] = quad_sim.step(s,struct('pwm_us',pwm,'wind_ned_mps',wind),dt,cfg);
    ref(k,:) = [out.electrical_power_W out.battery_voltage_V ...
        norm(out.velocity_ned_mps(1:2)) out.position_ned_m(1) out.soc s.time_s];
end
% ---- S-B2 slx 仿真对拍 + S-B3 逐位复跑 ----
clear air_quad_tick
mdl = 'air_quad'; load_system(file);
cleanupMdl = onCleanup(@()close_system(mdl,0)); %#ok<NASGU>
simOut1 = sim(mdl);
log1 = double(simOut1.air_quad_log);
clear air_quad_tick
simOut2 = sim(mdl);
log2 = double(simOut2.air_quad_log);
detOK = isequal(log1,log2);
if ~detOK, fails{end+1} = 'S-B3: two-pass sim not bitwise'; end
% log 列: [P̂ V I v th1 th2 x soc]
nCmp = min(size(log1,1),size(ref,1));
dV = max(abs(log1(1:nCmp,2)-ref(1:nCmp,2)));
dv = max(abs(log1(1:nCmp,4)-ref(1:nCmp,3)));
dx = max(abs(log1(1:nCmp,7)-ref(1:nCmp,4)));
ds = max(abs(log1(1:nCmp,8)-ref(1:nCmp,5)));
if max([dV dv dx ds]) > 0
    fails{end+1} = sprintf('S-B2: slx vs authority diff V=%.3g v=%.3g x=%.3g soc=%.3g', ...
        dV,dv,dx,ds);
end
% ---- S-B4 组帧接口位 ----
tel = double(simOut1.telemetry_bytes);
b = tel(end,:);
vRead = (b(2)+256*b(3))/10;                                 % bit15=0 主电压
t1 = bitand(b(4)+256*b(5),16383)/1000; t2 = bitand(b(6)+256*b(7),16383)/1000;
iRead = b(8); ck = mod(sum(b(1:23)),256);
dVtel = abs(vRead-log1(end,2)); dt1 = abs(t1-log1(end,5)); dt2 = abs(t2-log1(end,6));
dItel = abs(iRead-min(255,round(log1(end,3))));
telOK = (numel(b)==24) && (b(1)==242) && (dVtel<=0.1+1e-9) && ...
    (dt1<=0.001+1e-9) && (dt2<=0.001+1e-9) && (dItel<=0) && (b(24)==ck);
if ~telOK
    fails{end+1} = sprintf('S-B4: telemetry frame check failed (id=%.0f dV=%.3f ck=%d)', ...
        b(1),dVtel,b(24)==ck);
end
% ---- S-B5 估计映射 ----
bias = 100*(mean(log1(1:nCmp,1))-mean(ref(1:nCmp,1)))/mean(ref(1:nCmp,1));
if abs(bias) > 3
    fails{end+1} = sprintf('S-B5: estimator bias %+.2f%% > 3%%',bias);
end
% ---- 输出 ----
T2 = cell2table({dV,dv,dx,ds,detOK,dVtel,dt1,dItel,bias,b(1),b(24)==ck}, ...
    'VariableNames',{'dV','dv','dx','dsoc','deterministic','tel_dV','tel_dth', ...
    'tel_dI','est_bias_pct','frame_id','checksum_ok'});
csv = fullfile(resDir,'quad_slx_smoke.csv'); writetable(T2,csv,'Encoding','UTF-8');
fig = figure('Visible','off');
subplot(2,1,1); plot(t(1:nCmp),log1(1:nCmp,4),t(1:nCmp),ref(1:nCmp,3),'--');
legend('slx','authority'); grid on; xlabel('t (s)'); ylabel('v (m/s)');
title('air_quad.slx vs MATLAB authority (parity)');
subplot(2,1,2); plot(t(1:nCmp),log1(1:nCmp,1),t(1:nCmp),ref(1:nCmp,1),'--');
legend('P-hat (est)','P true'); grid on; xlabel('t (s)'); ylabel('P (W)');
title(sprintf('estimator mapping (bias %+.2f%%)',bias));
png = fullfile(resDir,'quad_slx_parity.png'); saveas(fig,png); close(fig);
result = struct('pass',isempty(fails),'tier','smoke','csv',csv,'png',png, ...
    'slx',file,'bias_pct',bias,'deterministic',detOK,'failures',{fails});
if ~result.pass
    error('quad:SlxChecks','SLX SMOKE FAIL (%d): %s | archive: %s', ...
        numel(fails),strjoin(fails,'; '),csv);
end
fprintf('slx smoke PASS -> %s | parity bitwise(V/v/x/soc) | est bias %+.2f%% | frame 0x%02X\n', ...
    csv,bias,b(1));
end
function n = local_n_of_t(c,t)
b = c.bench_T_coef_desc;
rr = roots([b(1),b(2),b(3)-t]); rr = rr(imag(rr)<1e-9 & real(rr)>0); n = min(real(rr));
if isempty(n) || ~isfinite(n), n = 0; end
end
