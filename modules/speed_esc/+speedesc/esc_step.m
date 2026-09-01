function [reference,s,d] = esc_step(s,J,pairedSpeed,powerTime,now,valid,p)
%ESC_STEP Public online controller API: no plant configuration or optimum.
[s.estimator,e]=speedesc.estimate_step(s.estimator,J,pairedSpeed,powerTime,now,valid && ~s.frozen,p);
[reference,s.reference,r]=speedesc.reference_step(s.reference,e.gradient,e.ready,e.healthy,now,p);
d=e; d.center=r.center; d.dither=r.dither; d.limited=r.limited; d.frozen=r.frozen;
end
