function [sample,s] = plant_step(s,reference,time,optimum,noise,c)
%PLANT_STEP Plant advances before measurement; reference is from last tick.
reference=min(max(reference,c.lower),c.upper);
if c.version==1, s.speed=reference;
else, s.speed=reference+(s.speed-reference)*exp(-c.Ts/c.tau); end
truth=speedesc.power_map(s.speed,optimum,c);
row=[truth*(1+c.noiseSigma*noise),s.speed,time];
if ~s.initialized
    s.delayBuffer=repmat(row,round(c.delay/c.Ts),1); s.initialized=true;
end
queue=[s.delayBuffer;row]; delayed=queue(1,:); s.delayBuffer=queue(2:end,:);
sample=struct('actualSpeed',s.speed,'truePower',truth,'measuredPower',delayed(1),...
    'pairedSpeed',delayed(2),'powerTime',delayed(3));
end
