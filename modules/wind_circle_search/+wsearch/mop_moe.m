function m = mop_moe(log, c)
%MOP_MOE 统一 MOP/MOE 评价（1小时任务窗口径, 支持时变平移场景）。
% ── MOE(效能) ──
%   MOE_energy = Emin / E_actual ∈ (0,1]
%   Emin    = Σ minPowerTrue·tEval   每时刻理论最低功率的积分(先验下界)
%   Eactual = Σ powerTrue·tEval      实际能耗(评价侧真值, 含搜索代价)
%   平移场景下 minPowerTrue(t)=J0min+dy(t) 随 dy 变化；上界当且仅当
%   全程精确跟踪 v*(t)=6+dx(t)。
% ── MOP(性能量) ──
%   tSearchEvals / finalErr / regretPercent / energyExcessPercent /
%   holdFraction / budgetUtilization
% energyAccounting=false 时能耗类指标记 NaN(只评价定位与稳态)。
n=height(log);
m=struct();
Eactual=sum(log.powerTrue)*c.tEval;
Emin=sum(log.minPowerTrue)*c.tEval;
m.EactualNorm=Eactual; m.EminNorm=Emin;
m.energyExcessPercent=100*(Eactual-Emin)/Emin;
m.MOE_energy=Emin/Eactual;
m.MOE_energy_W=m.MOE_energy;   % 瓦级口径同比值(powerScale 约掉)
m.finalErr=abs(log.estimate(end)-log.optimumTrue(end));
inband=abs(log.estimate-log.optimumTrue)<=c.eps & ~isnan(log.estimate);
k=find(inband,1);
if isempty(k), m.tSearchEvals=NaN; else, m.tSearchEvals=k; end
tail=max(1,n-c.tailSteps)+1:n;
m.regretPercent=100*mean((log.powerTrue(tail)-log.minPowerTrue(tail))./log.minPowerTrue(tail));
m.holdFraction=sum(strcmp(log.tag,'hold'))/n;
m.budgetUtilization=n/c.duration; %#ok<NASGU>
m.MOE_consistency=abs(m.MOE_energy-1/(1+m.energyExcessPercent/100))<1e-9;
if ~c.energyAccounting
    m.energyExcessPercent=NaN;
    m.MOE_energy=NaN;
    m.MOE_energy_W=NaN;
    m.MOE_consistency=NaN;
end
end
