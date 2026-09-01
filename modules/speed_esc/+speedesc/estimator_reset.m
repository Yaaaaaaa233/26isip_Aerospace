function s = estimator_reset(p)
%ESTIMATOR_RESET Fixed-size state also used by generated Simulink blocks.
s=struct('power',zeros(1,p.window),'speed',zeros(1,p.window),'count',0,...
    'bias',0,'gradient',0,'lastSample',-Inf,'initialized',false);
end
