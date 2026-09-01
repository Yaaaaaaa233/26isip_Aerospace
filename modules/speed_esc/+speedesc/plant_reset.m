function s = plant_reset(c)
s=struct('speed',c.initialSpeed,'delayBuffer',zeros(round(c.delay/c.Ts),3),'initialized',false);
end
