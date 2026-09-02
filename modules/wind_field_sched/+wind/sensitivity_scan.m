function out = sensitivity_scan(c, omegaList, windowList)
%SENSITIVITY_SCAN 任务4交付项：风估计滞后代价的敏感性扫描与带宽设计准则。
% 对正弦风(单方向)扫 ωw × 估计窗长 W：
%   - ωw 增大 → 风变化快 → 固定带宽估计器滞后增大 → 能量超额上升；
%   - W 减小(带宽升高) → 跟踪快但噪声大。
% 由此给出经验带宽准则：满足能量超额≤阈值 的最大可用窗长 W*(ωw)。
if nargin<1, c=wind.config(); end
if nargin<2, omegaList=[0.02 0.05 0.08 0.12 0.2 0.35 0.6]; end
if nargin<3, windowList=[20 30 45 60 90 130]; end
rows=cell(0,6);
for om=omegaList
    for W=windowList
        cc=wind.config(c,'windMode','sin','windOmega',om,...
            'estWindow',W,'duration',720,'tailSteps',120);
        [log,~]=wind.run_policy('online',cc);
        m=wind.mop_moe(log,cc);
        tail=(cc.duration-cc.tailSteps+1):cc.duration;
        werr=hypot(log.windEstX(tail)-log.windX(tail),...
            log.windEstY(tail)-log.windY(tail));
        rows(end+1,:)={om,W,m.energyExcessPercent,m.rmsVErr,...
            mean(werr,'omitnan'),m.MOE_energy}; %#ok<AGROW>
    end
end
T=cell2table(rows,'VariableNames',{'omega','window','excessPercent',...
    'rmsVErr','windEstErr','MOE'});
% 带宽准则: 每个ω下满足 超额<=1% 的最大窗长(=最低可用带宽)
crit=cell(0,4);
for om=omegaList
    ix=strcmp(T.omega,om);
    sub=T(ix,:);
    ok=sub.excessPercent<=1.0;
    if any(ok)
        Wmax=max(sub.window(ok));
    else
        Wmax=0;
    end
    [~,ib]=min(sub.excessPercent);
    crit(end+1,:)={om,Wmax,sub.window(ib),min(sub.excessPercent)}; %#ok<AGROW>
end
C=cell2table(crit,'VariableNames',{'omega','maxWindowAt1pct','bestWindow','bestExcess'});
out=struct('table',T,'criterion',C);
end
