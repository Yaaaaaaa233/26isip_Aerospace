function s = plant_reset(c)
s.ratio=c.initialRatio;
initialPower=ratioesc.power_map(s.ratio,c.optimalRatio,c);
if strcmp(c.scenario,'shift') && c.shiftTime<=0
    initialPower=ratioesc.power_map(s.ratio,c.shiftedOptimalRatio,c);
end
s.delayBuffer=initialPower*ones(round(c.delay/c.Ts),1);
s.previousReference=c.initialRatio;
end
