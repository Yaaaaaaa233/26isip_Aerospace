function tests = tests_task32()
%TESTS_TASK32 任务3.2单元测试: 曲线未知且无扫频标定——纯奖励RL(pure_rl)
% 直接从奖励学每航向最优速度 + sweepcal/rl对照 + 七种风场库 + 空速语义
% (空速=地速−风) + 曲线标定锚点回归 + 执行链(时延/限幅/航向积分)回归。
% 注: windinfer/est/known 为已知曲线oracle参照(评价侧), 非因果策略。
tests = functiontests(localfunctions);
end

%% ---------- 风场模型库 ----------
function test_wind_models_values(tc)
wind={'windAmp',2,'windOmega',0.4,'windBias',3,'windAmpY',1.5,'windOmegaY',0.7,...
    'windBiasY',1,'windDirDeg',0,'duration',40,'tailSteps',5};
t=[0 1.37 9.1 22.8];
% const: 恒等于偏置
c=w32.config(wind{:},'windKind','const'); scn=w32.scenario('static',c);
[wx,wy]=w32.wind_field(scn,[0 12.3 40],0);
tc.verifyEqual(wx,[3 3 3],'AbsTol',1e-12);
tc.verifyEqual(wy,[1 1 1],'AbsTol',1e-12);
% sin: 与闭式一致(任务4/5/8原口径)
c=w32.config(wind{:},'windKind','sin'); scn=w32.scenario('static',c);
[wx,wy]=w32.wind_field(scn,t,0);
tc.verifyEqual(wx,2*sin(0.4*t)+3,'AbsTol',1e-12);
tc.verifyEqual(wy,1.5*sin(0.7*t)+1,'AbsTol',1e-12);
% square: 软边方波——峰值=B+A, 有界, 连续(边缘陡度有界)
c=w32.config(wind{:},'windKind','square','squareEdge',4); scn=w32.scenario('static',c);
tp=pi/2/0.4;
[wx,~]=w32.wind_field(scn,tp,0);
tc.verifyEqual(wx,5,'AbsTol',1e-9);
tt=0:0.01:40;
[wx,wy]=w32.wind_field(scn,tt,0);
tc.verifyTrue(max(abs(wx-3))<=2+1e-9 && max(abs(wy-1))<=1.5+1e-9,'方波必须有界');
dwx=abs(diff(wx)); bound=2*0.4*(4/tanh(4))*0.01+1e-12;
tc.verifyTrue(max(dwx)<=bound,'软边方波应连续(边缘陡度有界)');
% triangle: 峰值=B+A, 上升段斜率=A·ω·2/π
c=w32.config(wind{:},'windKind','triangle'); scn=w32.scenario('static',c);
[wx,~]=w32.wind_field(scn,tp,0);
tc.verifyEqual(wx,5,'AbsTol',1e-9);
t2=[0 tp/2 tp];
[wx,~]=w32.wind_field(scn,t2,0);
slope=(wx(2)-wx(1))/(t2(2)-t2(1));
tc.verifyEqual(slope,2*0.4*2/pi,'AbsTol',1e-9);
% turb: 确定性(同种子同序列)+平稳统计(std≈windAmp, 均值≈0)
wA=2.0;
c1=w32.config(wind{:},'windKind','turb','windAmp',wA,'turbTheta',0.2,'duration',4000);
s1=w32.scenario('static',c1); s2=w32.scenario('static',c1);
tc.verifyEqual(s1.windTurbX,s2.windTurbX);
tc.verifyEqual(s1.windTurbY,s2.windTurbY);
tc.verifyLessThan(abs(std(s1.windTurbX(10000:end))-wA),0.5,'OU平稳std应≈windAmp');
tc.verifyLessThan(abs(mean(s1.windTurbX(10000:end))),0.3,'OU均值应≈0');
% composite: turbStd=0 时退化为纯sin; turbStd>0 时叠加std≈turbStd的湍流
c=w32.config(wind{:},'windKind','composite','turbStd',0); scn=w32.scenario('static',c);
[wx,wy]=w32.wind_field(scn,t,0);
tc.verifyEqual(wx,2*sin(0.4*t)+3,'AbsTol',1e-12);
c=w32.config(wind{:},'windKind','composite','turbStd',0.3,'seed',5,'duration',400);
scn=w32.scenario('static',c);
tt2=0:0.01:400;
[wx,~]=w32.wind_field(scn,tt2,0);
resid=wx-(2*sin(0.4*tt2)+3);
tc.verifyLessThan(abs(std(resid(10000:end))-0.3),0.05,'复合风湍流分量std应≈turbStd');
% sector: 与时间无关、周期2π、绕偏置幅值=A
c=w32.config(wind{:},'windKind','sector'); scn=w32.scenario('static',c);
[wx1,wy1]=w32.wind_field(scn,0,0);
[wx2,wy2]=w32.wind_field(scn,137.9,0);
tc.verifyEqual(wx1,wx2); tc.verifyEqual(wy1,wy2);
[wx3,wy3]=w32.wind_field(scn,0,2*pi);
tc.verifyEqual(wx3,wx1,'AbsTol',1e-12); tc.verifyEqual(wy3,wy1,'AbsTol',1e-12);
[wxp,~]=w32.wind_field(scn,0,pi);   % ψ=π: Wx=B−A·cos(π)=B+A
tc.verifyEqual(wxp,5,'AbsTol',1e-12);
[wxh,wyh]=w32.wind_field(scn,0,pi/2); % ψ=π/2: Wx=B−A·cos(π/2)=B, Wy=D+C·sin(π/2)=D+C
tc.verifyEqual(wxh,3,'AbsTol',1e-12);
tc.verifyEqual(wyh,1+1.5,'AbsTol',1e-12);
end

function test_sector_periodic_profile(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w32.config(wind{:},'windKind','sector');
scn=w32.scenario('static',c);
psd=deg2rad(0:1:360);
[wx,wy]=w32.wind_field(scn,0,psd);
tc.verifyEqual(wx(1),wx(end),'AbsTol',1e-12,'ψ=0与ψ=2π风应相同(周期)');
tc.verifyEqual(wy(1),wy(end),'AbsTol',1e-12);
tc.verifyLessThan(max(wx)-min(wx),4.0001,'扇区风x向峰峰应=2A');
end

function test_wind_rotation(tc)
wind={'windAmp',2,'windOmega',0.4,'windBias',3,'windAmpY',1.5,'windOmegaY',0.7,...
    'windBiasY',1,'windDirDeg',90,'windKind','sin','duration',40,'tailSteps',5};
c=w32.config(wind{:}); scn=w32.scenario('static',c);
t=3.7;
[wx,wy,vx,vy]=w32.wind_field(scn,t,0);
tc.verifyEqual(vx,-wy,'AbsTol',1e-12);   % R(90°)[Wx;Wy]=[-Wy;Wx]
tc.verifyEqual(vy,wx,'AbsTol',1e-12);
end

%% ---------- 空速语义(空速=地速−风; 功率由空速决定) ----------
function test_plant_airspeed_identity(tc)
wind={'windAmp',0,'windBias',3,'windAmpY',0,'windBiasY',1,'windKind','const'};
c=w32.config('seed',11,'duration',30,'tailSteps',5,wind{:});
[log,~]=w32.run_algorithm('openloop',w32.scenario('static',c),c);
psi=deg2rad(log.headingDeg);
uExp=hypot(log.speed.*cos(psi)-log.windX, log.speed.*sin(psi)-log.windY);
tc.verifyEqual(log.airspeed,uExp,'AbsTol',1e-9,'空速应=|地速矢量−风矢量|');
tc.verifyEqual(log.windX,3*ones(height(log),1),'AbsTol',1e-12);
tc.verifyEqual(log.windY,1*ones(height(log),1),'AbsTol',1e-12);
end

function test_user_example_tailwind_headwind(tc)
% 用户口径例子: 地速向右6m/s + 顺风向右3m/s → 空速3m/s; 地速曲线顺风右移。
wind={'windAmp',0,'windBias',3,'windAmpY',0,'windBiasY',0,'windKind','const'};
c=w32.config('seed',11,'duration',5,'tailSteps',1,'turnRadius',600,...
    'initialSpeed',6,'openLoopV',6,wind{:});
[log,~]=w32.run_algorithm('openloop',w32.scenario('static',c),c);
tc.verifyLessThan(abs(log.airspeed(1)-3),0.01,...
    '地速6+顺风3(ψ≈0)时空速应≈3');
tc.verifyLessThan(abs(log.optimumTrue(1)-9.3),0.02,...
    '顺风3时地速最优应右移到 6.3+3=9.3');
% 逆风对照: 偏置3经windDirDeg=180旋转 → w=(−3,0), 空速9, 地速最优左移到 3.3
windH={'windAmp',0,'windBias',3,'windAmpY',0,'windBiasY',0,'windDirDeg',180,'windKind','const'};
cH=w32.config('seed',11,'duration',5,'tailSteps',1,'turnRadius',600,...
    'initialSpeed',6,'openLoopV',6,windH{:});
[logH,~]=w32.run_algorithm('openloop',w32.scenario('static',cH),cH);
tc.verifyLessThan(abs(logH.airspeed(1)-9),0.01,'地速6+逆风3时空速应≈9');
tc.verifyLessThan(abs(logH.optimumTrue(1)-3.3),0.02,'逆风3时地速最优应左移到 6.3−3=3.3');
end

function test_plant_power_from_airspeed_nowind(tc)
wind={'windAmp',0,'windBias',0,'windAmpY',0,'windBiasY',0,'windKind','const'};
c=w32.config('seed',11,'duration',20,'tailSteps',5,'initialSpeed',6.3,'openLoopV',6.3,wind{:});
[log,~]=w32.run_algorithm('openloop',w32.scenario('static',c),c);
P63=w32.base_curve(6.3,c);   % 零风+恒地速: 空速=地速, 功率=base_curve(6.3)
tc.verifyEqual(log.powerTrue,P63*ones(height(log),1),'AbsTol',1e-9);
end

function test_ground_curve_optimum_closed_form(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w32.config('seed',11,'duration',40,'tailSteps',10,wind{:});
scn=w32.scenario('static',c);
plant=w32.make_plant(scn,c);
n=40; vK=6;
for k=1:n
    plant.q(vK,'hold'); plant.amendEstimate(vK);
end
log=plant.table();
for k=1:n
    tEnd=log.time(k)+c.tEval;
    psiE=deg2rad(log.headingDeg(k));
    [~,~,VxE,VyE]=w32.wind_field(scn,tEnd,psiE);
    qE=VxE*cos(psiE)+VyE*sin(psiE);
    disc=qE^2+c.optimum0^2-(VxE^2+VyE^2);
    if disc>0, vO=qE+sqrt(disc); else, vO=qE; end
    vO=min(max(vO,c.lower),c.upper);
    tc.verifyEqual(log.optimumTrue(k),vO,'AbsTol',1e-9,'地速最优应与新约定闭式解一致');
end
end

function test_sector_optimum_varies_with_heading(tc)
wind={'windAmp',2,'windBias',0,'windAmpY',0,'windBiasY',0,'windKind','sector'};
c=w32.config('seed',11,'duration',60,'tailSteps',5,'initialSpeed',6.3,'openLoopV',6.3,wind{:});
[log,~]=w32.run_algorithm('openloop',w32.scenario('static',c),c);
tc.verifyGreaterThan(std(log.optimumTrue),0.02,'扇区风下地速最优应随航向变化');
wind0={'windAmp',0,'windBias',0,'windAmpY',0,'windBiasY',0,'windKind','const'};
c0=w32.config('seed',11,'duration',60,'tailSteps',5,'initialSpeed',6.3,'openLoopV',6.3,wind0{:});
[log0,~]=w32.run_algorithm('openloop',w32.scenario('static',c0),c0);
tc.verifyEqual(std(log0.optimumTrue),0,'AbsTol',1e-9,'零风下地速最优不应随时间变化');
tc.verifyEqual(mean(log0.optimumTrue),c0.optimum0,'AbsTol',1e-9,'零风下地速最优应=名义V*');
end

%% ---------- 任务8曲线case标定回归 ----------
function test_case_anchors_exact(tc)
for r=[0.95 0.90 0.85]
    c=w32.config('curveCase',r);
    tc.verifyEqual(w32.base_curve(0,c),1.0,'AbsTol',1e-9);
    tc.verifyEqual(w32.base_curve(c.optimum0,c),r,'AbsTol',1e-9);
    vv=0:0.005:20; Pw=w32.base_curve(vv,c);
    [~,im]=min(Pw);
    tc.verifyTrue(abs(vv(im)-c.optimum0)<0.01,'全局谷底应恰在V*');
end
end

function test_reference_anchors_watts(tc)
c=w32.config();
tc.verifyEqual(c.pHover,103.7); tc.verifyEqual(c.p20,134.5);
tc.verifyEqual(w32.base_curve(20,c)*c.pHover,134.5,'AbsTol',3.5);
end

function test_grad_finite_difference(tc)
c=w32.config();
for x=[2.0 6.3 10.5 18.0]
    h=1e-6;
    fd=(w32.base_curve(x+h,c)-w32.base_curve(x-h,c))/(2*h);
    tc.verifyEqual(w32.base_curve_grad(x,c),fd,'AbsTol',1e-7);
end
end

function test_moe_identity_and_case_in_plant(tc)
c=w32.config('seed',11,'curveCase',0.85);
[log,~]=w32.run_algorithm('openloop',w32.scenario('static',c),c);
m=w32.mop_moe(log,c);
tc.verifyEqual(m.MOE_energy,1/(1+m.energyExcessPercent/100),'AbsTol',1e-9);
tc.verifyEqual(mean(log.minPowerTrue),0.85,'AbsTol',1e-9);
end

%% ---------- 任务7执行链回归 ----------
function test_latency_impulse(tc)
c=w32.config('initialSpeed',10,'openLoopV',4,'windAmp',0,'windBias',0,...
    'windAmpY',0,'windBiasY',0,'windKind','const','latencySec',0.3);
[log,~]=w32.run_algorithm('openloop',w32.scenario('static',c),c);
tc.verifyEqual(log.speed(1),8.6,'AbsTol',1e-9);
% 任务3.2放宽: τ=0(无时延对照) — 指令立即释放, 仅受限幅: 第1步末 10-2×1=8
c0=w32.config('initialSpeed',10,'openLoopV',4,'windAmp',0,'windBias',0,...
    'windAmpY',0,'windBiasY',0,'windKind','const','latencySec',0);
[log0,~]=w32.run_algorithm('openloop',w32.scenario('static',c0),c0);
tc.verifyEqual(log0.speed(1),8.0,'AbsTol',1e-9,'τ=0时指令应立即生效(仅受限幅)');
tc.verifyTrue(all(log0.accelMax<=c0.aMax+1e-9),'τ=0时加速度限幅仍须成立');
end

function test_task2_noise_kept(tc)
c=w32.config('seed',11);
[log,~]=w32.run_algorithm('openloop',w32.scenario('static',c),c);
rel=(log.powerMeas-log.powerTrue)./log.powerTrue;
tc.verifyEqual(std(rel),0.01,'AbsTol',0.004);
tc.verifyEqual(mean(rel),0,'AbsTol',0.005);
end

function test_accel_and_budget_all_policies(tc)
% 2026-09-07精简: 移除任务1遗留搜索器(tracker/esc/spsa/bayes/qnewton/gtrack)。
policies={'openloop','est','windinfer','sweepcal','rl','purerl','known'};
for name=policies
    c=w32.config('seed',11,'duration',400);
    [log,~]=w32.run_algorithm(name{1},w32.scenario('static',c),c);
    tc.verifyEqual(height(log),c.duration,sprintf('%s预算未走满',name{1}));
    tc.verifyTrue(all(log.accelMax<=c.aMax+1e-9),sprintf('%s加速度超限',name{1}));
    tc.verifyTrue(all(isfinite(log.powerMeas)),sprintf('%s出现非有限测量',name{1}));
end
end

function test_all_kinds_policies_smoke(tc)
kinds={'const','sin','square','triangle','turb','composite','sector'};
policies={'openloop','known','sweepcal','rl','purerl'};
for kk=1:numel(kinds)
    for pp=1:numel(policies)
        c=w32.config('seed',11,'duration',250,'tailSteps',5,'windKind',kinds{kk},...
            'windAmpY',1.5,'windBiasY',1);
        [log,~]=w32.run_algorithm(policies{pp},w32.scenario('static',c),c);
        tc.verifyEqual(height(log),250,...
            sprintf('%s×%s预算未走满',kinds{kk},policies{pp}));
        tc.verifyTrue(all(log.accelMax<=c.aMax+1e-9),...
            sprintf('%s×%s加速度超限',kinds{kk},policies{pp}));
        tc.verifyTrue(all(isfinite(log.powerTrue)),...
            sprintf('%s×%s功率非有限',kinds{kk},policies{pp}));
    end
end
end

function test_heading_integration(tc)
c=w32.config('initialSpeed',6.3,'openLoopV',6.3,'windAmp',0,'windBias',0,...
    'windAmpY',0,'windBiasY',0,'windKind','const');
[log,~]=w32.run_algorithm('openloop',w32.scenario('static',c),c);
psiExp=rad2deg(cumsum(log.speed)*c.tEval/c.turnRadius);
tc.verifyEqual(max(abs(mod(log.headingDeg-psiExp+180,360)-180)),0,'AbsTol',1e-6);
end

function test_openloop_nowind_is_upper(tc)
c=w32.config('initialSpeed',6.3,'openLoopV',6.3,'windAmp',0,'windBias',0,...
    'windAmpY',0,'windBiasY',0,'windKind','const');
[log,~]=w32.run_algorithm('openloop',w32.scenario('static',c),c);
tc.verifyEqual(w32.mop_moe(log,c).MOE_energy,1.0,'AbsTol',1e-9);
end

function test_known_oracle_information_value(tc)
exK=zeros(1,5); exO=zeros(1,5);
for i=1:5
    c=w32.config('seed',10+i);
    scn=w32.scenario('static',c);
    [log,~]=w32.run_algorithm('known',scn,c);
    exK(i)=w32.mop_moe(log,c).energyExcessPercent;
    [log,~]=w32.run_algorithm('openloop',scn,c);
    exO(i)=w32.mop_moe(log,c).energyExcessPercent;
end
tc.verifyTrue(mean(exK)<1.0);
tc.verifyTrue(mean(exO)-mean(exK)>3.0);
end

%% ---------- 任务3.2核心: u*固定 + 风推断寻优(windinfer) ----------
function test_ustar_fixed_pmin_constant(tc)
% 任务3.2核心设定: 无平移调度 → 空速最优点u*固定, Pmin恒定不随时间变化;
% 地速最优v*仍随风变化(这正是需要寻优的原因)。
wind={'windKind','sin','windAmp',2,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w32.config('seed',7,'duration',300,'tailSteps',60,wind{:});
[log,~]=w32.run_algorithm('openloop',w32.scenario('static',c),c);
tc.verifyEqual(std(log.minPowerTrue),0,'AbsTol',1e-12,'Pmin应恒定(u*固定)');
tc.verifyEqual(mean(log.minPowerTrue),c.curveCase,'AbsTol',1e-9,'Pmin应=curveCase');
tc.verifyGreaterThan(std(log.optimumTrue),0.1,'变风下地速最优v*应随时间变化');
end

function test_windinfer_const_wind(tc)
% 恒定风: 由功率随航向的调制反推风矢量, 收敛后误差<0.6 m/s, 能耗逼近known。
c=w32.config('seed',3,'windKind','const','windBias',3.5,'windDirDeg',40);
scn=w32.scenario('static',c);
[log,info]=w32.run_algorithm('windinfer',scn,c);
m=w32.mop_moe(log,c);
wTrue=[3.5*cosd(40);3.5*sind(40)];
we=info.windEst;
kFin=find(isfinite(we(1,:)),1,'last');   % 末段就位步不更新估计(预算行为)
errF=norm(we(:,kFin)-wTrue);
hh=we(:,ceil(kFin/2):kFin);
errH=mean(hypot(hh(1,:)-wTrue(1),hh(2,:)-wTrue(2)),'omitnan');
tc.verifyLessThan(errF,0.6,'恒定风末段风估计误差应<0.6 m/s');
tc.verifyLessThan(errH,0.9,'恒定风后半程平均误差应<0.9 m/s');
tc.verifyLessThan(m.energyExcessPercent,2.0,'恒定风能耗超额应<2%');
tc.verifyEqual(info.regime{kFin},'恒定风','恒定风应被判为恒定风');
end

function test_windinfer_zero_wind(tc)
% 零风: 估计≈0, 全程飞u*, 无探针成本 → 超额≈0(探针法的能耗缺点被消除)。
c=w32.config('seed',3,'windKind','const','windBias',0,'windDirDeg',0);
scn=w32.scenario('static',c);
[log,info]=w32.run_algorithm('windinfer',scn,c);
m=w32.mop_moe(log,c);
tc.verifyLessThan(m.energyExcessPercent,0.5,'零风应几乎零超额');
we=info.windEst; kFin=find(isfinite(we(1,:)),1,'last');
tc.verifyLessThan(norm(we(:,kFin)),0.4,'零风风估计应≈0');
end

function test_windinfer_vary_wind_beats_openloop(tc)
% 变风(正弦慢变+湍流): 自适应缩窗跟踪, 至少应优于不补偿的开环巡航。
wcfg={'windKind','composite','windBias',2.5,'windAmp',1.5,'windOmega',0.08,...
    'windBiasY',0,'windAmpY',0,'turbStd',0.3};
c=w32.config('seed',3,wcfg{:});
scn=w32.scenario('static',c);
[logI,~]=w32.run_algorithm('windinfer',scn,c);
[logO,~]=w32.run_algorithm('openloop',scn,c);
mI=w32.mop_moe(logI,c); mO=w32.mop_moe(logO,c);
tc.verifyLessThan(mI.energyExcessPercent,mO.energyExcessPercent,'变风下风推断应优于开环');
tc.verifyLessThan(mI.energyExcessPercent,4.5,'变风超额应有界(<4.5%)');
end

function test_windinfer_strong_wind(tc)
% 强风(|w|=5.5接近u*=6.3): 闭式解仍可行, 推断不发散。
c=w32.config('seed',3,'windKind','const','windBias',5.5,'windDirDeg',200);
scn=w32.scenario('static',c);
[log,info]=w32.run_algorithm('windinfer',scn,c);
m=w32.mop_moe(log,c);
tc.verifyLessThan(m.energyExcessPercent,3.0,'强风能耗超额应<3%');
wTrue=[5.5*cosd(200);5.5*sind(200)];
we=info.windEst; kFin=find(isfinite(we(1,:)),1,'last');
tc.verifyLessThan(norm(we(:,kFin)-wTrue),1.6,'强风末段估计误差应<1.6(谷底功率对风误差二阶不敏感, 能耗几乎无损)');
end

function test_windinfer_causal_protocol(tc)
% 红线1: 预算走满/测量有限/估计序列有限(仅由指令与测量驱动, 种子变化即变化)。
for sd=[3 9]
    c=w32.config('seed',sd);
    scn=w32.scenario('static',c);
    [log,info]=w32.run_algorithm('windinfer',scn,c);
    tc.verifyEqual(height(log),c.duration,'预算未走满');
    tc.verifyTrue(all(isfinite(log.powerMeas)),'出现非有限测量');
    tc.verifyTrue(all(isfinite(info.windEst(:))),'风估计序列应有限');
    tc.verifyTrue(~isempty(info.regime), '风况判定序列不应为空');
end
end

function test_hover_uniform_baselines(tc)
% 悬停(地速0): 空速=|w|, 功率=J0(|w|); 零风匀速转圈@u*: 即全局最优(MOE=1)。
c=w32.config('seed',3,'windKind','const','windBias',3.5,'windDirDeg',40,...
    'openLoopV',0,'initialSpeed',6.3);
[log,~]=w32.run_algorithm('openloop',w32.scenario('static',c),c);
tc.verifyLessThan(abs(mean(log.airspeed)-3.5),0.1,'悬停空速应≈|w|=3.5');
tc.verifyLessThan(abs(mean(log.powerTrue)-w32.base_curve(3.5,c)),1e-3,'悬停功率应=J0(|w|)');
c0=w32.config('seed',3,'windKind','const','windBias',0,'openLoopV',6.3);
[log0,~]=w32.run_algorithm('openloop',w32.scenario('static',c0),c0);
tc.verifyEqual(w32.mop_moe(log0,c0).MOE_energy,1.0,'AbsTol',1e-9,'零风匀速@u*应=最优');
end

function test_moe_overall_is_energy_only(tc)
% 2026-09-04用户口径: MOE只考虑续航能耗, overall=Emin/Eactual。
c=w32.config('seed',3);
scn=w32.scenario('static',c);
[log,~]=w32.run_algorithm('windinfer',scn,c);
m=w32.mop_moe(log,c);
tc.verifyEqual(m.MOE.overall,m.MOE_energy,'AbsTol',1e-12,'overall应=MOE_energy');
tc.verifyEqual(m.MOE.overall,m.MOE.energy,'AbsTol',1e-12,'overall应=MOE.energy');
end

%% ---------- 任务3.2核心: 曲线未知(sweepcal/rl) ----------
function test_ctrl_view_whitelist(tc)
% 红线1结构核验: 曲线未知口径下, 控制器白名单不含任何曲线/最优点/噪声真值。
c0=w32.config();
p=w32.ctrl_view(c0);
drop={'curveCoef','curveCase','pHover','p20','rippleA1','rippleL1','rippleF1',...
    'rippleA2','rippleL2','optimum0','noiseSigma','eps','tailSteps'};
for k=1:numel(drop)
    tc.verifyFalse(isfield(p,drop{k}),'白名单不应包含真值字段');
end
keep={'lower','upper','initialSpeed','tEval','turnRadius','latencySec','aMax','openLoopV'};
for k=1:numel(keep)
    tc.verifyTrue(isfield(p,keep{k}),'白名单应保留控制器合法知识');
end
end

function test_sweepcal_identifies_curve_and_wind(tc)
% 恒定风: 全速域标定+在线精化, 不知曲线不知风不知u*, 应辨识出 û*≈6.3 与风矢量,
% 能耗显著优于开环(单一速度点基线)。
c=w32.config('seed',3,'windKind','const','windBias',3.5,'windDirDeg',40,'duration',800);
scn=w32.scenario('static',c);
[log,info]=w32.run_algorithm('sweepcal',scn,c);
m=w32.mop_moe(log,c);
[logO,~]=w32.run_algorithm('openloop',scn,c);
mO=w32.mop_moe(logO,c);
tc.verifyLessThan(abs(info.uStar-c.optimum0),0.6,'û*辨识误差应<0.6 m/s');
wT=[3.5*cosd(40);3.5*sind(40)];
we=info.windEst; kF=find(isfinite(we(1,:)),1,'last');
tc.verifyLessThan(norm(we(:,kF)-wT),1.0,'风矢量辨识误差应<1.0 m/s');
tc.verifyLessThan(m.energyExcessPercent,4.5,'能耗超额应<4.5%');
tc.verifyLessThan(m.energyExcessPercent,mO.energyExcessPercent,'应优于开环基线');
tc.verifyEqual(info.calibSteps,c.swSteps,'标定步数应=swSteps');
end

function test_sweepcal_zero_wind(tc)
% 零风: 标定应直接找到u*并恒飞, 超额小。
c=w32.config('seed',3,'windKind','const','windBias',0,'windDirDeg',0,'duration',600);
scn=w32.scenario('static',c);
[log,info]=w32.run_algorithm('sweepcal',scn,c);
m=w32.mop_moe(log,c);
% 标定段(前swSteps步故意飞离最优点采样)是一次性学费, 摊在总账上≈3%;
% 门槛用尾段稳态口径(regretPercent): 标定完成后应贴近最优。
tc.verifyLessThan(m.regretPercent,1.5,'零风下标定后稳态应接近最优(尾段)');
tc.verifyLessThan(m.energyExcessPercent,4.5,'含标定学费的总超额应<4.5%');
tc.verifyLessThan(abs(info.uStar-c.optimum0),0.6,'零风下û*辨识应<0.6');
end

function test_sweepcal_vary_wind_beats_openloop(tc)
% 变风: 标定块+在线联合重拟合, 至少应优于不补偿的开环。
wcfg={'windKind','composite','windBias',2.5,'windAmp',1.5,'windOmega',0.08,...
    'windBiasY',0,'windAmpY',0,'turbStd',0.3};
c=w32.config('seed',3,wcfg{:},'duration',800);
scn=w32.scenario('static',c);
[logI,~]=w32.run_algorithm('sweepcal',scn,c);
[logO,~]=w32.run_algorithm('openloop',scn,c);
mI=w32.mop_moe(logI,c); mO=w32.mop_moe(logO,c);
tc.verifyLessThan(mI.energyExcessPercent,mO.energyExcessPercent+0.2,...
    '变风下应不劣于开环(非劣性; 漂移风追踪受滑窗滞后约束)');
end

function test_rl_completes_and_anneals_honest(tc)
% RL对照(在线策略梯度): 预算走满/有限/σ退火到位; 性能上如实允许其不敌标定法
% (谷底奖励二阶+1%噪声, 等预算下样本效率不足——诚实负结果, 与speed_rl_pytorch一致)。
c=w32.config('seed',3,'duration',600);
scn=w32.scenario('static',c);
[log,info]=w32.run_algorithm('rl',scn,c);
m=w32.mop_moe(log,c);
tc.verifyEqual(height(log),c.duration,'RL预算未走满');
tc.verifyTrue(all(isfinite(log.powerMeas)),'RL出现非有限测量');
tc.verifyLessThan(info.sigma,c.rlSigma+1e-9,'σ应退火不增');
tc.verifyTrue(isfinite(m.MOE_energy),'RL的MOE应有限');
end

function test_sweepcal_rl_all_kinds_complete(tc)
% sweepcal/rl 在七种风场下都能完整跑完(鲁棒性)。
kinds={'const','sin','square','triangle','turb','composite','sector'};
for kk=1:numel(kinds)
    c=w32.config('seed',11,'duration',250,'tailSteps',5,'windKind',kinds{kk},...
        'windAmpY',1.5,'windBiasY',1);
    [log1,~]=w32.run_algorithm('sweepcal',w32.scenario('static',c),c);
    [log2,~]=w32.run_algorithm('rl',w32.scenario('static',c),c);
    [log3,~]=w32.run_algorithm('purerl',w32.scenario('static',c),c);
    tc.verifyEqual(height(log1),250,'sweepcal预算未走满');
    tc.verifyEqual(height(log2),250,'rl预算未走满');
    tc.verifyEqual(height(log3),250,'purerl预算未走满');
end
end

%% ---------- 任务3.2核心: 纯奖励RL(无扫频/无模型) ----------
function test_purerl_structural_model_free(tc)
% 结构核验: pure_rl 的输出不含任何模型/辨识字段(无coefs/无uStar),
% 它不学世界模型, 只学策略本身(查表μ)。
c=w32.config('seed',3,'duration',300);
scn=w32.scenario('static',c);
[~,info]=w32.run_algorithm('purerl',scn,c);
tc.verifyFalse(isfield(info,'coefs'),'纯奖励RL不应输出拟合曲线');
tc.verifyFalse(isfield(info,'uStar'),'纯奖励RL不应输出显式u*辨识');
tc.verifyTrue(isfield(info,'muB'),'应输出表格策略μ');
end

function test_purerl_const_beats_openloop(tc)
% 恒定风: 无扫频/无模型/无u*知识, 仅凭奖励学出的策略应显著优于开环基线。
c=w32.config('seed',3,'windKind','const','windBias',3.5,'windDirDeg',40,'duration',1200);
scn=w32.scenario('static',c);
[log,info]=w32.run_algorithm('purerl',scn,c);
m=w32.mop_moe(log,c);
[logO,~]=w32.run_algorithm('openloop',scn,c);
mO=w32.mop_moe(logO,c);
tc.verifyLessThan(m.energyExcessPercent,mO.energyExcessPercent,'纯奖励RL应优于开环');
tc.verifyLessThan(m.energyExcessPercent,4.5,'1200步时应收敛到<4.5%');
tc.verifyGreaterThan(max(info.muB)-min(info.muB),2.5,'应学到明显的地速补偿轮廓');
end

function test_purerl_vary_beats_openloop(tc)
% 变风: 无标定的纯在线RL仍应优于不补偿的开环。
wcfg={'windKind','composite','windBias',2.5,'windAmp',1.5,'windOmega',0.08,...
    'windBiasY',0,'windAmpY',0,'turbStd',0.3};
c=w32.config('seed',3,wcfg{:},'duration',800);
scn=w32.scenario('static',c);
[log,~]=w32.run_algorithm('purerl',scn,c);
[logO,~]=w32.run_algorithm('openloop',scn,c);
m=w32.mop_moe(log,c); mO=w32.mop_moe(logO,c);
tc.verifyLessThan(m.energyExcessPercent,mO.energyExcessPercent,'变风下应优于开环');
end

function test_purerl_no_sweep_calibration(tc)
% 任务3.2核心主张: 全程不扫频——前150步不应出现sweepcal式全速域斜坡
% (指令幅值从3扫到12)。检查前150步指令始终在初速±探索幅值邻域内。
c=w32.config('seed',3,'duration',600);
scn=w32.scenario('static',c);
[log,~]=w32.run_algorithm('purerl',scn,c);
early=log.speedCmd(1:150);
tc.verifyLessThan(max(early),c.initialSpeed+c.plSigma0+0.5,'前150步不应出现全速域扫频(高速段)');
tc.verifyGreaterThan(min(early),c.initialSpeed-c.plSigma0-0.5,'前150步不应出现全速域扫频(低速段)');
end
