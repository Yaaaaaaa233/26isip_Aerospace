function info = tracker_run(plant, p, n)
%TRACKER_RUN 任务1推荐方案(算法逻辑原样移植任务6, 全部查询经指令就位包装器)：
% Brent混合搜索 + 锁定 + 平移监测重夹逼。
% 任务7差异: 非常驻查询与锁定保持都走 w7.settled_q(指令就位后再测量/其实
% hold就位过程本身就是锁定平飞), 状态机/阈值与任务6一致——横比反映约束
% 影响而非算法改动。
info=struct('lockV',NaN,'researchCount',0,'probePairs',0,'researchTimes',[],...
    'brackets',zeros(0,2),'bracketSegs',zeros(0,2));
drift=false;
qs=w7.settled_q(plant,p,n);
f=w7.search_query(plant,qs);
s0=w7.brent_search(f,p.lower,p.upper,p.tol,min(p.maxSearchEval,n-1));
appendBrackets(s0);
if isfinite(s0.fx), lockV=s0.x; else, lockV=p.initialSpeed; end
info.lockV=lockV;
hold=0;
while plant.count()<n
    if hold<p.t1ProbePeriod
        qs(lockV,'hold');
        hold=hold+1;
        continue;
    end
    if plant.count()>n-2
        qs(lockV,'hold');
        continue;
    end
    hold=0;
    pm=qs(lockV-p.t1ProbeDelta,'probe');
    if ~isfinite(pm), continue; end
    pp=qs(lockV+p.t1ProbeDelta,'probe');
    if ~isfinite(pp), continue; end
    info.probePairs=info.probePairs+1;
    g=(pp-pm)/(2*p.t1ProbeDelta);
    trigger=false;
    if ~drift && abs(g)>=p.t1SlopeThresh
        drift=true; trigger=true;          % 进入漂移模式
    elseif drift
        if abs(g)>=p.t1SlopeRelease
            trigger=true;                  % 漂移未结束，继续精调
        else
            drift=false;                   % 残余斜率低于释放阈值，退出漂移
        end
    end
    if ~trigger || plant.count()>n-4
        continue;
    end
    span=p.t1Span0; sr=[];
    for attempt=1:p.t1Retry+1
        if plant.count()>=n, break; end
        a=max(p.lower,lockV-span); b=min(p.upper,lockV+span);
        f=w7.search_query(plant,qs);
        sr=w7.brent_search(f,a,b,p.tol,min(p.maxSearchEval,n-plant.count()));
        appendBrackets(sr);
        edge=0.05*(b-a);
        if ~isfinite(sr.fx) || (abs(sr.x-a)>edge && abs(sr.x-b)>edge), break; end
        span=span*p.t1Grow;
    end
    if ~isempty(sr) && isfinite(sr.fx) && plant.count()<=n
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
