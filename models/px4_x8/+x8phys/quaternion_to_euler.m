function a = quaternion_to_euler(q)
%X8PHYS.QUATERNION_TO_EULER Body-to-NED quaternion to 3-2-1 Euler angles.
q=double(q(:)); q=q/norm(q); w=q(1);x=q(2);y=q(3);z=q(4);
roll=atan2(2*(w*x+y*z),1-2*(x*x+y*y));
pitch=asin(max(-1,min(1,2*(w*y-z*x))));
yaw=atan2(2*(w*z+x*y),1-2*(y*y+z*z));
a=[roll;pitch;yaw];
end
