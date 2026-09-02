function m = mop_moe(log, c)
%MOP_MOE 双层 MOP/MOE 评价体系(任务6完善版：性能量×任务效能分层)。
% ── MOP(性能度量, Measures of Performance)：系统自身行为质量,
%    回答"算法/控制器做得好不好", 与任务目标解耦 ──
%   MOP.finalErr      末误差 |v̂(T)−v*(T)|                [越小越好]
%   MOP.settleSteps   首次入带步数(定位速度)              [越小越好]
%   MOP.steadyFluct   尾段估计波动 std(v̂)(稳态抖动)       [越小越好]
%   MOP.searchSteps   非hold查询数(搜索代价)              [越小越好]
%   MOP.inBandRate    全程入带率 |v̂−v*|<=ε 的时间占比     [越大越好]
%   MOP.recoverySteps dx平移后重新入带步数(无dx平移记NaN)  [越小越好]
% ── MOE(效能度量, Measures of Effectiveness)：任务目标达成度,
%    回答"任务完成了多少"(续航任务=能量+可用性) ──
%   MOE.energy        Emin/E_actual ∈(0,1] 续航能效(先验下界口径)
%   MOE.instant       尾段瞬时能效 mean(Pmin(t)/Ptrue(t))  [越大越好]
%   MOE.availability  任务可用率(全程处于最优带内比例, 定位口径)
%   MOE.overall       综合效能 0.5·energy+0.3·instant+0.2·availability
% energyAccounting=false: 能耗类(energy/instant/overall/超额)记NaN,
% availability与全部MOP保留(只评价定位与稳态)。
% 顶层保留旧字段名(finalErr/MOE_energy/regretPercent/...)兼容既有测试与面板。
n=height(log);
m=struct();
tail=max(1,n-c.tailSteps)+1:n;
% ---- MOE: 能耗口径 ----
Eactual=sum(log.powerTrue)*c.tEval;
Emin=sum(log.minPowerTrue)*c.tEval;
m.EactualNorm=Eactual; m.EminNorm=Emin;
m.energyExcessPercent=100*(Eactual-Emin)/Emin;
m.MOE_energy=Emin/Eactual;
m.MOE_energy_W=m.MOE_energy;   % 瓦级口径同比值(powerScale 约掉)
m.MOE_consistency=abs(m.MOE_energy-1/(1+m.energyExcessPercent/100))<1e-9;
% ---- MOE: 稳态与可用性口径 ----
m.regretPercent=100*mean((log.powerTrue(tail)-log.minPowerTrue(tail))./log.minPowerTrue(tail));
instEff=log.minPowerTrue(tail)./log.powerTrue(tail);
m.MOE_instant=mean(instEff(isfinite(instEff)));
inband=abs(log.estimate-log.optimumTrue)<=c.eps & ~isnan(log.estimate);
m.MOE_availability=sum(inband)/max(sum(~isnan(log.estimate)),1);
% ---- MOP: 性能口径 ----
m.finalErr=abs(log.estimate(end)-log.optimumTrue(end));
k=find(inband,1);
if isempty(k), m.tSearchEvals=NaN; else, m.tSearchEvals=k; end
m.holdFraction=sum(strcmp(log.tag,'hold'))/n;
m.budgetUtilization=n/c.duration; %#ok<NASGU>
% 分层结构体
m.MOP=struct('finalErr',m.finalErr,'settleSteps',m.tSearchEvals,...
    'steadyFluct',std(log.estimate(tail),'omitnan'),...
    'searchSteps',sum(~strcmp(log.tag,'hold')),...
    'inBandRate',m.MOE_availability,...
    'recoverySteps',recoverySteps(log,c,inband));
m.MOE=struct('energy',m.MOE_energy,'instant',m.MOE_instant,...
    'availability',m.MOE_availability,...
    'overall',0.5*m.MOE_energy+0.3*m.MOE_instant+0.2*m.MOE_availability);
if ~c.energyAccounting
    m.energyExcessPercent=NaN;
    m.MOE_energy=NaN;
    m.MOE_energy_W=NaN;
    m.MOE_consistency=NaN;
    m.MOE_instant=NaN;
    m.MOE.overall=NaN;
    m.MOE.energy=NaN;
    m.MOE.instant=NaN;
end
end

function rec=recoverySteps(log,c,inband)
% dx型平移(jumpUp/jumpDown/ramp)后的重新入带步数; 静态(含风场振荡)/纯dy平移记NaN。
% 判据: 平移时刻前后各10步均值发生>0.5的水平阶跃(风场振荡在10步窗内均值
% 相消, 不会触发), 且平移时刻须在评价窗内。
tJ=round(c.shiftTime/c.tEval)+1;
if tJ+10>=height(log), rec=NaN; return; end
lo=max(1,tJ-10);
before=mean(log.optimumTrue(lo:tJ-1),'omitnan');
after=mean(log.optimumTrue(tJ:tJ+10),'omitnan');
if abs(after-before)<=0.5
    rec=NaN; return;
end
kk=find(inband(tJ:end),1);
if isempty(kk), rec=NaN; else, rec=kk-1; end
end
