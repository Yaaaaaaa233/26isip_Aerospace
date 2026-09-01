function agent = make_agent(env,c)
%MAKE_AGENT Compact TD3 agent; action remains physical delta-v.
init=rlAgentInitializationOptions('NumHiddenUnit',128);
opt=rlTD3AgentOptions('SampleTime',c.decisionPeriod,'MiniBatchSize',128,...
    'ExperienceBufferLength',200000,'DiscountFactor',0.995);
span=diff(c.deltaBounds);
opt.ExplorationModel.StandardDeviation=0.12*span;
opt.ExplorationModel.StandardDeviationMin=0.01*span;
opt.TargetPolicySmoothModel.StandardDeviation=0.03*span;
opt.TargetPolicySmoothModel.StandardDeviationMin=0.005*span;
agent=rlTD3Agent(getObservationInfo(env),getActionInfo(env),init,opt);
end
