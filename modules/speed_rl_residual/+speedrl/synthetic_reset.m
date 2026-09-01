function [s,sample] = synthetic_reset(seed,c)
%SYNTHETIC_RESET Private synthetic state. No optimum enters observations.
stream=RandStream('mt19937ar','Seed',seed);
mode=c.windMode;
if strcmp(mode,'mixed')
    choices={'constant','step','sine','irregular'}; mode=choices{1+mod(seed,numel(choices))};
end
tau=c.tauSpeed; factor=1; resistance=c.internalResistance;
baseWind=c.constantWind; windPhase=0;
if c.training
    tau=tau*(0.75+0.5*rand(stream)); factor=0.9+0.2*rand(stream);
    resistance=resistance*(0.75+0.5*rand(stream));
end
if c.randomizeWind
    magnitude=0.5+3*rand(stream); angle=2*pi*rand(stream);
    baseWind=magnitude*[cos(angle);sin(angle)]; windPhase=2*pi*rand(stream);
end
s=struct('config',c,'stream',stream,'windMode',mode,'time',0,'speed',c.initialSpeed,...
    'reference',c.initialSpeed,'phase',0,'radialError',0,'soc',c.initialSoc,...
    'tau',tau,'powerFactor',factor,'resistance',resistance,'baseWind',baseWind,...
    'windPhase',windPhase,'ouWind',zeros(2,1),...
    'gust',zeros(2,1),'powerQueue',zeros(0,4),'windQueue',zeros(0,3),...
    'lastPower',[],'lastWind',[],'lastTruth',struct());
[s,sample]=speedrl.synthetic_step(s,c.initialSpeed,0);
end
