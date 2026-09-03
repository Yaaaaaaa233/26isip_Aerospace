function q = euler_to_quaternion(a)
%X8PHYS.EULER_TO_QUATERNION 3-2-1 Euler angles to body-to-NED quaternion.
a = double(a(:));
assert(numel(a) == 3, 'x8phys:Attitude', 'Expected roll, pitch, yaw.');
hr=a(1)/2; hp=a(2)/2; hy=a(3)/2;
q=[cos(hr)*cos(hp)*cos(hy)+sin(hr)*sin(hp)*sin(hy); ...
   sin(hr)*cos(hp)*cos(hy)-cos(hr)*sin(hp)*sin(hy); ...
   cos(hr)*sin(hp)*cos(hy)+sin(hr)*cos(hp)*sin(hy); ...
   cos(hr)*cos(hp)*sin(hy)-sin(hr)*sin(hp)*cos(hy)];
q=q/norm(q);
end
