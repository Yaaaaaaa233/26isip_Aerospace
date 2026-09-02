function info = tracker_run(plant, p, n)
%TRACKER_RUN 任务1推荐方案：Brent混合搜索 + 锁定 + 平移监测重夹逼。
%
% 状态机(每行日志一个评估步, tag 标记相位):
%   search  初始搜索(整个定义域)或平移后的重夹逼搜索(围绕旧最优点展开)
%   hold    锁定在当前最优点持续平飞
%   probe   每隔 probePeriod 个 hold 步做一次两点复探 v±probeDelta
%
% 平移判别(核心设计，迟滞双阈值)：
%   斜率 g=(P(v+d)-P(v-d))/(2d) 越过 slopeThresh => 判定左右平移(dx)：
%     以旧最优点为种子、span 从 bracketSpan0 起按 bracketGrow 扩张重搜；
%     若新最优贴近夹逼区间边缘则扩张重试(真最优可能更远)，至多 bracketRetry 次。
%     同时进入"漂移模式"。慢漂结束后的残余滞后可能恰好停在 slopeThresh 之下
%     (锯齿相位问题)，因此漂移模式内改用更低的释放阈值 slopeRelease：
%     只要 |g| 仍不低于它就继续重搜，直到 |g| 跌破它才退出漂移模式——
%     保证慢漂收尾后被精调到释放阈值对应的更小滞后(三次约0.04、调试约0.08 m/s)。
%   斜率正常 => 上下平移(dy)或无平移：argmin 都未变，继续锁定即可——
%     判据只需要斜率，不需要参考功率，因此上下平移天然不误触发重搜。
%   检测下限约 slopeThresh/P''(三次曲线约0.15 m/s、调试曲线约0.33 m/s)；
%   更小的纯dx平移稳态超额不足0.01%，不追是合理工程取舍。
%
% 预算边界：探针需2步、重搜至少留1步；预算不足时保持锁定走完，
% 不会越过评估上限。
info=struct('lockV',NaN,'researchCount',0,'probePairs',0,'researchTimes',[],...
    'brackets',zeros(0,2),'bracketSegs',zeros(0,2));
drift=false;
f=wsearch.search_query(plant);
s0=wsearch.brent_search(f,p.lower,p.upper,p.tol,min(p.maxSearchEval,n-1));
appendBrackets(s0);
lockV=s0.x; info.lockV=lockV;
hold=0;
while plant.count()<n
    if hold<p.t1ProbePeriod
        plant.q(lockV,'hold'); plant.amendEstimate(lockV);
        hold=hold+1;
        continue;
    end
    if plant.count()>n-2
        % 预算不够一对探针：继续锁定平飞
        plant.q(lockV,'hold'); plant.amendEstimate(lockV);
        continue;
    end
    hold=0;
    pm=plant.q(lockV-p.t1ProbeDelta,'probe'); plant.amendEstimate(lockV);
    pp=plant.q(lockV+p.t1ProbeDelta,'probe'); plant.amendEstimate(lockV);
    info.probePairs=info.probePairs+1;
    g=(pp-pm)/(2*p.t1ProbeDelta);
    trigger=false;
    if ~drift && abs(g)>=p.t1SlopeThresh
        drift=true; trigger=true;          % 进入漂移模式
    elseif drift
        if abs(g)>=p.t1SlopeRelease
            trigger=true;                  % 漂移未结束，继续精调
        else
            drift=false;                   % 残余斜率已低于释放阈值，退出漂移
        end
    end
    if ~trigger || plant.count()>n-4
        continue;   % 上下平移/无平移不动作；预算不足以重搜时如实保持锁定
    end
    span=p.t1Span0; sr=[];
    for attempt=1:p.t1Retry+1
        if plant.count()>=n, break; end
        a=max(p.lower,lockV-span); b=min(p.upper,lockV+span);
        f=wsearch.search_query(plant);
        sr=wsearch.brent_search(f,a,b,p.tol,min(p.maxSearchEval,n-plant.count()));
        appendBrackets(sr);
        edge=0.05*(b-a);
        if abs(sr.x-a)>edge && abs(sr.x-b)>edge, break; end
        span=span*p.t1Grow;
    end
    if ~isempty(sr) && plant.count()<=n
        info.researchCount=info.researchCount+1;
        info.researchTimes(end+1)=plant.count(); %#ok<AGROW>
        lockV=sr.x; info.lockV=lockV;
    end
end

    function appendBrackets(sr)   % 供动画展示逐评估夹逼区间(可多段)
        info.brackets=vertcat(info.brackets,sr.brackets); %#ok<AGROW>
        info.bracketSegs(end+1,:)=[size(info.brackets,1)-size(sr.brackets,1)+1,...
            size(sr.brackets,1)]; %#ok<AGROW>
    end
end
