function tests = test_core
tests=functiontests(localfunctions);
end

function testStaticOptimum(t)
c=ratioesc.config(); x=linspace(c.lower,c.upper,10001);
[value,k]=min(ratioesc.power_map(x,c.optimalRatio,c));
verifyEqual(t,value,1,'AbsTol',1e-12); verifyEqual(t,x(k),0.9,'AbsTol',1e-12);
end

function testConfigurationValidation(t)
verifyError(t,@()ratioesc.config('amplitude',0.3),'ratioesc:Config');
verifyError(t,@()ratioesc.config('delay',0.023),'ratioesc:Config');
verifyError(t,@()ratioesc.config('initialRatio',1.8),'ratioesc:Config');
end

function testActuatorAnalyticalResponse(t)
c=ratioesc.config('duration',3,'stage','feedback','initialRatio',0.8,...
    'fixedReference',1,'rateLimit',100);
l=ratioesc.run(c); expected=1+(0.8-1)*exp(-l.time/c.tau);
verifyEqual(t,l.ratio,expected,'AbsTol',1e-12);
end

function testDeterministicNoise(t)
c=ratioesc.config('duration',5,'noiseSigma',0.02);
a=ratioesc.make_inputs(c); b=ratioesc.make_inputs(c);
verifyEqual(t,a.noise,b.noise);
c.seed=2; b=ratioesc.make_inputs(c); verifyNotEqual(t,a.noise,b.noise);
end

function testMeasurementDelay(t)
c=ratioesc.config('duration',3,'stage','feedback','initialRatio',0.8,...
    'fixedReference',1,'delay',0.5);
l=ratioesc.run(c); d=round(c.delay/c.Ts);
verifyEqual(t,l.measuredPower(1:d),repmat(l.truePower(1),d,1),'AbsTol',1e-12);
verifyEqual(t,l.measuredPower(d+1:end),l.truePower(1:end-d),'AbsTol',1e-12);
end

function testDitherGradientDirection(t)
values=zeros(1,3);
for j=1:3
    ratios=[0.8 0.9 1.1]; c=ratioesc.config('stage','dither','duration',250,'initialRatio',ratios(j));
    l=ratioesc.run(c); values(j)=mean(l.gradient(l.time>=200));
    verifyEqual(t,l.center,ratios(j)*ones(height(l),1),'AbsTol',1e-12);
end
verifyLessThan(t,values(1),-0.5); verifyLessThan(t,abs(values(2)),0.05);
verifyGreaterThan(t,values(3),1);
end

function testBoundariesAndRate(t)
for ratio=[0.75 1.25]
    c=ratioesc.config('duration',60,'initialRatio',ratio,'gain',0.05);
    l=ratioesc.run(c);
    verifyGreaterThanOrEqual(t,min(l.reference),c.lower-1e-12);
    verifyLessThanOrEqual(t,max(l.reference),c.upper+1e-12);
    verifyLessThanOrEqual(t,max(abs(diff([ratio;l.reference]))),c.rateLimit*c.Ts+1e-12);
    verifyGreaterThanOrEqual(t,min(l.center),c.lower+c.amplitude-1e-12);
    verifyLessThanOrEqual(t,max(l.center),c.upper-c.amplitude+1e-12);
end
end

function testFreezeRecovery(t)
c=ratioesc.config(); p=ratioesc.controller_config(c); s=ratioesc.esc_reset(p,1.1,1.16);
for j=1:40, [~,s]=ratioesc.esc_step(s,1.16+0.002*sin(j),1.1,true,p); end
center=s.center; held=s.lastReference; s=ratioesc.freeze(s,true);
for j=1:10
    [ref,s,d]=ratioesc.esc_step(s,0.7,1.1,true,p);
    verifyEqual(t,ref,held); verifyEqual(t,s.center,center); verifyTrue(t,d.frozen);
end
s=ratioesc.freeze(s,false); [~,s,d]=ratioesc.esc_step(s,1.2,1.1,true,p);
verifyFalse(t,d.frozen); verifyEqual(t,d.highpass,0); verifyEqual(t,s.center,center);
verifyGreaterThan(t,s.warmup,0);
end

function testInvalidSample(t)
c=ratioesc.config(); p=ratioesc.controller_config(c); s=ratioesc.esc_reset(p,1,1.04);
[ref,s,d]=ratioesc.esc_step(s,NaN,1,true,p);
verifyEqual(t,ref,1); verifyTrue(t,d.frozen); verifyTrue(t,isfinite(s.bias));
[~,s,d]=ratioesc.esc_step(s,1.04,1,true,p);
verifyFalse(t,d.frozen); verifyEqual(t,d.highpass,0); verifyTrue(t,isfinite(s.gradient));
end

function testNoTruthInController(t)
a=ratioesc.config(); b=a; b.optimalRatio=1.08; b.curvature=9; b.scenario='shift';
verifyEqual(t,ratioesc.controller_config(a),ratioesc.controller_config(b));
p=ratioesc.controller_config(a);
verifyFalse(t,isfield(p,'optimalRatio')); verifyFalse(t,isfield(p,'curvature'));
end

function testRLResetRewardAndBounds(t)
c=ratioesc.config('duration',3,'noiseSigma',0.02);
[oa,a]=ratioesc.rl_reset(c); [ob,b]=ratioesc.rl_reset(c); verifyEqual(t,oa,ob);
[oa,r,done,a]=ratioesc.rl_step(5,a); [ob,rb,~,b]=ratioesc.rl_step(5,b);
verifyEqual(t,oa,ob); verifyEqual(t,r,rb); verifySize(t,oa,[4 1]); verifyFalse(t,done);
verifyEqual(t,r,-mean(a.lastSegment.measuredPower),'AbsTol',1e-12);
verifyLessThanOrEqual(t,max(a.lastSegment.reference),c.upper);
[~,~,~,a]=ratioesc.rl_step(-2,a); [~,~,done,a]=ratioesc.rl_step(1,a);
verifyTrue(t,done); verifyError(t,@()ratioesc.rl_step(1,a),'ratioesc:EpisodeDone');
end

function testRLFixedPolicyMatchesFeedback(t)
c=ratioesc.config('duration',7,'stage','feedback','noiseSigma',0.02,'delay',0.5,'fixedReference',1);
a=ratioesc.run(c); b=ratioesc.run_rl(c,'fixed');
verifyEqual(t,a{:,:},b{:,:},'AbsTol',1e-12);
end
