function est = est_step(est, v, psi, Pm)
%EST_STEP 在线风估计一步：滑动窗口 Levenberg-Marquardt 参数更新。
% 每步把新测量(v,ψ,Pm)压入窗口，然后在窗口上做2轮LM迭代
% 最小化 Σ(P0(|v·t̂+ŵ|)−Pm)²，热启动自上一步 ŵ。
% 观测性注记：在 |u|≈V* 处 P0'≈0（功率对空速不敏感），近最优巡航时
% 风估计本质病态——观测性激励(obsDither)由 run_policy 提供。
est.V(end+1)=v; est.psi(end+1)=psi; est.Pm(end+1)=Pm; %#ok<AGROW>
keep=est.window;
if numel(est.V)>keep
    est.V(1:end-keep)=[]; est.psi(1:end-keep)=[]; est.Pm(1:end-keep)=[];
end
est.filled=numel(est.V);
if est.filled>=16
    th=est.theta;
    vv=est.V; ps=est.psi; pm=est.Pm;
    tx=vv.*cos(ps)+th(1); ty=vv.*sin(ps)+th(2);
    u2=tx.^2+ty.^2; u=sqrt(max(u2,1e-9));
    for it=1:2
        x=u/est.Vstar;
        dPdu=3*est.b*(x.^2-x)/est.Vstar;      % P0'(|u|)
        r=wind.power_curve(u,struct('Pstar',est.Pstar,'Vstar',est.Vstar))-pm;
        J1=dPdu.*tx./u; J2=dPdu.*ty./u;       % ∂P/∂w = P0'·u⃗/|u|
        H=[dot(J1,J1)+est.lm, dot(J1,J2); dot(J1,J2), dot(J2,J2)+est.lm];
        g=[dot(J1,r); dot(J2,r)];
        dth=-H\g;
        th=th+min(max(dth,-1.5),1.5);          % 步长限幅(稳健)
        tx=vv.*cos(ps)+th(1); ty=vv.*sin(ps)+th(2);
        u=sqrt(max(tx.^2+ty.^2,1e-9));
    end
    est.theta=th;
end
end
