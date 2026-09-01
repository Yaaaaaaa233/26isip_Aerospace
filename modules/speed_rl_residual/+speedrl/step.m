function [observation,reward,done,s] = step(action,s)
%STEP TD3 action is a bounded correction to a replaceable baseline.
c=s.config; validateattributes(action,{'double'},{'scalar','real','finite'});
assert(s.steps<round(c.duration/c.decisionPeriod),'speedrl:EpisodeDone','Reset completed episode.');
delta=min(max(action,c.deltaBounds(1)),c.deltaBounds(2));
ctx0=speedrl.context(s.sample,s.reference,s.lastDelta,s.previousMean,0,c);
[base,baseInfo]=s.baseline.reference(ctx0);
request=base+delta;
if abs(s.sample.radial_error_m)>c.radialFreeze, request=base; end
n=round(c.decisionPeriod/c.Ts); powers=nan(n,1); truePowers=nan(n,1);
speeds=nan(n,1); airspeeds=nan(n,1); windAlong=nan(n,1); windNormal=nan(n,1);
blocked=0; radial=zeros(n,1); lastReason='ok'; oldReference=s.reference;
for k=1:n
    [s.reference,g]=speedrl.guard(request,s.reference,s.sample,c.Ts,c);
    if g.blocked, blocked=blocked+1; lastReason=g.reason; end
    [s.adapterState,s.sample]=s.adapter.step(s.adapterState,s.reference,c.Ts);
    if s.sample.power_valid, powers(k)=s.sample.power_w; end
    if isfield(s.sample,'evaluator'), truePowers(k)=s.sample.evaluator.true_power_w;
    elseif s.sample.power_valid, truePowers(k)=s.sample.power_w; end
    measured=speedrl.context(s.sample,s.reference,delta,s.previousMean,0,c);
    speeds(k)=measured.groundSpeed; airspeeds(k)=measured.airSpeed;
    windAlong(k)=measured.windAlong; windNormal(k)=measured.windNormal;
    radial(k)=s.sample.radial_error_m;
end
speedrl.validate_sample(s.sample);
good=isfinite(powers); coverage=mean(good);
if any(good), meanPower=mean(powers(good)); else, meanPower=s.previousMean; end
deltaPower=meanPower-s.previousMean;
ctx=speedrl.context(s.sample,s.reference,delta,meanPower,deltaPower,c);
[nextBase,~]=s.baseline.reference(ctx); ctx.baseSpeed=nextBase;
[observation,s.history]=speedrl.observe(ctx,s.history,c);
move=((delta-s.lastDelta)/diff(c.deltaBounds))^2;
trajectoryCost=mean((radial/c.radialScale).^2);
powerCost=meanPower/c.powerScale;
reward=-powerCost-c.movePenalty*move-c.missingPenalty*(1-coverage)-...
    c.blockedPenalty*blocked/n-c.trajectoryPenalty*trajectoryCost;
s.previousMean=meanPower; s.lastDelta=delta; s.steps=s.steps+1;
done=s.steps>=round(c.duration/c.decisionPeriod);
if any(isfinite(truePowers)), trueMean=mean(truePowers,'omitnan'); else, trueMean=meanPower; end
s.lastBaseline=base; s.lastBaselineInfo=baseInfo;
s.lastInfo=struct('time',s.sample.time_s,'baseline',base,'requestedResidual',delta,...
    'requestedReference',request,'appliedReference',s.reference,'oldReference',oldReference,...
    'meanPower',meanPower,'trueMeanPower',trueMean,'energyWh',sum(truePowers,'omitnan')*c.Ts/3600,...
    'powerCoverage',coverage,'blockedFraction',blocked/n,'reason',lastReason,'reward',reward,...
    'meanGroundSpeed',mean(speeds,'omitnan'),'meanAirSpeed',mean(airspeeds,'omitnan'),...
    'meanWindAlong',mean(windAlong,'omitnan'),'meanWindNormal',mean(windNormal,'omitnan'),...
    'radialRms',sqrt(mean(radial.^2)));
end
