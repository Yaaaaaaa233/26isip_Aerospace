function [observation,reward,isDone,s] = rl_step(action,s)
%RL_STEP Action is a ratio reference held for one decision interval.
validateattributes(action,{'double'},{'scalar','real','finite'});
c=s.config; n=numel(s.data.time);
assert(s.index<=n,'ratioesc:EpisodeDone','Reset after the episode ends.');
request=min(max(action,c.lower),c.upper);
count=min(round(c.rlPeriod/c.Ts),n-s.index+1);
matrix=zeros(count,12); truth=zeros(count,1);
for j=1:count
    k=s.index;
    [power,measured,s.plant]=ratioesc.measure(s.plant,s.data.optimum(k),s.data.noise(k),c);
    ref=ratioesc.limit_reference(request,s.plant.previousReference,c);
    matrix(j,:)=[s.data.time(k),s.plant.ratio,ref,request,power,measured,...
        0,0,0,0,abs(ref-request)>1e-12,0];
    truth(j)=s.data.optimum(k);
    s.plant=ratioesc.plant_advance(s.plant,ref,c); s.index=s.index+1;
end
names={'time','ratio','reference','center','truePower','measuredPower',...
    'dither','highpass','demodulated','gradient','rateLimited','frozen'};
s.lastSegment=array2table(matrix,'VariableNames',names);
s.lastSegment.optimum=truth; s.lastSegment.offlinePower=ones(count,1);
meanPower=mean(matrix(:,6));
observation=[(s.plant.ratio-c.lower)/(c.upper-c.lower);...
    (s.plant.previousReference-c.lower)/(c.upper-c.lower);meanPower;meanPower-s.previousMean];
reward=-meanPower; s.previousMean=meanPower;
isDone=s.index>n;
end
