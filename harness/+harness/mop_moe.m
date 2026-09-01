function m = mop_moe(log, aircraft, c)
%MOP_MOE 统一评价体系：MOE(任务效能) + MOP(算法性能量)。
%
% ── 场景口径 ─────────────────────────────────────────────
% 任务窗 T(默认1小时=3600s)，评价器持有先验理论最低功率 Pmin(离线最优，
% 归一化 Pmin_norm 与瓦级 Pmin_W 两套)。任务目标=最小化窗口内总能耗 E。
%
% ── MOE(效能, 指挥员视角: "任务完成得怎么样") ────────────
%   MOE_energy = Emin / E_actual ∈ (0,1]
%     Emin = Pmin * T   先验理论最低能耗(理想: 一直停在全局最优)
%     E_actual = Σ P_true·tEval   窗口内实际能耗(评价侧真值, 含搜索代价)
%     越接近1越好; =1 当且仅当全程精确停在Pmin(不可达上界, 扰动/搜索必有代价)
%   MOE_energy_W = (Pmin_W*T) / E_actual_W   同比值, 瓦级口径(实机接入口径)
%
% ── MOP(性能量, 工程师视角: "算法按规格表现如何") ────────
%   mop.tSearchEvals      达到定位容差所用评估步数(收敛速度)
%   mop.finalErr          末段估计-全局最优偏差(m/s, 定位精度)
%   mop.regretPercent     稳态功率超额% =100*(P_tail-Pmin)/Pmin(稳态品质)
%   mop.energyExcessPercent 全程能量超额% =100*(E_actual-Emin)/Emin(能耗品质)
%   mop.holdFraction      锁定占空比=hold步数/总步数(稳态经济性结构)
%   mop.probeSteps        搜索+探查步数(扫描/精调合计, 评估预算占用)
%   mop.budgetUtilization 评估预算利用率=有效评估数/预算
%
% 关系(自上而下分解): MOE_energy ≈ 1/(1+energyExcessPercent/100)；
% MOP.energyExcessPercent 直接决定 MOE；MOP.tSearchEvals/finalErr 通过
% 搜索段能耗与末段精度间接影响 MOE——这正是"MOE分解为MOP"的标准结构。
%
% 全部MOP/MOE用评价侧真值计算；带噪测量列只留作诊断。
n=height(log);
E_actual_norm=sum(log.powerTrue)*c.tEval;          % 归一化功率·秒
Emin_norm=aircraft.Pmin*c.T;
m=struct();
m.MOE_energy=Emin_norm/E_actual_norm;
m.MOE_energy_W=(aircraft.Pmin*c.powerScaleW*c.T)/(E_actual_norm*c.powerScaleW);
m.EminNorm=Emin_norm; m.EactualNorm=E_actual_norm;
m.PminNorm=aircraft.Pmin; m.PminW=aircraft.Pmin*c.powerScaleW;
m.EminW=Emin_norm*c.powerScaleW; m.EactualW=E_actual_norm*c.powerScaleW;
% ---- MOP ----
inband=abs(log.estimate-log.globalOptimum)<=0.35 & ~isnan(log.estimate);
k=find(inband,1);
if isempty(k), m.tSearchEvals=NaN; else, m.tSearchEvals=k; end
tail=max(1,n-round(60/c.tEval))+1:n;
m.finalErr=abs(log.estimate(end)-log.globalOptimum(end));
m.regretPercent=100*mean((log.powerTrue(tail)-log.minPowerTrue(tail))./log.minPowerTrue(tail));
m.energyExcessPercent=100*(E_actual_norm-Emin_norm)/Emin_norm;
m.holdFraction=sum(strcmp(log.tag,'hold'))/n;
m.probeSteps=n-sum(strcmp(log.tag,'hold'));
m.budgetUtilization=n/(c.T/c.tEval);
m.MOE_consistency=abs(m.MOE_energy-1/(1+m.energyExcessPercent/100))<1e-9;
end
