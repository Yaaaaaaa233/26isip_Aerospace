function m = evaluate(log, info, c)
%EVALUATE 一幕运行的评价指标(全局命中口径)。能耗列受 energyAccounting 开关控制。
% vG 由评价侧数值计算并记录在日志列 globalOptimum 中。
% eps 默认0.35=命中全局谷口径(噪声下位置分辨率极限, 见README);
% 跨种子系统偏置|mean err|<=0.05 由验收层另行设门槛。
n=height(log);
m=struct();
vG=log.globalOptimum(n);
m.globalOptimum=vG;
m.finalErr=abs(log.estimate(n)-vG);
m.hitsGlobal=m.finalErr<=c.eps;
inband=abs(log.estimate-vG)<=c.eps & ~isnan(log.estimate);
k=find(inband,1);
if isempty(k), m.evalsToEps=NaN; else, m.evalsToEps=k; end
tail=n-c.tailSteps+1:n;
m.steadyRegretPercent=100*mean((log.powerTrue(tail)-log.minPowerTrue(tail))./log.minPowerTrue(tail));
if c.energyAccounting
    m.energyExcessPercent=100*sum(log.powerTrue-log.minPowerTrue)/sum(log.minPowerTrue);
else
    m.energyExcessPercent=NaN;
end
m.scanSteps=sum(strcmp(log.tag,'scan'));
m.refineSteps=sum(strcmp(log.tag,'refine'));
m.holdSteps=sum(strcmp(log.tag,'hold'));
m.filterMethod=info.filterMethod; m.filterW=info.filterW;
m.filteredArgmin=info.filteredArgmin;
end
