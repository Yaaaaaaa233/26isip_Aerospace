function info = esc_run(plant, p, n)
%ESC_RUN 连续极值寻优基线(算法逻辑原样移植任务6, 查询经指令就位包装器)：
% 正弦扰动 + 半周期窗口回归。
% 任务7差异: 每个ESC控制周期的扰动指令经 w9.settled_q 就位后再测量;
% 扰动相位按ESC迭代计数(一个控制周期可能占多个对象步)。
W=p.escWindow; alpha=(2-p.escLpOmega*p.tEval)/(2+p.escLpOmega*p.tEval);
vhat=p.initialSpeed; bufV=zeros(1,0); bufJ=zeros(1,0); lp=0;
qs=w9.settled_q(plant,p,n);
kIter=0;
while plant.count()<n
    kIter=kIter+1;
    vcmd=vhat+p.escA*sin(p.escOmega*kIter*p.tEval);
    J=qs(vcmd,'esc');
    if ~isfinite(J), break; end            % 预算耗尽, 转入末段
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
while plant.count()<n
    plant.q(vhat,'hold'); plant.amendEstimate(vhat);
end
info=struct('best',vhat,'bestP',NaN,'candidates',p.initialSpeed,'scanSteps',0,...
    'refineSteps',0,'filteredArgmin',NaN,'filterMethod','none','filterW',0,...
    'iterations',kIter);
end
