function Rbn = rotation321(attitude_rad)
%X8PHYS.ROTATION321 Body-to-NED 3-2-1 Euler rotation.
% Input order is [roll; pitch; yaw] in radians, matching quaternion helpers.
a = double(attitude_rad(:));
assert(numel(a) == 3 && all(isfinite(a)), ...
    'x8phys:Attitude', 'Expected finite [roll; pitch; yaw].');
phi = a(1); theta = a(2); psi = a(3);
cp = cos(phi); sp = sin(phi);
ct = cos(theta); st = sin(theta);
cy = cos(psi); sy = sin(psi);
Rbn = [cy*ct, cy*st*sp-sy*cp, cy*st*cp+sy*sp; ...
       sy*ct, sy*st*sp+cy*cp, sy*st*cp-cy*sp; ...
       -st,   ct*sp,           ct*cp];
end
