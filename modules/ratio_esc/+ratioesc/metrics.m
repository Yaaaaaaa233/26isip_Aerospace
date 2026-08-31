function m = metrics(log,c)
tail=log.time>=max(0,c.duration-100);
excess=100*(log.truePower./log.offlinePower-1);
m=struct('finalExcessPercent',mean(excess(tail)),...
    'finalMeanPower',mean(log.truePower(tail)),...
    'finalMeanRatio',mean(log.ratio(tail)),...
    'ratioOscillation',max(log.ratio(tail))-min(log.ratio(tail)),...
    'boundViolations',sum(log.ratio<c.lower-1e-12 | log.ratio>c.upper+1e-12),...
    'rateLimitActivations',sum(log.rateLimited),...
    'convergenceTime',NaN,'reconvergenceTime',NaN);
window=max(1,round(50/c.Ts));
avg=movmean(excess,[window-1 0]);
ok=avg<=3;
start=1;
if strcmp(c.scenario,'shift')
    firstEnd=find(log.time<c.shiftTime,1,'last');
    if ~isempty(firstEnd), m.convergenceTime=settled(log.time(1:firstEnd),ok(1:firstEnd),window,0); end
    start=find(log.time>=c.shiftTime,1);
    if ~isempty(start)
        local=movmean(excess(start:end),[window-1 0]);
        m.reconvergenceTime=settled(log.time(start:end),local<=3,window,c.shiftTime);
    end
else
    m.convergenceTime=settled(log.time,ok,window,0);
end
end

function value=settled(time,ok,window,origin)
% Require a complete 50 s window and no subsequent threshold crossing.
lastBad=find(~ok,1,'last');
if isempty(lastBad), lastBad=0; end
idx=max(window,lastBad+1);
if idx<=numel(time), value=time(idx)-origin; else, value=NaN; end
end
