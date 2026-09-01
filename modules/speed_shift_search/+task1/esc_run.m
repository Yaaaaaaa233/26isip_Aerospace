function info = esc_run(plant, p, n)
%ESC_RUN 连续极值寻优基线：正弦扰动 + 半周期窗口回归(镜像 esc_core.py V1)。
% 与直接搜索的差别：扰动永不停(稳态持续付出约 0.5*P''*a^2 的功率超额)，
% 但对慢漂移有天然的连续跟踪能力。参数取 tEval=1s 尺度下的等效默认。
W=p.escWindow; alpha=(2-p.escLpOmega*p.tEval)/(2+p.escLpOmega*p.tEval);
vhat=p.escInitial; bufV=zeros(1,0); bufJ=zeros(1,0); lp=0;
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
info=struct('center',vhat,'researchCount',NaN,'brackets',zeros(0,2),'bracketSegs',[0 0]);
end
