function tests = tests_task9()
%TESTS_TASK9 任务9单元测试: 七种风场模型库 + 空速语义(空速=地速+风) +
% 任务8曲线case标定锚点回归 + 任务7执行链(时延/限幅/航向积分)回归。
tests = functiontests(localfunctions);
end

%% ---------- 风场模型库 ----------
function test_wind_models_values(tc)
wind={'windAmp',2,'windOmega',0.4,'windBias',3,'windAmpY',1.5,'windOmegaY',0.7,...
    'windBiasY',1,'windDirDeg',0,'duration',40,'tailSteps',5};
t=[0 1.37 9.1 22.8];
% const: 恒等于偏置
c=w9.config(wind{:},'windKind','const'); scn=w9.scenario('static',c);
[wx,wy]=w9.wind_field(scn,[0 12.3 40],0);
tc.verifyEqual(wx,[3 3 3],'AbsTol',1e-12);
tc.verifyEqual(wy,[1 1 1],'AbsTol',1e-12);
% sin: 与闭式一致(任务4/5/8原口径)
c=w9.config(wind{:},'windKind','sin'); scn=w9.scenario('static',c);
[wx,wy]=w9.wind_field(scn,t,0);
tc.verifyEqual(wx,2*sin(0.4*t)+3,'AbsTol',1e-12);
tc.verifyEqual(wy,1.5*sin(0.7*t)+1,'AbsTol',1e-12);
% square: 软边方波——峰值=B+A, 有界, 连续(边缘陡度有界)
c=w9.config(wind{:},'windKind','square','squareEdge',4); scn=w9.scenario('static',c);
tp=pi/2/0.4;
[wx,~]=w9.wind_field(scn,tp,0);
tc.verifyEqual(wx,5,'AbsTol',1e-9);
tt=0:0.01:40;
[wx,wy]=w9.wind_field(scn,tt,0);
tc.verifyTrue(max(abs(wx-3))<=2+1e-9 && max(abs(wy-1))<=1.5+1e-9,'方波必须有界');
dwx=abs(diff(wx)); bound=2*0.4*(4/tanh(4))*0.01+1e-12;
tc.verifyTrue(max(dwx)<=bound,'软边方波应连续(边缘陡度有界)');
% triangle: 峰值=B+A, 上升段斜率=A·ω·2/π
c=w9.config(wind{:},'windKind','triangle'); scn=w9.scenario('static',c);
[wx,~]=w9.wind_field(scn,tp,0);
tc.verifyEqual(wx,5,'AbsTol',1e-9);
t2=[0 tp/2 tp];
[wx,~]=w9.wind_field(scn,t2,0);
slope=(wx(2)-wx(1))/(t2(2)-t2(1));
tc.verifyEqual(slope,2*0.4*2/pi,'AbsTol',1e-9);
% turb: 确定性(同种子同序列)+平稳统计(std≈windAmp, 均值≈0)
wA=2.0;
c1=w9.config(wind{:},'windKind','turb','windAmp',wA,'turbTheta',0.2,'duration',4000);
s1=w9.scenario('static',c1); s2=w9.scenario('static',c1);
tc.verifyEqual(s1.windTurbX,s2.windTurbX);
tc.verifyEqual(s1.windTurbY,s2.windTurbY);
tc.verifyLessThan(abs(std(s1.windTurbX(10000:end))-wA),0.5,'OU平稳std应≈windAmp');
tc.verifyLessThan(abs(mean(s1.windTurbX(10000:end))),0.3,'OU均值应≈0');
% composite: turbStd=0 时退化为纯sin; turbStd>0 时叠加std≈turbStd的湍流
c=w9.config(wind{:},'windKind','composite','turbStd',0); scn=w9.scenario('static',c);
[wx,wy]=w9.wind_field(scn,t,0);
tc.verifyEqual(wx,2*sin(0.4*t)+3,'AbsTol',1e-12);
c=w9.config(wind{:},'windKind','composite','turbStd',0.3,'seed',5,'duration',400);
scn=w9.scenario('static',c);
tt2=0:0.01:400;
[wx,~]=w9.wind_field(scn,tt2,0);
resid=wx-(2*sin(0.4*tt2)+3);
tc.verifyLessThan(abs(std(resid(10000:end))-0.3),0.05,'复合风湍流分量std应≈turbStd');
% sector: 与时间无关、周期2π、绕偏置幅值=A
c=w9.config(wind{:},'windKind','sector'); scn=w9.scenario('static',c);
[wx1,wy1]=w9.wind_field(scn,0,0);
[wx2,wy2]=w9.wind_field(scn,137.9,0);
tc.verifyEqual(wx1,wx2); tc.verifyEqual(wy1,wy2);
[wx3,wy3]=w9.wind_field(scn,0,2*pi);
tc.verifyEqual(wx3,wx1,'AbsTol',1e-12); tc.verifyEqual(wy3,wy1,'AbsTol',1e-12);
[wxp,~]=w9.wind_field(scn,0,pi);   % ψ=π: Wx=B−A·cos(π)=B+A
tc.verifyEqual(wxp,5,'AbsTol',1e-12);
[wxh,wyh]=w9.wind_field(scn,0,pi/2); % ψ=π/2: Wx=B−A·cos(π/2)=B, Wy=D+C·sin(π/2)=D+C
tc.verifyEqual(wxh,3,'AbsTol',1e-12);
tc.verifyEqual(wyh,1+1.5,'AbsTol',1e-12);
end

function test_sector_periodic_profile(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w9.config(wind{:},'windKind','sector');
scn=w9.scenario('static',c);
psd=deg2rad(0:1:360);
[wx,wy]=w9.wind_field(scn,0,psd);
tc.verifyEqual(wx(1),wx(end),'AbsTol',1e-12,'ψ=0与ψ=2π风应相同(周期)');
tc.verifyEqual(wy(1),wy(end),'AbsTol',1e-12);
tc.verifyLessThan(max(wx)-min(wx),4.0001,'扇区风x向峰峰应=2A');
end

function test_wind_rotation(tc)
wind={'windAmp',2,'windOmega',0.4,'windBias',3,'windAmpY',1.5,'windOmegaY',0.7,...
    'windBiasY',1,'windDirDeg',90,'windKind','sin','duration',40,'tailSteps',5};
c=w9.config(wind{:}); scn=w9.scenario('static',c);
t=3.7;
[wx,wy,vx,vy]=w9.wind_field(scn,t,0);
tc.verifyEqual(vx,-wy,'AbsTol',1e-12);   % R(90°)[Wx;Wy]=[-Wy;Wx]
tc.verifyEqual(vy,wx,'AbsTol',1e-12);
end

%% ---------- 空速语义(空速=地速+风; 功率由空速决定) ----------
function test_plant_airspeed_identity(tc)
wind={'windAmp',0,'windBias',3,'windAmpY',0,'windBiasY',1,'windKind','const'};
c=w9.config('seed',11,'duration',30,'tailSteps',5,wind{:});
[log,~]=w9.run_algorithm('openloop',w9.scenario('static',c),c);
psi=deg2rad(log.headingDeg);
uExp=hypot(log.speed.*cos(psi)+log.windX, log.speed.*sin(psi)+log.windY);
tc.verifyEqual(log.airspeed,uExp,'AbsTol',1e-9,'空速应=|地速矢量+风矢量|');
tc.verifyEqual(log.windX,3*ones(height(log),1),'AbsTol',1e-12);
tc.verifyEqual(log.windY,1*ones(height(log),1),'AbsTol',1e-12);
end

function test_plant_power_from_airspeed_nowind(tc)
wind={'windAmp',0,'windBias',0,'windAmpY',0,'windBiasY',0,'windKind','const'};
c=w9.config('seed',11,'duration',20,'tailSteps',5,'initialSpeed',6.3,'openLoopV',6.3,wind{:});
[log,~]=w9.run_algorithm('openloop',w9.scenario('static',c),c);
P63=w9.base_curve(6.3,c);   % 零风+恒地速: 空速=地速, 功率=base_curve(6.3)
tc.verifyEqual(log.powerTrue,P63*ones(height(log),1),'AbsTol',1e-9);
end

function test_ground_curve_optimum_closed_form(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w9.config('seed',11,'duration',40,'tailSteps',10,wind{:});
scn=w9.scenario('static',c);
plant=w9.make_plant(scn,c);
n=40; vK=6;
for k=1:n
    plant.q(vK,'hold'); plant.amendEstimate(vK);
end
log=plant.table();
for k=1:n
    tEnd=log.time(k)+c.tEval;
    psiE=deg2rad(log.headingDeg(k));
    [~,~,VxE,VyE]=w9.wind_field(scn,tEnd,psiE);
    qE=VxE*cos(psiE)+VyE*sin(psiE);
    disc=qE^2+c.optimum0^2-(VxE^2+VyE^2);
    if disc>0, vO=-qE+sqrt(disc); else, vO=-qE; end
    vO=min(max(vO,c.lower),c.upper);
    tc.verifyEqual(log.optimumTrue(k),vO,'AbsTol',1e-9,'地速最优应与闭式解一致');
end
end

function test_sector_optimum_varies_with_heading(tc)
wind={'windAmp',2,'windBias',0,'windAmpY',0,'windBiasY',0,'windKind','sector'};
c=w9.config('seed',11,'duration',60,'tailSteps',5,'initialSpeed',6.3,'openLoopV',6.3,wind{:});
[log,~]=w9.run_algorithm('openloop',w9.scenario('static',c),c);
tc.verifyGreaterThan(std(log.optimumTrue),0.02,'扇区风下地速最优应随航向变化');
wind0={'windAmp',0,'windBias',0,'windAmpY',0,'windBiasY',0,'windKind','const'};
c0=w9.config('seed',11,'duration',60,'tailSteps',5,'initialSpeed',6.3,'openLoopV',6.3,wind0{:});
[log0,~]=w9.run_algorithm('openloop',w9.scenario('static',c0),c0);
tc.verifyEqual(std(log0.optimumTrue),0,'AbsTol',1e-9,'零风下地速最优不应随时间变化');
tc.verifyEqual(mean(log0.optimumTrue),c0.optimum0,'AbsTol',1e-9,'零风下地速最优应=名义V*');
end

%% ---------- 任务8曲线case标定回归 ----------
function test_case_anchors_exact(tc)
for r=[0.95 0.90 0.85]
    c=w9.config('curveCase',r);
    tc.verifyEqual(w9.base_curve(0,c),1.0,'AbsTol',1e-9);
    tc.verifyEqual(w9.base_curve(c.optimum0,c),r,'AbsTol',1e-9);
    vv=0:0.005:20; Pw=w9.base_curve(vv,c);
    [~,im]=min(Pw);
    tc.verifyTrue(abs(vv(im)-c.optimum0)<0.01,'全局谷底应恰在V*');
end
end

function test_reference_anchors_watts(tc)
c=w9.config();
tc.verifyEqual(c.pHover,103.7); tc.verifyEqual(c.p20,134.5);
tc.verifyEqual(w9.base_curve(20,c)*c.pHover,134.5,'AbsTol',3.5);
end

function test_grad_finite_difference(tc)
c=w9.config();
for x=[2.0 6.3 10.5 18.0]
    h=1e-6;
    fd=(w9.base_curve(x+h,c)-w9.base_curve(x-h,c))/(2*h);
    tc.verifyEqual(w9.base_curve_grad(x,c),fd,'AbsTol',1e-7);
end
end

function test_moe_identity_and_case_in_plant(tc)
c=w9.config('seed',11,'curveCase',0.85);
[log,~]=w9.run_algorithm('openloop',w9.scenario('static',c),c);
m=w9.mop_moe(log,c);
tc.verifyEqual(m.MOE_energy,1/(1+m.energyExcessPercent/100),'AbsTol',1e-9);
tc.verifyEqual(mean(log.minPowerTrue),0.85,'AbsTol',1e-9);
end

%% ---------- 任务7执行链回归 ----------
function test_latency_impulse(tc)
c=w9.config('initialSpeed',10,'openLoopV',4,'windAmp',0,'windBias',0,...
    'windAmpY',0,'windBiasY',0,'windKind','const','latencySec',0.3);
[log,~]=w9.run_algorithm('openloop',w9.scenario('static',c),c);
tc.verifyEqual(log.speed(1),8.6,'AbsTol',1e-9);
% 任务9放宽: τ=0(无时延对照) — 指令立即释放, 仅受限幅: 第1步末 10-2×1=8
c0=w9.config('initialSpeed',10,'openLoopV',4,'windAmp',0,'windBias',0,...
    'windAmpY',0,'windBiasY',0,'windKind','const','latencySec',0);
[log0,~]=w9.run_algorithm('openloop',w9.scenario('static',c0),c0);
tc.verifyEqual(log0.speed(1),8.0,'AbsTol',1e-9,'τ=0时指令应立即生效(仅受限幅)');
tc.verifyTrue(all(log0.accelMax<=c0.aMax+1e-9),'τ=0时加速度限幅仍须成立');
end

function test_task2_noise_kept(tc)
c=w9.config('seed',11);
[log,~]=w9.run_algorithm('openloop',w9.scenario('static',c),c);
rel=(log.powerMeas-log.powerTrue)./log.powerTrue;
tc.verifyEqual(std(rel),0.01,'AbsTol',0.004);
tc.verifyEqual(mean(rel),0,'AbsTol',0.005);
end

function test_accel_and_budget_all_policies(tc)
policies={'openloop','tracker','esc','spsa','bayes','qnewton','gtrack','est','known'};
for name=policies
    c=w9.config('seed',11);
    [log,~]=w9.run_algorithm(name{1},w9.scenario('static',c),c);
    tc.verifyEqual(height(log),c.duration,sprintf('%s预算未走满',name{1}));
    tc.verifyTrue(all(log.accelMax<=c.aMax+1e-9),sprintf('%s加速度超限',name{1}));
    tc.verifyTrue(all(isfinite(log.powerMeas)),sprintf('%s出现非有限测量',name{1}));
end
end

function test_all_kinds_policies_smoke(tc)
kinds={'const','sin','square','triangle','turb','composite','sector'};
policies={'openloop','qnewton','known'};
for kk=1:numel(kinds)
    for pp=1:numel(policies)
        c=w9.config('seed',11,'duration',40,'tailSteps',5,'windKind',kinds{kk},...
            'windAmpY',1.5,'windBiasY',1);
        [log,~]=w9.run_algorithm(policies{pp},w9.scenario('static',c),c);
        tc.verifyEqual(height(log),40,...
            sprintf('%s×%s预算未走满',kinds{kk},policies{pp}));
        tc.verifyTrue(all(log.accelMax<=c.aMax+1e-9),...
            sprintf('%s×%s加速度超限',kinds{kk},policies{pp}));
        tc.verifyTrue(all(isfinite(log.powerTrue)),...
            sprintf('%s×%s功率非有限',kinds{kk},policies{pp}));
    end
end
end

function test_heading_integration(tc)
c=w9.config('initialSpeed',6.3,'openLoopV',6.3,'windAmp',0,'windBias',0,...
    'windAmpY',0,'windBiasY',0,'windKind','const');
[log,~]=w9.run_algorithm('openloop',w9.scenario('static',c),c);
psiExp=rad2deg(cumsum(log.speed)*c.tEval/c.turnRadius);
tc.verifyEqual(max(abs(mod(log.headingDeg-psiExp+180,360)-180)),0,'AbsTol',1e-6);
end

function test_openloop_nowind_is_upper(tc)
c=w9.config('initialSpeed',6.3,'openLoopV',6.3,'windAmp',0,'windBias',0,...
    'windAmpY',0,'windBiasY',0,'windKind','const');
[log,~]=w9.run_algorithm('openloop',w9.scenario('static',c),c);
tc.verifyEqual(w9.mop_moe(log,c).MOE_energy,1.0,'AbsTol',1e-9);
end

function test_known_oracle_information_value(tc)
exK=zeros(1,5); exO=zeros(1,5);
for i=1:5
    c=w9.config('seed',10+i);
    scn=w9.scenario('static',c);
    [log,~]=w9.run_algorithm('known',scn,c);
    exK(i)=w9.mop_moe(log,c).energyExcessPercent;
    [log,~]=w9.run_algorithm('openloop',scn,c);
    exO(i)=w9.mop_moe(log,c).energyExcessPercent;
end
tc.verifyTrue(mean(exK)<1.0);
tc.verifyTrue(mean(exO)-mean(exK)>3.0);
end
