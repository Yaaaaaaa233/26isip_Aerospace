function m = mop_moe(log, c)
%MOP_MOE 环境风场模块评价（双层口径，对齐 docs/ARCHITECTURE_MOP_MOE.md）。
% ── MOE 任务效能 ──
%   MOE_energy = Emin/E_actual, Emin=ΣPmin(t)·tEval（解析可达最低功率积分,
%               时变风场下 Pmin(t) 逐点计算, 含速度边界裁剪损失）
%   MOE_instant= 尾段 mean(Pmin/P_true)（稳态瞬时能效）
% ── MOP 性能度量 ──
%   rmsVErr / maxVErr    调度相对解析 v*(t) 的偏差（时域）
%   energyExcessPercent  全程能量超额%（直接决定 MOE）
%   tailRegretPercent    尾段功率超额%
%   windEstErr           在线风估计末段误差 |ŵ−w|（在线模式）
% energyAccounting=false 时能耗类记NaN。
n=height(log);
tt=log.time;
sa=wind.analytic_sched(c,tt);
Eactual=sum(log.powerTrue)*c.tEval;
Emin=sum(sa.Pmin)*c.tEval;
m=struct();
m.EactualNorm=Eactual; m.EminNorm=Emin;
m.energyExcessPercent=100*(Eactual-Emin)/Emin;
m.MOE_energy=Emin/Eactual;
tail=max(1,n-c.tailSteps)+1:n;
m.regretPercent=100*mean((log.powerTrue(tail)-sa.Pmin(tail))./sa.Pmin(tail));
instEff=sa.Pmin(tail)./log.powerTrue(tail);
m.MOE_instant=mean(instEff(isfinite(instEff)));
verr=log.vCmd-sa.v;
m.rmsVErr=sqrt(mean(verr.^2)); m.maxVErr=max(abs(verr));
if any(~isnan(log.windEstX(tail)))
    werr=hypot(log.windEstX(tail)-log.windX(tail),log.windEstY(tail)-log.windY(tail));
    m.windEstErr=mean(werr,'omitnan');
else
    m.windEstErr=NaN;
end
m.MOE=struct('energy',m.MOE_energy,'instant',m.MOE_instant);
m.MOP=struct('rmsVErr',m.rmsVErr,'maxVErr',m.maxVErr,...
    'energyExcessPercent',m.energyExcessPercent,...
    'tailRegretPercent',m.regretPercent,'windEstErr',m.windEstErr);
if ~c.energyAccounting
    m.energyExcessPercent=NaN; m.MOE_energy=NaN; m.MOE_instant=NaN;
    m.MOE.energy=NaN; m.MOE.instant=NaN;
end
end
