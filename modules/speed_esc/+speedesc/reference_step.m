function [reference,s,d] = reference_step(s,gradient,ready,healthy,now,p)
%REFERENCE_STEP Distinct center-rate, command bounds, and reference slew.
d=struct('center',s.center,'dither',0,'limited',false,'frozen',false);
if ~healthy
    reference=s.last; d.frozen=true; return
end
if p.controlMode==2 && ready
    change=min(max(-p.gain*gradient,-p.centerRate),p.centerRate)*p.Ts;
    s.center=min(max(s.center+change,p.lower+p.amplitude),p.upper-p.amplitude);
end
if p.controlMode==0
    requested=p.fixedReference;
else
    d.dither=p.amplitude*sin(p.omega*now); requested=s.center+d.dither;
end
bounded=min(max(requested,p.lower),p.upper);
reference=s.last+min(max(bounded-s.last,-p.referenceRate*p.Ts),p.referenceRate*p.Ts);
s.last=reference; d.center=s.center;
d.limited=abs(reference-requested)>1e-12;
end
