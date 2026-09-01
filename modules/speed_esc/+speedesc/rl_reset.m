function [observation,s] = rl_reset(c)
data=speedesc.make_inputs(c); p=speedesc.controller_config(c);
initialJ=speedesc.power_map(c.initialSpeed,c.optimum,c)*(1+c.noiseSigma*data.noise(1));
s=struct('config',c,'data',data,'plant',speedesc.plant_reset(c),...
    'referenceState',speedesc.reference_reset(c.initialSpeed,p),...
    'reference',c.initialSpeed,'index',1,'previousMean',initialJ,'history',[]);
[observation,s.history]=speedesc.rl_observe(c.initialSpeed,c.initialSpeed,initialJ,0,0,1,[],c);
s.lastSegment=zeros(0,4);
end
