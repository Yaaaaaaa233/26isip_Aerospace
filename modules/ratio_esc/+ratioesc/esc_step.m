function [reference,s,d] = esc_step(s,measuredPower,actualRatio,valid,p)
%ESC_STEP Causal washout / demodulation / descent controller.
phase=sin(2*pi*p.frequency*(s.sample*p.Ts));
d=struct('center',s.center,'dither',p.amplitude*phase,'highpass',0,...
    'demodulated',0,'gradient',s.gradient,'frozen',false,'rateLimited',false);
sampleOK=isscalar(valid) && logical(valid) && isscalar(measuredPower) && ...
    isfinite(measuredPower) && isscalar(actualRatio) && isfinite(actualRatio) && ...
    actualRatio>=p.lower && actualRatio<=p.upper;
if s.frozen || ~sampleOK
    reference=s.lastReference; s.reinitialize=true; s.sample=s.sample+1;
    d.frozen=true; d.dither=0;
    return
end
if s.reinitialize
    s.bias=measuredPower; s.gradient=0;
    s.warmup=ceil(1/(p.frequency*p.Ts)); s.reinitialize=false;
end
highpass=measuredPower-s.bias;
s.bias=s.bias+(1-exp(-p.hpOmega*p.Ts))*highpass;
demodulated=(2/p.amplitude)*highpass*phase;
s.gradient=s.gradient+(1-exp(-p.lpOmega*p.Ts))*(demodulated-s.gradient);
if p.adapt && s.warmup==0
    s.center=s.center-p.gain*p.Ts*s.gradient;
end
s.center=min(max(s.center,p.lower+p.amplitude),p.upper-p.amplitude);
request=s.center+p.amplitude*phase;
reference=ratioesc.limit_reference(request,s.lastReference,p);
d.center=s.center; d.highpass=highpass; d.demodulated=demodulated;
d.gradient=s.gradient; d.rateLimited=abs(reference-request)>1e-12;
s.lastReference=reference; s.sample=s.sample+1; s.warmup=max(0,s.warmup-1);
end
