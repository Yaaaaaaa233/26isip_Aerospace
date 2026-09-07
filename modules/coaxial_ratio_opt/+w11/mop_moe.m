function m = mop_moe(log, c)
%MOP_MOE 双层MOP/MOE评价体系(与速度包同口径, 变量为桨比)。
% ── MOE(效能) ── energy/energyExcessPercent/MOE_energy = Emin/Eactual
%   (2026-09-04用户口径: 仅续航能耗); instant/availability为辅助诊断。
% ── MOP(性能) ── finalErr/settleSteps/steadyFluct/searchSteps/inBandRate/
%   meanTrackLag(平均|rAct−rCmd|)/slewMaxUsed(应<=slewMax, 物理性核验)。
n=height(log);
m=struct();
tail=max(1,n-c.tailSteps)+1:n;
% ---- MOE: 能耗口径 ----
Eactual=sum(log.powerTrue)*c.tEval;
Emin=sum(log.minPowerTrue)*c.tEval;
m.EactualNorm=Eactual; m.EminNorm=Emin;
m.energyExcessPercent=100*(Eactual-Emin)/Emin;
m.MOE_energy=Emin/Eactual;
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
m.meanTrackLag=mean(abs(log.ratio-log.ratioCmd),'omitnan');
m.slewMaxUsed=max(log.slewUsed);
tagStr=string(log.tag);
nSettle=sum(strcmp(tagStr,'settle'));
nSearch=sum(~strcmp(tagStr,'hold'));
m.settleQueryRatio=nSettle/max(nSearch,1);
m.MOP=struct('finalErr',m.finalErr,'settleSteps',m.tSearchEvals,...
    'steadyFluct',std(log.estimate(tail),'omitnan'),...
    'searchSteps',nSearch,'inBandRate',m.MOE_availability,...
    'meanTrackLag',m.meanTrackLag,'slewMaxUsed',m.slewMaxUsed,...
    'settleQueryRatio',m.settleQueryRatio);
m.MOE=struct('energy',m.MOE_energy,'instant',m.MOE_instant,...
    'availability',m.MOE_availability,'overall',m.MOE_energy);
if ~c.energyAccounting
    m.energyExcessPercent=NaN; m.MOE_energy=NaN; m.MOE_consistency=NaN;
    m.MOE_instant=NaN; m.MOE.overall=NaN; m.MOE.energy=NaN; m.MOE.instant=NaN;
end
end
