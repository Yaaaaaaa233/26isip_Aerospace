function info = known_run(plant, p, n, scn)
%KNOWN_RUN 已知风oracle参照(评价侧上界, 因果策略不可用, 同任务6 'fixed'定位)。
% 假设风矢量真值与航向真值已知, 每步按解析调度直接解算 v*(t)。
% 作用: 量化"信息价值上界"——openloop与其差=信息价值, 各在线策略与其差
% =算法兑现能力的缺口。使用plant.truthPsi(评价侧内部状态), 不参与黑箱横比。
while plant.count()<n
    t=plant.count()*p.tEval;
    psi=plant.truthPsi();
    [~,~,Vx,Vy]=w8.wind_components(scn,t);
    q=Vx*cos(psi)+Vy*sin(psi);
    [dxS,~]=w8.shift_truth(scn,t);
    ust=p.optimum0+dxS;
    disc=q^2+ust^2-(Vx^2+Vy^2);
    if disc>0, v=-q+sqrt(disc); else, v=-q; end
    v=min(max(v,p.lower),p.upper);
    plant.q(v,'oracle'); plant.amendEstimate(v);
end
info=struct('best',NaN,'bestP',NaN,'mode','known');
end
