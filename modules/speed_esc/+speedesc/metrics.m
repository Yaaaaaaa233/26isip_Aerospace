function m = metrics(L,c)
tail=L.time>=c.duration-c.tailSeconds;
excess=100*(L.truePower./L.optimalPower-1);
m=struct('meanSpeed',mean(L.actualSpeed(tail)),'centerError',abs(mean(L.center(tail)-L.trueOptimum(tail))),...
    'speedError',abs(mean(L.actualSpeed(tail)-L.trueOptimum(tail))),...
    'regretPercent',mean(excess(tail)),'speedStd',std(L.actualSpeed(tail),1),...
    'meanTruePower',mean(L.truePower(tail)),'normalizedEnergySeconds',sum(L.truePower)*c.Ts,...
    'boundViolations',sum(L.nextReference<c.lower-1e-10 | L.nextReference>c.upper+1e-10),...
    'rateViolations',sum(abs(L.nextReference-L.appliedReference)>c.referenceRate*c.Ts+1e-10),...
    'frozenSamples',sum(L.frozen),'convergenceSeconds',NaN,'reconvergenceSeconds',NaN);
if c.shift
    before=L(L.time<c.shiftTime,:); after=L(L.time>=c.shiftTime,:);
    m.convergenceSeconds=settle(before,c.optimum,0.5,c);
    detected=settle(after,c.shiftedOptimum,0.7,c);
    if isfinite(detected), m.reconvergenceSeconds=detected-c.shiftTime; end
else
    m.convergenceSeconds=settle(L,c.optimum,0.5,c);
end
end

function t=settle(L,target,tol,c)
t=NaN; w=round(c.settlingWindow/c.Ts); hold=round(c.settlingHold/c.Ts);
if height(L)<w+hold, return; end
average=movmean(L.actualSpeed,[w-1 0]); count=0;
for k=w:height(L)
    if abs(average(k)-target)<=tol, count=count+1; else, count=0; end
    if count>=hold, t=L.time(k); return; end
end
end
