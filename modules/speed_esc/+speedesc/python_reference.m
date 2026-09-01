function L = python_reference(version,curve,initial,noise)
%PYTHON_REFERENCE Literal compatibility port for tests, not recommended control.
% Keeps the Python Euler step, unpaired delay, startup FIFO, and reference clipping behavior.
dt=0.1; a=0.5; omega=0.5; win=63; n=numel(noise);
physical=strcmp(curve,'cubic'); optimum=6+0.3*physical;
gain=22; if physical, gain=8; end
center=initial; speed=initial; command=initial; time=0; gradient=0;
vb=[]; jb=[]; buffer=[]; matrix=zeros(n,6); alpha=(2-2*dt)/(2+2*dt);
for k=1:n
    if version==3 && k-1==200, optimum=9; end
    if version==1, speed=min(max(command,0),20);
    else, speed=min(max(speed+(min(max(command,0),20)-speed)/2*dt,0),20); end
    if physical
        b=2*(1-.913); x=speed/optimum; truth=1-1.5*b*x^2+b*x^3;
    else, truth=1+0.3*((speed-optimum)/10)^2; end
    measured=truth;
    if version==3
        noisy=truth*(1+.02*noise(k)); buffer=[buffer,noisy]; %#ok<AGROW>
        if numel(buffer)>5, measured=buffer(1); buffer(1)=[]; else, measured=noisy; end
    end
    matrix(k,:)=[command,speed,center,measured,optimum,truth];
    vb=[vb,speed]; jb=[jb,measured]; %#ok<AGROW>
    if numel(vb)>win, vb(1)=[]; jb(1)=[]; end
    vc=vb-mean(vb); jc=jb-mean(jb); den=sum(vc.*vc);
    raw=0;
    if (~physical || numel(vb)>=win) && den>1e-9, raw=sum(vc.*jc)/den; end
    gradient=alpha*gradient+(1-alpha)*raw;
    delta=-gain*gradient*dt;
    if physical, delta=min(max(delta,-.2),.2); end
    center=min(max(center+delta,0),20); time=time+dt;
    command=center+a*sin(omega*time);
end
L=array2table(matrix,'VariableNames',{'v_ref','v','v_hat','J','v_star','P_true'});
end
