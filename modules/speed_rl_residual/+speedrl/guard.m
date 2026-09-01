function [reference,info] = guard(request,previous,sample,dt,c)
%GUARD Slow reference gate. This is not a flight-qualified failsafe.
reason='ok'; reference=previous;
if ~isfinite(request)
    reason='invalid_action';
elseif ~sample.velocity_valid || ~sample.power_valid
    reason='invalid_or_stale_feedback';
else
    bounded=min(max(request,c.speedBounds(1)),c.speedBounds(2));
    change=min(max(bounded-previous,-c.speedRate*dt),c.speedRate*dt);
    reference=previous+change;
    if abs(sample.radial_error_m)>c.radialFreeze, reason='trajectory_freeze'; end
end
info=struct('reason',reason,'blocked',~strcmp(reason,'ok'),...
    'bounded',reference>=c.speedBounds(1)-1e-12 && reference<=c.speedBounds(2)+1e-12);
end
