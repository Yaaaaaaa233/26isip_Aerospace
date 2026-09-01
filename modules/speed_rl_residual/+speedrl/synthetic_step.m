function [s,x] = synthetic_step(s,vRef,dt)
%SYNTHETIC_STEP Simple 2-D wind/kinematics/power/sensor adapter.
c=s.config; validateattributes(vRef,{'double'},{'scalar','real','finite'});
validateattributes(dt,{'double'},{'scalar','real','finite','nonnegative'});
oldSpeed=s.speed;
if dt>0
    s.speed=vRef+(s.speed-vRef)*exp(-dt/s.tau);
    s.time=s.time+dt;
end
t=s.time;
if strcmp(c.trajectory,'circle')
    if dt>0, s.phase=mod(s.phase+s.speed*dt/c.pathRadius,2*pi); end
    tangent=[-sin(s.phase);cos(s.phase)];
else
    tangent=[1;0]; s.phase=0;
end
[trueWind,s]=wind_value(s,dt);
ground=tangent*s.speed; trueAir=norm(ground-trueWind);
acceleration=0; if dt>0, acceleration=(s.speed-oldSpeed)/dt; end
shaft=c.powerScale*s.powerFactor*(0.913+0.012*(trueAir-c.optimumAirSpeed)^2+0.01*acceleration^2);
openVoltage=21+4.2*s.soc;
disc=openVoltage^2-4*s.resistance*shaft;
assert(disc>0,'speedrl:Battery','Synthetic load exceeds battery model feasibility.');
current=2*shaft/(openVoltage+sqrt(disc)); voltage=openVoltage-s.resistance*current;
truePower=voltage*current;
if dt>0, s.soc=max(0,s.soc-current*dt/(3600*c.capacityAh)); end

powerItem=[truePower*(1+c.powerNoiseFraction*randn(s.stream)),t,voltage,s.soc];
powerDelay=round(c.powerDelay/c.Ts);
if isempty(s.powerQueue), s.powerQueue=repmat(powerItem,powerDelay,1); end
s.powerQueue=[s.powerQueue;powerItem]; delayedPower=s.powerQueue(1,:); s.powerQueue(1,:)=[];
dropPower=c.powerDropouts && mod(t,50)>=35 && mod(t,50)<38;
if isempty(s.lastPower) || ~dropPower, s.lastPower=delayedPower; end
p=s.lastPower; powerValid=~isempty(p) && t-p(2)<=c.maxPowerAge+1e-9 && p(1)>0;

windItem=[trueWind+c.windNoiseStd*randn(s.stream,2,1);t]';
windDelay=round(c.windDelay/c.Ts);
if isempty(s.windQueue), s.windQueue=repmat(windItem,windDelay,1); end
s.windQueue=[s.windQueue;windItem]; delayedWind=s.windQueue(1,:); s.windQueue(1,:)=[];
dropWind=strcmp(c.windObservation,'hidden') || ...
    (strcmp(c.windObservation,'dropout') && (mod(t,40)>=25 && mod(t,40)<32));
if isempty(s.lastWind) || ~dropWind, s.lastWind=delayedWind; end
w=s.lastWind; windValid=~strcmp(c.windObservation,'hidden') && ~isempty(w) && ...
    t-w(3)<=c.maxWindAge+1e-9;
observedWind=[NaN;NaN]; windTime=NaN;
if windValid, observedWind=w(1:2)'; windTime=w(3); end

x=struct('time_s',t,'ground_velocity_ne_mps',ground,...
    'wind_velocity_ne_mps',observedWind,'wind_sample_time_s',windTime,...
    'power_w',p(1),'power_sample_time_s',p(2),'voltage_v',p(3),'soc',p(4),...
    'path_phase_rad',s.phase,'path_tangent_ne',tangent,'radial_error_m',s.radialError,...
    'velocity_valid',true,'wind_valid',logical(windValid),'power_valid',logical(powerValid));
x.evaluator=struct('true_power_w',truePower,'true_wind_ne_mps',trueWind,...
    'true_air_speed_mps',trueAir,'chemical_power_w',openVoltage*current,'wind_mode',s.windMode);
s.lastTruth=x.evaluator;
end

function [wind,s]=wind_value(s,dt)
c=s.config; t=s.time;
switch s.windMode
    case 'none'
        wind=zeros(2,1);
    case 'constant'
        wind=s.baseWind;
    case 'step'
        if t<0.45*c.duration, wind=s.baseWind; else, wind=[-0.8*s.baseWind(1);-s.baseWind(2)+0.5]; end
    case 'sine'
        period=max(40,c.duration); q=2*pi*t/period+s.windPhase;
        wind=[2*sin(q);1.5*cos(q)];
    case 'irregular'
        if dt>0
            a=exp(-dt/c.ouTimeConstant);
            s.ouWind=a*s.ouWind+c.ouStd*sqrt(1-a^2)*randn(s.stream,2,1);
            s.gust=s.gust*exp(-dt/2);
            if rand(s.stream)<c.gustProbability
                angle=2*pi*rand(s.stream); s.gust=s.gust+c.gustMagnitude*[cos(angle);sin(angle)];
            end
        end
        wind=s.ouWind+s.gust;
    otherwise
        error('speedrl:Wind','Unknown wind mode.');
end
end
