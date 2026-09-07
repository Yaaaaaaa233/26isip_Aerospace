function info = known_run(plant, p, n, scn)
%KNOWN_RUN 已知干扰场oracle参照(评价侧上界, 因果策略不可用, 同速度包'known'定位)。
% 假设γ场真值与航向真值已知: 每步取 γ_eff(t,ψ) → 漂移映射 → r*(t)=rStar0+Δr(γ)。
% 作用: 量化"信息价值上界"——openloop 与其差=干扰带来的损失, 各在线策略与其差
% =算法兑现能力的缺口。使用 plant.truthPsi(评价侧内部状态), 不参与黑箱横比。
while plant.count()<n
    t=plant.count()*p.tEval;
    psi=plant.truthPsi();
    [~,gEff]=w11.interfer_field(scn,t,psi);
    [dGam,~]=w11.shift_truth(scn,t);
    dx=w11.drift_of(gEff+dGam,p);
    r=min(max(p.rStar0+dx,p.lower),p.upper);
    plant.q(r,'oracle'); plant.amendEstimate(r);
end
info=struct('best',NaN,'bestP',NaN,'mode','known');
end
