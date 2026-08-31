function log = run(c,data)
%RUN Each iteration measures the current state before choosing the next input.
if nargin<2, data=ratioesc.make_inputs(c); end
if strcmp(c.stage,'rl'), log=ratioesc.run_rl(c,'random'); return; end
n=numel(data.time); p=ratioesc.controller_config(c); plant=ratioesc.plant_reset(c);
matrix=zeros(n,12); controller=[];
for k=1:n
    [power,measured,plant]=ratioesc.measure(plant,data.optimum(k),data.noise(k),c);
    if isempty(controller), controller=ratioesc.esc_reset(p,c.initialRatio,measured); end
    if any(strcmp(c.stage,{'esc','dither'}))
        [ref,controller,d]=ratioesc.esc_step(controller,measured,plant.ratio,true,p);
    else
        request=c.fixedReference;
        if strcmp(c.stage,'static'), request=c.initialRatio; end
        ref=ratioesc.limit_reference(request,plant.previousReference,p);
        d=struct('center',request,'dither',0,'highpass',0,'demodulated',0,...
            'gradient',0,'rateLimited',abs(ref-request)>1e-12,'frozen',false);
    end
    matrix(k,:)=[data.time(k),plant.ratio,ref,d.center,power,measured,...
        d.dither,d.highpass,d.demodulated,d.gradient,d.rateLimited,d.frozen];
    plant=ratioesc.plant_advance(plant,ref,c);
end
names={'time','ratio','reference','center','truePower','measuredPower',...
    'dither','highpass','demodulated','gradient','rateLimited','frozen'};
log=array2table(matrix,'VariableNames',names);
log.optimum=data.optimum; log.offlinePower=ones(n,1);
end
