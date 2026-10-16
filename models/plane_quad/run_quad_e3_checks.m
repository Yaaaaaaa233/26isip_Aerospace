function result = run_quad_e3_checks()
%RUN_QUAD_E3_CHECKS E3 涌现门(sag→推力天花板) + B 组样张(满放 V(t)/推力天花板)。
% 运行: cd models/plane_quad && run_quad_e3_checks
% 通过标准(方案 §5 v1.8 §10.2 预注册, 叶安确认 2026-10-11): 单调、与 OCV×T(n) 一致。
% E3 涌现口径(方案 §4): 电池端电压随放电/内阻压降下垂(sag) → 满油门转速
% n_ce=KV·V̂ 线性缩水 → 推力天花板 T_ce=bench_T(n_ce)·g 随之下降——
% "电压跌落→上限线性缩放"(config KV_eff 注释/H9 同源)。
% 实现口径:
%   满放 = 定油门恒载放电, **电气链走权威 +quad_sim/step**(电压耦合固定点/
%   内阻压降/容量记账逐位同码), 力学态逐拍钉在悬停条件(速度/角率/姿态清零)
%   ——负载因子恒 1、废阻功率 0, 电气负载只由电转速映射决定(自洽随 V 下降)。
%   两档: 悬停油门(整机重力=4×悬停桨距)与高功率(1.1× 悬停总推力; 低 soc 段
%   油门自然饱和进天花板——sag→天花板涌现自现)。
%   推力天花板 = 理论线 T_ce(V)=bench_T(min(KV·V,ω帽))·g 与放电途中 6 个
%   soc 检查点的**全油门实测推力**(2 s 窗, 尾 0.5 s 均值)对照。
% 机型: baseline('b40')(R6 单机口径)。确定性(无噪声流), 复跑逐位。
% 指标表 quad_e3_metrics.csv 与样张 quad_e3_figB.png 同源同批导出
% (面板截图不作证据)。数字口径 quad_placeholder 族(C9)仅限内部比较。
root = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(root));
addpath(root); addpath(fullfile(repo,'models','px4_x8'));
resDir = fullfile(root,'results');
if ~exist(resDir,'dir'), mkdir(resDir); end
c = quad_sim.config(quad_sim.baseline('b40'));
dt = 0.5;                    % 满放积分步(电量 Euler; I 慢变, dt 加倍 <0.01%)
dtM = 0.05;                  % 全油门检查点测量步(电调/电机就位用)
tMax = 12*3600;
Vfull = local_ocv(1,c);
Vcut = c.battery_cutoff_V;
% 悬停/高功率定油门(throttle 分数: 满电下 n 目标/KV·V_full)
nHover = local_n_of_t(c,c.mass_kg/4);            % krpm(悬停桨距)
nHigh = local_n_of_t(c,1.1*c.mass_kg/4);         % 1.1x 悬停总推力/4
thHover = nHover*1000/(c.kv_rpm_per_V*Vfull);
thHigh = nHigh*1000/(c.kv_rpm_per_V*Vfull);
pwmHover = c.pwm_min_us + (c.pwm_max_us-c.pwm_min_us)*thHover;
pwmHigh = c.pwm_min_us + (c.pwm_max_us-c.pwm_min_us)*thHigh;
socChk = [0.90 0.70 0.50 0.30 0.15 0.05];        % 天花板检查点(soc 档)
% ---- 推力天花板理论线(OCV×T(n) 口径; 整机总推力=4×单桨) ----
Vgrid = linspace(Vcut,Vfull,60);
Tce = zeros(size(Vgrid));
for k = 1:numel(Vgrid)
    nCe = min(c.kv_rpm_per_V*Vgrid(k)/1000, c.omega_max_radps/(2*pi)*60/1000);
    Tce(k) = 4*max(0,polyval(c.bench_T_coef_desc,nCe))*c.gravity_mps2;
end
% ---- 两档满放 + 高功率档全油门检查点 ----
runs = cell(1,2); chk = cell(1,2);
[runs{1},chk{1}] = local_discharge(c,pwmHover,dt,dtM,tMax,socChk,true);
[runs{2},chk{2}] = local_discharge(c,pwmHigh,dt,dtM,tMax,socChk,true);
% ---- 指标 ----
fails = {};
monoTol = 0.01;              % V(t) 单调容差(V/步)
dV1 = max(diff(runs{1}.V)); dV2 = max(diff(runs{2}.V));
okMono1 = dV1 <= monoTol; okMono2 = dV2 <= monoTol;
if ~okMono1, fails{end+1} = sprintf('E3-1: hover V(t) not monotone (%.3f V)',dV1); end
if ~okMono2, fails{end+1} = sprintf('E3-2: high V(t) not monotone (%.3f V)',dV2); end
okEnd1 = runs{1}.cutoff; okEnd2 = runs{2}.cutoff;
if ~(okEnd1 && okEnd2), fails{end+1} = 'E3-3: discharge did not reach cutoff'; end
dTce = min(diff(Tce));
okTce = dTce >= -1e-9;
if ~okTce, fails{end+1} = sprintf('E3-4: T_ce(V) not monotone (%.3f N)',dTce); end
% E3-5 实测满推力 vs OCV×T(n)(用实测端电压代入理论线, 整机总推力口径)
devMax = 0;
for i = 1:2
    for k = 1:numel(chk{i}.V)
        nCe = min(c.kv_rpm_per_V*chk{i}.V(k)/1000, c.omega_max_radps/(2*pi)*60/1000);
        Tref = 4*max(0,polyval(c.bench_T_coef_desc,nCe))*c.gravity_mps2;
        devMax = max(devMax, abs(chk{i}.T(k)-Tref)/max(Tref,1));
    end
end
okConsist = devMax <= 0.01;
if ~okConsist, fails{end+1} = sprintf('E3-5: measured ceiling dev %.3f%% > 1%%',100*devMax); end
% E3-6 sag→天花板涌现(高功率档): 全油门 sag>2%OCV 且天花板落差
% T_ce(OCV)−T_ce(V_sag)>=0 并存在 >0 点。注意 b40 天花板是**两段式**:
% n_ce=min(KV·V, 台架域顶帽), 高 soc 段撞帽(落差恒 0, 天花板平顶=H9 硬顶),
% 电压线性缩放段在非帽区显现——落差序列随 soc 的走向如实报告, 不设单调门。
ch = chk{2};
sagV = ch.ocv - ch.V;                                % 端电压下垂量
dropN = zeros(size(ch.V));                           % 天花板落差(对 OCV 名义线, 整机)
for k = 1:numel(ch.V)
    nOcv = min(c.kv_rpm_per_V*ch.ocv(k)/1000, c.omega_max_radps/(2*pi)*60/1000);
    nSag = min(c.kv_rpm_per_V*ch.V(k)/1000, c.omega_max_radps/(2*pi)*60/1000);
    dropN(k) = 4*(max(0,polyval(c.bench_T_coef_desc,nOcv)) - ...
        max(0,polyval(c.bench_T_coef_desc,nSag)))*c.gravity_mps2;
end
fprintf('CHK high: soc=%s\n  V=%s\n  ocv=%s\n  T=%s\n  dropN=%s\n', ...
    sprintf('%.2f ',ch.soc),sprintf('%.2f ',ch.V),sprintf('%.2f ',ch.ocv), ...
    sprintf('%.1f ',ch.T),sprintf('%.2f ',dropN));
okSag = all(sagV > 0.02*ch.ocv) && all(dropN >= -1e-9) && any(dropN > 0);
if ~okSag, fails{end+1} = 'E3-6: sag->ceiling emergence missing'; end
% E3-7 容量对账(报告): ∫I dt ≈ 96 Ah
capErr = max(abs(runs{1}.Ah(end)-c.battery_capacity_Ah), ...
    abs(runs{2}.Ah(end)-c.battery_capacity_Ah))/c.battery_capacity_Ah;
% ---- 指标表(指标|门槛|实测|判定) ----
rows = { ...
 'E3-1 悬停档满放 V(t) 单调', 'dV<=+0.01 V/步', sprintf('%+.4f V',dV1), tern(okMono1);
 'E3-2 高功率档满放 V(t) 单调', 'dV<=+0.01 V/步', sprintf('%+.4f V',dV2), tern(okMono2);
 'E3-3 满放到截止', 'battery_cutoff=1', sprintf('%d/%d',okEnd1,okEnd2), tern(okEnd1&&okEnd2);
 'E3-4 T_ce(V) 单调非减', 'min dT>=0', sprintf('%+.3f N',dTce), tern(okTce);
 'E3-5 实测满推力 vs OCV*T(n)', '偏差<=1%', sprintf('%.4f%%',100*devMax), tern(okConsist);
 'E3-6 sag->天花板涌现', 'sag>2%OCV, 落差>=0 且非全零', sprintf('sag %.2f~%.2f V, 落差 %.1f~%.1f N(帽区平顶)', ...
    min(sagV),max(sagV),min(dropN),max(dropN)), tern(okSag);
 'E3-7 满放容量对账(报告)', '偏差<=2%', sprintf('%.3f%%',100*capErr), tern(capErr<=0.02);
};
T = cell2table(rows,'VariableNames',{'指标','门槛','实测','判定'});
csv = fullfile(resDir,'quad_e3_metrics.csv'); writetable(T,csv,'Encoding','UTF-8');
% ---- 样张 B(同源同批导出) ----
fig = figure('Visible','off','Position',[100 100 1100 760]);
subplot(2,2,1); hold on;
plot(runs{1}.t/60,runs{1}.V,'b-','LineWidth',1.2);
plot(runs{2}.t/60,runs{2}.V,'r-','LineWidth',1.2);
yline(Vcut,'k--'); yline(Vfull,'k:');
grid on; xlabel('t (min)'); ylabel('V_{term} (V)');
title(sprintf('B1 满放 V(t) (b40 7S4P %.0f Ah)',c.battery_capacity_Ah));
legend({'悬停油门','高功率 1.1xW','截止 V','满电 OCV'},'Location','southwest');
subplot(2,2,2); hold on;
plot(runs{2}.t/60,runs{2}.Ah,'r-','LineWidth',1.2);
plot(runs{2}.t/60,runs{2}.I,'m-','LineWidth',1.0);
grid on; xlabel('t (min)'); ylabel('Ah / A');
title(sprintf('容量对账 \\int I dt=%.2f Ah (偏差 %.2f%%)',runs{2}.Ah(end),100*capErr));
legend({'累计 Ah','I (A)'},'Location','best');
subplot(2,2,3); hold on;
plot(Vgrid,Tce,'k-','LineWidth',1.6);
for k = 1:numel(chk{1}.V)
    plot(chk{1}.V(k),chk{1}.T(k),'bo','MarkerSize',7,'LineWidth',1.2);
end
for k = 1:numel(chk{2}.V)
    plot(chk{2}.V(k),chk{2}.T(k),'rs','MarkerSize',7,'LineWidth',1.2);
end
grid on; xlabel('V_{term} (V)'); ylabel('T_{ce} (N)');
title('B2 推力天花板 T_{ce}(V)=4·bench\_T(min(KV·V,\omega帽))·g');
legend({'OCV×T(n) 理论线','悬停档实测','高功率档实测'},'Location','northwest');
subplot(2,2,4); hold on;
plot(ch.soc,dropN,'rs-','LineWidth',1.2,'MarkerFaceColor','r');
plot(chk{1}.soc,chk{1}.dropN,'bo-','LineWidth',1.2);
grid on; xlabel('SOC'); ylabel('\DeltaT_{ce}(OCV→V_{sag}) (N)');
set(gca,'XDir','reverse');                          % 放电方向从左到右
title('E3 涌现: sag→推力天花板落差(随放电加深)');
legend({'高功率档','悬停档'},'Location','northwest');
png = fullfile(resDir,'quad_e3_figB.png'); saveas(fig,png); close(fig);
% ---- 收口 ----
result = struct('pass',isempty(fails),'tier','smoke','csv',csv,'png',png, ...
    'metrics',T,'runs',{runs},'chk',{chk},'failures',{fails});
if ~result.pass
    error('quad:E3Checks','E3 FAIL (%d): %s | archive: %s', ...
        numel(fails),strjoin(fails,'; '),csv);
end
fprintf(['E3 PASS: V(t) 单调 | T_ce 实测偏差 %.4f%% | sag %.2f~%.2f V, ' ...
    '天花板落差 %.1f~%.1f N | 容量对账 %.3f%% -> %s\n'], ...
    100*devMax,min(sagV),max(sagV),min(dropN),max(dropN),100*capErr,csv);
end
function [R,C] = local_discharge(c,pwmFix,dt,dtM,tMax,socChk,doChk)
% 定油门满放: 权威 step.m 电气链, 力学态逐拍钉悬停(负载因子恒 1)
s = quad_sim.reset(c,struct('rotor_omega_radps', ...
    (local_n_of_t(c,c.mass_kg/4)*1000*2*pi/60)*ones(4,1)));
nRec = ceil(tMax/dt)+1;
tR = zeros(1,nRec); VR = zeros(1,nRec); IR = zeros(1,nRec);
AR = zeros(1,nRec); SR = zeros(1,nRec); nR = 0;
C = struct('soc',zeros(1,0),'V',zeros(1,0),'ocv',zeros(1,0), ...
    'T',zeros(1,0),'I',zeros(1,0),'dropN',zeros(1,0));
iChk = 1; Ah = 0;
while ~s.battery_cutoff && s.time_s < tMax && nR < nRec
    if doChk && iChk <= numel(socChk) && s.soc <= socChk(iChk)
        % 全油门检查点: 2 s 窗, 尾 0.5 s 均值(推力/端电压/电流)
        q0 = s.battery_charge_Ah;
        nM = round(2/dtM); tSum = 0; vSum = 0; iSum = 0; nTail = 0;
        for m = 1:nM
            [s,om] = quad_sim.step(s,struct('pwm_us',ones(4,1)*c.pwm_max_us, ...
                'wind_ned_mps',[0;0;0]),dtM,c);
            s = local_pin(s);
            if m > nM - round(0.5/dtM)
                tSum = tSum + sum(om.rotor_thrust_N);
                vSum = vSum + om.battery_voltage_V;
                iSum = iSum + om.battery_current_A; nTail = nTail + 1;
            end
        end
        C.soc(end+1) = s.soc; C.V(end+1) = vSum/nTail;
        C.ocv(end+1) = local_ocv(s.soc,c);
        C.T(end+1) = tSum/nTail; C.I(end+1) = iSum/nTail;
        Ah = Ah + (q0 - s.battery_charge_Ah);     % 检查点放电计入对账
        iChk = iChk + 1;
    end
    [s,o] = quad_sim.step(s,struct('pwm_us',ones(4,1)*pwmFix, ...
        'wind_ned_mps',[0;0;0]),dt,c);
    s = local_pin(s);
    nR = nR + 1;
    tR(nR) = s.time_s; VR(nR) = o.battery_voltage_V;
    IR(nR) = o.battery_current_A;
    Ah = Ah + o.battery_current_A*dt/3600;
    AR(nR) = Ah; SR(nR) = s.soc;
end
R = struct('t',tR(1:nR),'V',VR(1:nR),'I',IR(1:nR),'Ah',AR(1:nR), ...
    'soc',SR(1:nR),'cutoff',logical(s.battery_cutoff));
for k = 1:numel(C.V)
    nOcv = min(c.kv_rpm_per_V*C.ocv(k)/1000, c.omega_max_radps/(2*pi)*60/1000);
    nSag = min(c.kv_rpm_per_V*C.V(k)/1000, c.omega_max_radps/(2*pi)*60/1000);
    C.dropN(k) = 4*(max(0,polyval(c.bench_T_coef_desc,nOcv)) - ...
        max(0,polyval(c.bench_T_coef_desc,nSag)))*c.gravity_mps2;
end
end
function s = local_pin(s)
% 力学态钉悬停: 电气负载只由电转速映射决定(定油门口径)
s.velocity_ned_mps = [0;0;0]; s.body_rate_radps = [0;0;0];
s.quaternion_bn = [1;0;0;0]; s.position_ned_m = [0;0;0];
end
function v = local_ocv(soc,c)
cellV = interp1(c.battery_ocv_soc,c.battery_ocv_cell_V, ...
    min(c.max_soc,max(c.min_soc,soc)),'linear','extrap');
v = c.battery_n_ser*cellV;
end
function n = local_n_of_t(c,t)
% 台架 T(n) 反解(正根, krpm)——与 step.m/ctrl.m 同式
b = c.bench_T_coef_desc;
rr = roots([b(1),b(2),b(3)-t]); rr = rr(imag(rr)<1e-9 & real(rr)>0); n = min(real(rr));
if isempty(n) || ~isfinite(n), n = 0; end
end
function s = tern(c), if c, s = 'PASS'; else, s = 'FAIL'; end, end
