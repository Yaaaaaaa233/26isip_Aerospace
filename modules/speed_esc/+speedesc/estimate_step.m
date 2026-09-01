function [s,d] = estimate_step(s,J,speed,sampleTime,now,valid,p)
%ESTIMATE_STEP Power and speed must refer to the SAME acquisition time.
d=struct('highpass',0,'rawGradient',0,'gradient',s.gradient,...
    'ready',false,'healthy',false,'fresh',false,'speedStd',0);
healthy=valid && isfinite(J) && isfinite(speed) && isfinite(sampleTime) && ...
    isfinite(now) && sampleTime<=now+1e-9 && now-sampleTime<=p.maxAge+1e-9 && ...
    speed>=p.lower && speed<=p.upper && sampleTime>=s.lastSample-1e-9;
if ~healthy
    s=speedesc.estimator_reset(p); d.gradient=0; return
end
d.healthy=true;
if sampleTime<=s.lastSample+1e-9, return; end
d.fresh=true;
dt=p.Ts; if s.initialized, dt=sampleTime-s.lastSample; end
if ~s.initialized, s.bias=J; s.initialized=true; end
d.highpass=J-s.bias;
s.bias=s.bias+(1-exp(-p.hpOmega*dt))*d.highpass;
s.lastSample=sampleTime;
s.power=[s.power(2:end),J]; s.speed=[s.speed(2:end),speed];
s.count=min(p.window,s.count+1);
if s.count<p.window, return; end
vc=s.speed-mean(s.speed); jc=s.power-mean(s.power);
den=sum(vc.*vc); d.speedStd=sqrt(den/p.window);
if den<p.window*p.minimumSpeedStd^2
    s.gradient=0; d.gradient=0; return
end
if p.method==1
    raw=sum(vc.*jc)/den;
else
    raw=(2/p.amplitude)*d.highpass*sin(p.omega*sampleTime);
end
d.rawGradient=raw;
bounded=min(max(raw,-p.gradientLimit),p.gradientLimit);
s.gradient=s.gradient+(1-exp(-p.lpOmega*dt))*(bounded-s.gradient);
d.gradient=s.gradient; d.ready=true;
end
