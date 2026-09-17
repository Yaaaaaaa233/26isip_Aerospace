function [dw,c0] = wind_corr(psSet,vvSet,PmSet,coefs,w0,p)
%WIND_CORR 世界模型的风误差在线修正(3参数: δw + 功率偏置c0)。
% 原理: 若调度用的ŵ有误差(含标定段虚假风), 补偿后空速u=|v·t̂−ŵ|不再恒定,
% 功率出现每圈一次的调制——在最近窗口上最小化
%     min_{δw,c0} Σ (P_i − f̂(|v_i·t̂_i − (w0+δw)|) − c0)²  + λ‖δw‖²
% c0吸收f̂的多项式形状偏差(与δw解耦), 岭正则防窄带样本拖拽δw。
% f̂为控制器自己的模型(标定段学得), 非对象真值(红线1)。
ps=psSet(:); vv=vvSet(:); Pm=PmSet(:);
cx=vv.*cos(ps); cy=vv.*sin(ps);
th=[0;0;0];                       % [dwx; dwy; c0]
for it=1:6
    [fHat]=modelP(th,cx,cy,coefs,w0);
    e=Pm-fHat;
    dW=0.06; dC=0.005;
    [~,f1]=modelP(th+[dW;0;0],cx,cy,coefs,w0);
    [~,f2]=modelP(th+[0;dW;0],cx,cy,coefs,w0);
    [~,f3]=modelP(th+[0;0;dC],cx,cy,coefs,w0);
    J=[(f1-fHat)/dW, (f2-fHat)/dW, (f3-fHat)/dC];
    Rg=diag([1e-3*numel(ps), 1e-3*numel(ps), 1e-9]);
    dth=(J.'*J+Rg)\(J.'*e);
    th=th+dth;
    if max(abs(dth))<1e-4, break; end
end
dw=th(1:2);
c0=th(3);
    function [Pv,fv]=modelP(thq,cxq,cyq,cf,wq)
        wq2=wq+thq(1:2);
        u=min(max(hypot(cxq-wq2(1),cyq-wq2(2)),0.5),19.5);
        x=(u-7.5)/4.5;
        Pv=cf(1)+cf(2)*x+cf(3)*x.^2+cf(4)*x.^3+cf(5)*x.^4;
        fv=Pv+thq(3);
    end
end
