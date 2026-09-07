function [dth,c0] = interf_corr(psSet,rrSet,PmSet,coefs,th0,p)
%INTERF_CORR 世界模型的干扰场误差在线修正(4参数: δa0+δa1+δb1+功率偏置c0)。
% 原理(wind_corr 的桨比域移植): 若调度用的 δ̂ 有误差, 补偿后 u=r−δ̂(ψ) 不再对准
% 模型谷底, 功率出现系统性偏移/航向调制——在最近窗口上最小化
%   min_{δθ,c0} Σ (P_i − f̂(r_i − (θ0+δθ)·[1,cosψ,sinψ]') − c0)² + λ‖[δa1,δb1]‖²
% c0 吸收 f̂ 的多项式形状偏差(与 δθ 解耦), 岭正则防窄带样本拖拽谐波分量。
% f̂/θ0 为控制器自己的模型(标定段学得), 非对象真值(红线1)。
ps=psSet(:); rr=rrSet(:); Pm=PmSet(:);
dth=[0;0;0]; c0=0;
for it=1:6
    [fHat]=modelP(dth,c0,ps,rr,coefs,th0);
    e=Pm-fHat;
    dW=0.006; dC=0.005;
    [~,f1]=modelP(dth+[dW;0;0],c0,ps,rr,coefs,th0);
    [~,f2b]=modelP(dth+[0;dW;0],c0,ps,rr,coefs,th0);
    [~,f3]=modelP(dth+[0;0;dW],c0,ps,rr,coefs,th0);
    [~,f4]=modelP(dth,c0+dC,ps,rr,coefs,th0);
    J=[(f1-fHat)/dW, (f2b-fHat)/dW, (f3-fHat)/dW, (f4-fHat)/dC];
    Rg=diag([1e-4*numel(ps), 1e-3*numel(ps), 1e-3*numel(ps), 1e-9]);
    dth4=(J.'*J+Rg)\(J.'*e);
    dth=dth+dth4(1:3); c0=c0+dth4(4);
    if max(abs(dth4))<1e-5, break; end
end
    function [Pv,fv]=modelP(dq,c0q,psq,rrq,cf,thq)
        th2=thq+dq;
        u=min(max(rrq-(th2(1)+th2(2)*cos(psq)+th2(3)*sin(psq)),p.lower+0.005),p.upper-0.005);
        x=(u-1.0)/0.25;
        Pv=cf(1)+cf(2)*x+cf(3)*x.^2+cf(4)*x.^3+cf(5)*x.^4;
        fv=Pv+c0q;
    end
end
