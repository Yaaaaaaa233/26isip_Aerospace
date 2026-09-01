function data = make_inputs(c)
data.time=(0:round(c.duration/c.Ts)-1)'*c.Ts;
data.optimum=repmat(c.optimum,size(data.time));
if c.shift, data.optimum(data.time>=c.shiftTime)=c.shiftedOptimum; end
stream=RandStream('mt19937ar','Seed',c.seed);
data.noise=randn(stream,numel(data.time),1);
data.valid=ones(size(data.time));
data.freeze=zeros(size(data.time));
end
