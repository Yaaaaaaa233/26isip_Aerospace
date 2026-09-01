function log = run(c,data)
if nargin<2, data=speedesc.make_inputs(c); end
n=round(c.duration/c.Ts);
assert(all([numel(data.time),numel(data.optimum),numel(data.noise),numel(data.valid),numel(data.freeze)]==n),...
    'speedesc:Data','Input vectors must match duration/Ts.');
assert(all(abs(data.time(:)-(0:n-1)'*c.Ts)<1e-9),'speedesc:Data','Input clock must match Ts.');
p=speedesc.controller_config(c); controller=speedesc.esc_reset(c.initialSpeed,p);
plant=speedesc.plant_reset(c); reference=c.initialSpeed; matrix=zeros(n,18);
for k=1:n
    applied=reference;
    [sample,plant]=speedesc.plant_step(plant,applied,data.time(k),data.optimum(k),data.noise(k),c);
    controller=speedesc.freeze(controller,logical(data.freeze(k)));
    [reference,controller,d]=speedesc.esc_step(controller,sample.measuredPower,sample.pairedSpeed,...
        sample.powerTime,data.time(k),logical(data.valid(k)),p);
    optimumPower=speedesc.power_map(data.optimum(k),data.optimum(k),c);
    matrix(k,:)=[data.time(k),sample.actualSpeed,applied,reference,d.center,sample.truePower,...
        sample.measuredPower,sample.pairedSpeed,sample.powerTime,d.highpass,d.rawGradient,d.gradient,...
        d.dither,d.ready,d.limited,d.frozen,data.optimum(k),optimumPower];
end
log=array2table(matrix,'VariableNames',speedesc.log_names());
end
