function qnext = quaternion_advance(q, bodyRate, dt)
%X8PHYS.QUATERNION_ADVANCE First-order quaternion integration, normalized.
q=q(:);w=bodyRate(:);Omega=[0 -w';w -skew(w)];
qnext=q+0.5*Omega*q*dt;qnext=qnext/norm(qnext);
end

function S=skew(v)
S=[0 -v(3) v(2);v(3) 0 -v(1);-v(2) v(1) 0];
end
