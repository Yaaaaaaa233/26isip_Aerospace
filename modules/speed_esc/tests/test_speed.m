function tests = test_speed
tests=functiontests(localfunctions);
end

function testProxyCurves(t)
for curve={'debug','cubic'}
    c=speedesc.config('curve',curve{1}); x=linspace(c.lower,c.upper,20001);
    y=speedesc.power_map(x,c.optimum,c); [~,k]=min(y);
    verifyLessThan(t,abs(x(k)-c.optimum),.002);
    minimum=1; if strcmp(c.curve,'cubic'), minimum=.913; end
    verifyEqual(t,speedesc.power_map(c.optimum,c.optimum,c),minimum,'AbsTol',1e-12);
end
end

function testExactSpeedResponse(t)
c=speedesc.config('version',2,'initialSpeed',2); s=speedesc.plant_reset(c);
[m,~]=speedesc.plant_step(s,10,0,c.optimum,0,c);
verifyEqual(t,m.actualSpeed,10+(2-10)*exp(-c.Ts/c.tau),'AbsTol',1e-12);
verifyEqual(t,m.truePower,speedesc.power_map(m.actualSpeed,c.optimum,c),'AbsTol',1e-12);
end

function testPairedDelay(t)
c=speedesc.config('version',3,'noiseSigma',0,'shift',false); s=speedesc.plant_reset(c);
records=zeros(20,2); received=zeros(20,3);
for k=1:20
    time=(k-1)*c.Ts; [m,s]=speedesc.plant_step(s,5+k*.1,time,c.optimum,0,c);
    records(k,:)=[m.actualSpeed,m.truePower]; received(k,:)=[m.pairedSpeed,m.measuredPower,m.powerTime];
end
verifyEqual(t,received(6:end,1:2),records(1:end-5,:),'AbsTol',1e-12);
verifyEqual(t,received(1:6,3),zeros(6,1),'AbsTol',1e-12);
end

function testRegressionDirection(t)
c=speedesc.config(); p=speedesc.controller_config(c);
for slope=[-.03 .03]
    s=speedesc.estimator_reset(p);
    for k=1:400
        time=(k-1)*p.Ts; speed=8+.5*sin(p.omega*time);
        [s,d]=speedesc.estimate_step(s,1+slope*speed,speed,time,time,true,p);
    end
    verifyEqual(t,d.rawGradient,slope,'AbsTol',1e-12);
    verifyEqual(t,d.gradient,slope,'AbsTol',1e-8); verifyTrue(t,d.ready);
end
end

function testWarmupAndWeakExcitation(t)
c=speedesc.config(); p=speedesc.controller_config(c); s=speedesc.estimator_reset(p);
for k=1:2*p.window
    time=(k-1)*p.Ts; [s,d]=speedesc.estimate_step(s,1,6,time,time,true,p);
    verifyFalse(t,d.ready);
end
end

function testDuplicateMeasurementNotCounted(t)
p=speedesc.controller_config(speedesc.config()); s=speedesc.estimator_reset(p);
[s,~]=speedesc.estimate_step(s,1,6,0,0,true,p);
[s,d]=speedesc.estimate_step(s,1,6,0,.1,true,p);
verifyEqual(t,s.count,1); verifyFalse(t,d.fresh); verifyFalse(t,d.ready);
end

function testFreezeAndRecovery(t)
c=speedesc.config(); p=speedesc.controller_config(c); s=speedesc.esc_reset(10,p);
[ref,s,~]=speedesc.esc_step(s,1,10,0,0,true,p);
s=speedesc.freeze(s,true); [held,s,d]=speedesc.esc_step(s,2,8,.1,.1,true,p);
verifyEqual(t,held,ref); verifyTrue(t,d.frozen);
s=speedesc.freeze(s,false); [~,s,d]=speedesc.esc_step(s,1.1,9,.2,.2,true,p);
verifyFalse(t,d.ready); verifyEqual(t,s.estimator.count,1);
end

function testInvalidAndOldSamples(t)
p=speedesc.controller_config(speedesc.config()); s=speedesc.esc_reset(10,p);
for values={[NaN,0,0],[1,2,1],[1,0,5]}
    a=values{1}; [ref,~,d]=speedesc.esc_step(s,a(1),10,a(2),a(3),true,p);
    verifyTrue(t,d.frozen); verifyEqual(t,ref,10);
end
end

function testReferenceBoundsAndSlew(t)
c=speedesc.config(); p=speedesc.controller_config(c);
for initial=[0 20]
    s=speedesc.reference_reset(initial,p); old=initial;
    for k=1:500
        [ref,s,~]=speedesc.reference_step(s,100*sin(k),true,true,k*p.Ts,p);
        verifyGreaterThanOrEqual(t,ref,p.lower); verifyLessThanOrEqual(t,ref,p.upper);
        verifyLessThanOrEqual(t,abs(ref-old),p.referenceRate*p.Ts+1e-12); old=ref;
    end
end
end

function testControllerNoTruthLeak(t)
c=speedesc.config(); p=speedesc.controller_config(c);
c.optimum=8; c.shiftTime=40; c.minimumRatio=.8;
verifyEqual(t,p,speedesc.controller_config(c));
verifyFalse(t,isfield(p,'optimum')); verifyFalse(t,isfield(p,'curve'));
end

function testDeterministicReplay(t)
c=speedesc.config('duration',40,'tailSeconds',10,'shiftTime',15);
verifyEqual(t,speedesc.run(c),speedesc.run(c));
end

function testVersionFactors(t)
v1=speedesc.config('version',1); v2=speedesc.config('version',2);
verifyEqual(t,v1.delay,0); verifyEqual(t,v2.noiseSigma,0); verifyFalse(t,v1.shift);
verifyError(t,@()speedesc.config('delay',.15),'speedesc:Config');
end

function testRlSharesFixedPlant(t)
c=speedesc.config('mode','fixed','fixedReference',8,'duration',40,'tailSeconds',10,'shiftTime',15);
expected=speedesc.run(c); [~,s]=speedesc.rl_reset(c); actual=[]; done=false;
while ~done
    [o,reward,done,s]=speedesc.rl_step(8,s); actual=[actual;s.lastSegment]; %#ok<AGROW>
    verifyTrue(t,all(isfinite(o))); verifyTrue(t,isfinite(reward));
end
verifyEqual(t,actual,expected{:,{'time','actualSpeed','appliedReference','truePower'}},'AbsTol',1e-12);
verifyError(t,@()speedesc.rl_step(8,s),'speedesc:EpisodeDone');
end

function testTelemetryShadowPairing(t)
file=[tempname '.csv']; clean=onCleanup(@()delete(file)); %#ok<NASGU>
time=(0:.1:4)'; v=6+time; battery=max(0,time-.5);
T=table(time,time,v,zeros(size(v)),battery,24*ones(size(v)),20*ones(size(v)),...
    'VariableNames',{'time_s','velocity_time_s','vn_mps','ve_mps','battery_time_s','voltage_v','current_a'});
writetable(T,file); L=replay_speed_log(file,480);
verifyEqual(t,L.paired_speed_mps(6:end),v(1:end-5),'AbsTol',1e-10);
verifyEqual(t,L.normalized_power,ones(height(L),1));
verifyTrue(t,ismember('candidate_speed_NOT_APPLIED',L.Properties.VariableNames));
end
