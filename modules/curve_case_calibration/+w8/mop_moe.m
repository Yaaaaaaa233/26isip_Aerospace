function m = mop_moe(log, c)
%MOP_MOE 双层MOP/MOE评价体系(任务7版: 任务6分层结构 + 实际约束动力学MOP)。
% ── MOP(性能度量) ──
%   finalErr / settleSteps / steadyFluct / searchSteps / inBandRate /
%   recoverySteps         与任务6同口径(estimate列语义不变);
%   meanTrackLag          平均指令跟踪滞后 mean|v_act−v_cmd|(时延+限幅代价) [m/s]
%   maxAccelUsed          全程最大|dv/dt|, 应<=aMax(物理性核验)      [m/s^2]
%   settleQueryRatio      非常驻查询的就位步占搜索步比例(任务7新增开销)
% ── MOE(效能度量) ──
%   energy / instant / availability / overall   与任务6同口径;
%   (与开环基线的对比提升见 w8.compare_baseline, 不在本函数重复跑基线)。
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
% ---- MOP: 实际约束动力学口径(任务7新增) ----
m.meanTrackLag=mean(abs(log.speed-log.speedCmd),'omitnan');
m.maxAccelUsed=max(log.accelMax);
m.meanAccelUsed=mean(log.accelMax);
tagStr=string(log.tag);
nSettle=sum(strcmp(tagStr,'settle'));
nSearch=sum(~strcmp(tagStr,'hold'));
m.settleQueryRatio=nSettle/max(nSearch,1);
% 分层结构体
m.MOP=struct('finalErr',m.finalErr,'settleSteps',m.tSearchEvals,...
    'steadyFluct',std(log.estimate(tail),'omitnan'),...
    'searchSteps',nSearch,...
    'inBandRate',m.MOE_availability,...
    'recoverySteps',recoverySteps(log,c,inband),...
    'meanTrackLag',m.meanTrackLag,'maxAccelUsed',m.maxAccelUsed,...
    'settleQueryRatio',m.settleQueryRatio);
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
% 任务7改进: 用日志的shiftDx列(纯平移分量, 无风振荡混叠)做阶跃检测——
% 实际半径下风致最优振荡快, 任务6用optimumTrue前后均值差的启发式会漏检。
tJ=round(c.shiftTime/c.tEval)+1;
if tJ+10>=height(log), rec=NaN; return; end
lo=max(1,tJ-10);
before=mean(log.shiftDx(lo:tJ-1),'omitnan');
after=mean(log.shiftDx(tJ:tJ+10),'omitnan');
if abs(after-before)<=0.5
    rec=NaN; return;
end
kk=find(inband(tJ:end),1);
if isempty(kk), rec=NaN; else, rec=kk-1; end
end
