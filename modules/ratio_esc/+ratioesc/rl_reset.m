function [observation,s] = rl_reset(c)
%RL_RESET LoggedSignals is internal environment state, not an observation.
s=struct('config',c,'data',ratioesc.make_inputs(c),'plant',ratioesc.plant_reset(c),...
    'index',1,'previousMean',0,'lastSegment',table());
initial=ratioesc.power_map(c.initialRatio,s.data.optimum(1),c)+s.data.noise(1);
s.previousMean=initial;
z=(c.initialRatio-c.lower)/(c.upper-c.lower);
observation=[z;z;initial;0];
end
