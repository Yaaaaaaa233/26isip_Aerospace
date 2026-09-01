function info = esc_run(plant, p, n)
%ESC_RUN 连续极值寻优基线(镜像任务1 esc_run)：正弦扰动+半周期窗口回归。
% 在多峰对象上预期落入起始点附近的局部谷——作为"局部方法+多峰=陷阱"的
% 诚实对照，不设通过门槛。
W=p.escWindow; alpha=(2-p.escLpOmega*p.tEval)/(2+p.escLpOmega*p.tEval);
vhat=p.initialSpeed; bufV=zeros(1,0); bufJ=zeros(1,0); lp=0;
for k=1:n
    vcmd=vhat+p.escA*sin(p.escOmega*k*p.tEval);
    J=plant.q(vcmd,'esc'); plant.amendEstimate(vhat);
    bufV(end+1)=vcmd; bufJ(end+1)=J; %#ok<AGROW>
    if numel(bufV)>W, bufV(1)=[]; bufJ(1)=[]; end
    g=0;
    if numel(bufV)==W
        vc=bufV-mean(bufV); jc=bufJ-mean(bufJ); den=dot(vc,vc);
        if den>1e-9, g=dot(jc,vc)/den; end
    end
    lp=alpha*lp+(1-alpha)*g;
    vhat=min(max(vhat-p.escGain*lp*p.tEval,p.lower+p.escA),p.upper-p.escA);
end
info=struct('best',vhat,'bestP',NaN,'candidates',p.initialSpeed,'scanSteps',0,...
    'refineSteps',0,'filteredArgmin',NaN,'filterMethod','none','filterW',0);
end
