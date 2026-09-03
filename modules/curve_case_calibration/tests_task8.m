function tests = tests_task8()
%TESTS_TASK8 任务8单元测试: 曲线标定锚点(case1/2/3) + 噪声保留 + 执行链回归。
tests = functiontests(localfunctions);
end
function test_case_anchors_exact(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
for r=[0.95 0.90 0.85]
    c=w8.config('curveCase',r);
    tc.verifyEqual(w8.base_curve(0,c),1.0,'AbsTol',1e-9);
    tc.verifyEqual(w8.base_curve(c.optimum0,c),r,'AbsTol',1e-9);
    vv=0:0.005:20; Pw=w8.base_curve(vv,c);
    [~,im]=min(Pw);
    tc.verifyTrue(abs(vv(im)-c.optimum0)<0.01,'全局谷底应恰在V*');
end
end
function test_reference_anchors_watts(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w8.config();
tc.verifyEqual(c.pHover,103.7); tc.verifyEqual(c.p20,134.5);
tc.verifyEqual(w8.base_curve(20,c)*c.pHover,134.5,'AbsTol',3.5);
end
function test_smooth_part_u_shaped(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w8.config();
dS=polyval(polyder(c.curveCoef),0:0.05:20);
tc.verifyTrue(all(dS(1:126)<0));
tc.verifyTrue(all(dS(127:end)>0));
end
function test_grad_finite_difference(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w8.config();
for x=[2.0 6.3 10.5 18.0]
    h=1e-6;
    fd=(w8.base_curve(x+h,c)-w8.base_curve(x-h,c))/(2*h);
    tc.verifyEqual(w8.base_curve_grad(x,c),fd,'AbsTol',1e-7);
end
end
function test_latency_impulse(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w8.config('initialSpeed',10,'openLoopV',4,'windAmp',0,'windBias',0,'windAmpY',0,'windBiasY',0,'latencySec',0.3);
[log,~]=w8.run_algorithm('openloop',w8.scenario('static',c),c);
tc.verifyEqual(log.speed(1),8.6,'AbsTol',1e-9);
end
function test_task2_noise_kept(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w8.config('seed',11);
[log,~]=w8.run_algorithm('openloop',w8.scenario('static',c),c);
rel=(log.powerMeas-log.powerTrue)./log.powerTrue;
tc.verifyEqual(std(rel),0.01,'AbsTol',0.004);
tc.verifyEqual(mean(rel),0,'AbsTol',0.005);
end
function test_accel_and_budget_all_policies(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
policies={'openloop','tracker','esc','spsa','bayes','qnewton','gtrack','est','known'};
for name=policies
    c=w8.config('seed',11);
    [log,~]=w8.run_algorithm(name{1},w8.scenario('static',c),c);
    tc.verifyEqual(height(log),c.duration,sprintf('%s预算未走满',name{1}));
    tc.verifyTrue(all(log.accelMax<=c.aMax+1e-9),sprintf('%s加速度超限',name{1}));
end
end
function test_heading_integration(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w8.config('initialSpeed',6.3,'openLoopV',6.3,'windAmp',0,'windBias',0,'windAmpY',0,'windBiasY',0);
[log,~]=w8.run_algorithm('openloop',w8.scenario('static',c),c);
psiExp=rad2deg(cumsum(log.speed)*c.tEval/c.turnRadius);
tc.verifyEqual(max(abs(mod(log.headingDeg-psiExp+180,360)-180)),0,'AbsTol',1e-6);
end
function test_openloop_nowind_is_upper(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w8.config('initialSpeed',6.3,'openLoopV',6.3,'windAmp',0,'windBias',0,'windAmpY',0,'windBiasY',0);
[log,~]=w8.run_algorithm('openloop',w8.scenario('static',c),c);
tc.verifyEqual(w8.mop_moe(log,c).MOE_energy,1.0,'AbsTol',1e-9);
end
function test_known_oracle_information_value(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
exK=zeros(1,5); exO=zeros(1,5);
for i=1:5
    c=w8.config('seed',10+i);
    scn=w8.scenario('static',c);
    [log,~]=w8.run_algorithm('known',scn,c);
    exK(i)=w8.mop_moe(log,c).energyExcessPercent;
    [log,~]=w8.run_algorithm('openloop',scn,c);
    exO(i)=w8.mop_moe(log,c).energyExcessPercent;
end
tc.verifyTrue(mean(exK)<1.0);
tc.verifyTrue(mean(exO)-mean(exK)>3.0);
end
function test_moe_identity_and_case_in_plant(tc)
wind={'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
c=w8.config('seed',11,'curveCase',0.85);
[log,~]=w8.run_algorithm('openloop',w8.scenario('static',c),c);
m=w8.mop_moe(log,c);
tc.verifyEqual(m.MOE_energy,1/(1+m.energyExcessPercent/100),'AbsTol',1e-9);
tc.verifyEqual(mean(log.minPowerTrue),0.85,'AbsTol',1e-9);
end

