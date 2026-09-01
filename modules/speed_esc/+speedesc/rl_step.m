function [observation,reward,done,s] = rl_step(action,s)
%RL_STEP Alternative speed-reference generator with the SAME plant/limits.
validateattributes(action,{'double'},{'scalar','real','finite'});
c=s.config; p=speedesc.controller_config(c); p.controlMode=0;
p.fixedReference=min(max(action,c.lower),c.upper);
n=numel(s.data.time); assert(s.index<=n,'speedesc:EpisodeDone','Reset the completed episode.');
count=min(round(c.rlPeriod/c.Ts),n-s.index+1); values=zeros(count,4); measured=nan(count,1);
before=s.reference; blocked=0;
for j=1:count
    k=s.index; t=s.data.time(k); applied=s.reference;
    [sample,s.plant]=speedesc.plant_step(s.plant,applied,t,s.data.optimum(k),s.data.noise(k),c);
    valid=logical(s.data.valid(k)) && ~logical(s.data.freeze(k)) && isfinite(sample.measuredPower);
    [s.reference,s.referenceState,d]=speedesc.reference_step(s.referenceState,0,false,valid,t,p);
    if valid, measured(j)=sample.measuredPower; end
    blocked=blocked+double(d.frozen);
    values(j,:)=[t,sample.actualSpeed,applied,sample.truePower]; s.index=s.index+1;
end
good=isfinite(measured); coverage=mean(good); average=NaN;
if any(good), average=mean(measured(good)); end
[observation,s.history]=speedesc.rl_observe(sample.actualSpeed,s.reference,average,average-s.previousMean,...
    t-sample.powerTime,coverage,s.history,c);
cost=0; if isfinite(average), cost=average; s.previousMean=average; end
reward=-cost-10*(1-coverage)-10*blocked/count-.005*((s.reference-before)/(c.upper-c.lower))^2;
done=s.index>n; s.lastSegment=values;
end
