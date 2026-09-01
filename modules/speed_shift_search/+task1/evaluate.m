function m = evaluate(log, scn, c)
%EVALUATE 一幕运行的评价指标。能耗列受 energyAccounting 开关控制：
% 开=计入寻优过程本身的能量代价(续航纪录口径)；关=记NaN、不参与验收。
% 所有功率类指标用评价侧真值(powerTrue/minPowerTrue)计算，不用带噪测量值。
n=height(log);
m=struct();
m.finalErr=abs(log.estimate(n)-log.optimumTrue(n));
inband=abs(log.estimate-log.optimumTrue)<=c.eps;
k=find(inband,1);
if isempty(k), m.evalsToEps=NaN; else, m.evalsToEps=k; end
tail=n-c.tailSteps+1:n;
m.steadyRegretPercent=100*mean((log.powerTrue(tail)-log.minPowerTrue(tail))./log.minPowerTrue(tail));
if c.energyAccounting
    m.energyExcessPercent=100*sum(log.powerTrue-log.minPowerTrue)/sum(log.minPowerTrue);
else
    m.energyExcessPercent=NaN;
end
m.searchSteps=sum(strcmp(log.tag,'search'));
m.probeSteps=sum(strcmp(log.tag,'probe'));
m.holdSteps=sum(strcmp(log.tag,'hold'));
% 跳变恢复步数：事件时刻后首次入带，相对事件步的延迟；ramp不定义
m.recoverySteps=NaN;
events=scn.jumps(:,1);
if ~isempty(events)
    for e=events(:)'
        ke=find(log.time>=e,1);
        if ~isempty(ke)
            k2=find(inband(ke:end),1);
            if ~isempty(k2)
                r=k2-1;
                if isnan(m.recoverySteps)||r>m.recoverySteps, m.recoverySteps=r; end
            else
                m.recoverySteps=Inf;
            end
        end
    end
end
end
