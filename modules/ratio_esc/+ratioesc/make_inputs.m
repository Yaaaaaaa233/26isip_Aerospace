function data = make_inputs(c)
%MAKE_INPUTS Private plant/evaluator inputs, never passed to the controller.
ratioesc.validate_config(c);
n=round(c.duration/c.Ts);
data.time=(0:n-1)'*c.Ts;
data.optimum=c.optimalRatio*ones(n,1);
if strcmp(c.scenario,'shift')
    data.optimum(data.time>=c.shiftTime)=c.shiftedOptimalRatio;
end
stream=RandStream('mt19937ar','Seed',c.seed);
data.noise=c.noiseSigma*randn(stream,n,1);
end
