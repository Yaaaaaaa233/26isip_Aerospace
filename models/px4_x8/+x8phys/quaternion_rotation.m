function R = quaternion_rotation(q)
%X8PHYS.QUATERNION_ROTATION Body-to-NED direction cosine matrix.
q=double(q(:));q=q/norm(q);w=q(1);x=q(2);y=q(3);z=q(4);
R=[1-2*(y*y+z*z) 2*(x*y-z*w) 2*(x*z+y*w); ...
   2*(x*y+z*w) 1-2*(x*x+z*z) 2*(y*z-x*w); ...
   2*(x*z-y*w) 2*(y*z+x*w) 1-2*(x*x+y*y)];
end
