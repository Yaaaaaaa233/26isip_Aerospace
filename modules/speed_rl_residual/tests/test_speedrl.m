function tests = test_speedrl
tests=functiontests(localfunctions);
end

function testConfigAndNames(t)
c=speedrl.config(); verifyEqual(t,numel(speedrl.observation_names()),18);
verifyEqual(t,18*c.history,144); verifyError(t,@()speedrl.config('windMode','bad'),'speedrl:Config');
end

function testAdapterContractAndVectorWind(t)
c=speedrl.config('windMode','constant','windNoiseStd',0,'windDelay',0,'powerNoiseFraction',0,'powerDelay',0);
a=speedrl.make_synthetic_adapter(); [s,x]=speedrl.validate_adapter(a,c); %#ok<ASGLU>
expected=norm([c.initialSpeed;0]-c.constantWind);
verifyEqual(t,x.evaluator.true_air_speed_mps,expected,'AbsTol',1e-10);
end

function testTrainingRandomizesConstantWindAcrossEpisodes(t)
c=speedrl.config('windMode','constant','randomizeWind',true,'windNoiseStd',0,'windDelay',0);
a=speedrl.make_synthetic_adapter(); [~,x1]=a.reset(1,c); [~,x2]=a.reset(2,c);
verifyNotEqual(t,x1.evaluator.true_wind_ne_mps,x2.evaluator.true_wind_ne_mps);
end

function testCircleTangent(t)
c=speedrl.config('trajectory','circle','windMode','none'); a=speedrl.make_synthetic_adapter();
[s,~]=a.reset(1,c); [~,x]=a.step(s,6.3,c.Ts);
verifyEqual(t,norm(x.path_tangent_ne),1,'AbsTol',1e-12);
verifyGreaterThan(t,x.path_phase_rad,0);
end

function testBaselineUsesMeasuredWindOnly(t)
c=speedrl.config('windMode','constant','windNoiseStd',0,'windDelay',0);
a=speedrl.make_synthetic_adapter(); [~,x]=a.reset(1,c);
ctx=speedrl.context(x,c.initialSpeed,0,x.power_w,0,c);
b=speedrl.make_baseline('wind_analytic'); [v,info]=b.reference(ctx);
expected=c.constantWind(1)+sqrt(c.optimumAirSpeed^2-c.constantWind(2)^2);
verifyEqual(t,v,expected,'AbsTol',1e-10); verifyTrue(t,info.usedWind);
x.wind_valid=false; x.wind_velocity_ne_mps(:)=NaN; x.wind_sample_time_s=NaN;
ctx=speedrl.context(x,c.initialSpeed,0,x.power_w,0,c); [v,info]=b.reference(ctx);
verifyEqual(t,v,c.baselineSpeed); verifyFalse(t,info.usedWind);
end

function testHiddenWindObservation(t)
c=speedrl.config('windMode','constant','windObservation','hidden');
[o,s]=speedrl.reset(c,speedrl.make_synthetic_adapter(),speedrl.make_baseline('fixed'));
verifyFalse(t,s.sample.wind_valid); verifyTrue(t,all(isnan(s.sample.wind_velocity_ne_mps)));
frame=reshape(o,18,c.history); verifyEqual(t,frame([8 9 10 18],end),zeros(4,1));
verifyNotEqual(t,s.sample.evaluator.true_wind_ne_mps,zeros(2,1));
end

function testGuard(t)
c=speedrl.config(); a=speedrl.make_synthetic_adapter(); [~,x]=a.reset(1,c);
[r,info]=speedrl.guard(15,6.3,x,c.Ts,c);
verifyEqual(t,r,6.3+c.speedRate*c.Ts,'AbsTol',1e-12); verifyFalse(t,info.blocked);
x.power_valid=false; [r,info]=speedrl.guard(10,6.3,x,c.Ts,c);
verifyEqual(t,r,6.3); verifyTrue(t,info.blocked);
end

function testEnvironmentModes(t)
for mode={'none','constant','step','sine','irregular','mixed'}
    c=speedrl.config('windMode',mode{1},'duration',4,'history',2);
    env=speedrl.make_env(c); validateEnvironment(env); o=reset(env); %#ok<NASGU>
    done=false; count=0;
    while ~done, [o,r,done]=step(env,0); verifyTrue(t,all(isfinite(o))); verifyTrue(t,isfinite(r)); count=count+1; end
    verifyEqual(t,count,4);
end
end

function testDeterministicEpisode(t)
c=speedrl.config('duration',8,'seed',44);
[a,ma]=speedrl.run_episode(c,'scripted'); [b,mb]=speedrl.run_episode(c,'scripted');
verifyEqual(t,a,b); verifyEqual(t,ma.meanPowerW,mb.meanPowerW);
end

function testScriptedReferenceImprovesConstantWind(t)
c=speedrl.config('duration',80,'windMode','constant','windNoiseStd',0,'windDelay',0,...
    'powerNoiseFraction',0,'powerDelay',0);
[~,fixed]=speedrl.run_episode(c,'baseline'); [~,adaptive]=speedrl.run_episode(c,'scripted');
verifyLessThan(t,adaptive.meanPowerW,fixed.meanPowerW);
verifyEqual(t,adaptive.boundViolations,0); verifyEqual(t,adaptive.rateViolations,0);
end

function testFixedDurationAndMinimumSpeed(t)
c=speedrl.config('duration',10); [L,m]=speedrl.run_episode(c,@minimumAction);
verifyEqual(t,height(L),10); verifyGreaterThanOrEqual(t,m.minimumGroundSpeed,c.speedBounds(1));
verifyEqual(t,m.boundViolations,0); verifyEqual(t,m.rateViolations,0);
    function a=minimumAction(~,~,~,cc), a=cc.deltaBounds(1); end
end
