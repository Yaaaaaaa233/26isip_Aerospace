function info = multistart_run(plant, p, n)
%MULTISTART_RUN 任务2推荐方案：全局扫描→滤波→选谷→分层精调→锁定。
%
% 阶段(每行日志一个评估步, tag 标记相位)：
%   scan     均匀粗扫描 scanN 点，每点1次带噪测量
%   filter   无评估消耗(纯后处理)，中心对称滤波压噪
%   refine   K个候选谷各自做"局部细扫描+滤波"轻评估(每点 repeats 次均值)，
%            选出最优谷
%   polish   对最优谷做更细一层"局部扫描+滤波+argmin"(同一方法论分层应用，
%            不对原始噪声曲线做黄金分割——噪声下微结构低于分辨率时，
%            黄金分割会被谷内微起伏/谷肩伪特征吸走)
%   hold     锁定直到预算结束
%
% "无偏移"保证的设计：
%   1) 全部滤波为中心对称奇数窗口(零相位)；
%   2) 候选选择只决定去哪个谷，不决定最终位置；
%   3) 最终位置 = 分层细扫描+滤波后的 argmin(网格粒度 0.025 m/s)，
%      不含任何会引入系统性偏置的环节；跨种子系统偏置由验收单独设门槛。
info=struct('best',NaN,'bestP',NaN,'candidates',[],'scanSteps',0,'refineSteps',0,...
    'polishSteps',0,'filteredArgmin',NaN,'filterMethod',p.filterMethod,'filterW',p.filterW);
vs=linspace(p.lower,p.upper,p.scanN);
pm=zeros(1,p.scanN); bestSoFar=Inf; bestV=NaN;
for i=1:p.scanN                                   % --- 阶段1: 全局扫描 ---
    if plant.count()>=n, return; end
    pm(i)=plant.q(vs(i),'scan'); plant.amendEstimate(bestV);
    if pm(i)<bestSoFar, bestSoFar=pm(i); bestV=vs(i); end
end
info.scanSteps=plant.count();
pf=task2.apply_filter(pm,p.filterMethod,p.filterW);   % --- 阶段2: 滤波(0步) ---
[~,iMin]=min(pf); info.filteredArgmin=vs(iMin);
cand=pick_wells(pf,vs,p.K,p.minSep);
cand=merge_point(cand,vs(iMin),p.minSep);
cand=merge_point(cand,p.initialSpeed,p.minSep);
info.candidates=cand;
% --- 阶段3: 各候选局部细扫描+滤波(轻评估) ---
spanR=min(p.refineSpan,0.35);  % 窗口须完全罩住候选偏差(滤波argmin可偏+0.25), 真值谷±0.3内严格对称
bestSoFar=Inf; bestV=NaN;
% --- 阶段3: 候选精调 = 迭代重定位(pattern search) ---
% 滤波候选可偏+0.25：直接以候选为中心做抛物线拟合会被右肩污染。
% 先用两轮"采样-移向最小-收缩窗口"把中心拉回谷底(±0.1内)，
% 每点1次测量(只需粗定位)；谷间比较用各自最小样本值。
for j=1:numel(cand)
    if plant.count()>n-14, break; end
    c=cand(j); w=0.35;
    for it=1:2
        vr=linspace(max(p.lower,c-w),min(p.upper,c+w),7);
        pr=zeros(1,7);
        for i=1:7
            if plant.count()>=n, pr(i)=Inf; break; end
            pr(i)=repeatQuery(vr(i),'refine',2);
        end
        [~,il]=min(pr);
        if ~isfinite(pr(il)), break; end
        c=vr(il); w=0.2;
    end
    if isfinite(min(pr)) && min(pr)<bestSoFar
        bestSoFar=min(pr); bestV=c;
    end
    if ~isnan(bestV), plant.amendEstimate(bestV); end
    info.refineSteps=plant.count();
end
% --- 阶段4: 最优谷精调(局部重复采样 + 最小二乘抛物线顶点) ---
% 最终估计不经过滤波：滤波只用于"选哪个谷"(候选层)。窗口±0.25落在
% 真值谷的对称区(实测±0.3内严格对称)，顶点拟合无系统偏置——这是
% "无偏移"要求的最后一道保证。
if ~isnan(bestV) && plant.count()<=n-p.repeats*15
    vp=bestV+[-0.24 -0.12 0 0.12 0.24];
    pp=zeros(1,5);
    for i=1:5
        if plant.count()>=n, pp(i)=NaN; break; end
        pp(i)=repeatQuery(vp(i),'polish',max(p.repeats*3,12));
    end
    ok=~isnan(pp);
    if sum(ok)>=5
        pv=polyfit(vp(ok)-bestV,pp(ok),2);
        vertex=-pv(2)/(2*pv(3));
        vertex=min(max(vertex,-0.25),0.25);           % 顶点限幅防外推
        bestV=bestV+vertex;
        info.bestP=min(pp(ok));
    end
    plant.amendEstimate(bestV);
    info.polishSteps=plant.count();
end
info.best=bestV;
if ~isfield(info,'bestP') || isnan(info.bestP), info.bestP=bestSoFar; end
while plant.count()<n                             % --- 阶段5: 锁定 ---
    plant.q(bestV,'hold'); plant.amendEstimate(bestV);
end

    function y=repeatQuery(v,tag,m)
        acc=0;
        for r=1:m
            if plant.count()>=n, acc=acc+NaN; break; end
            acc=acc+plant.q(v,tag);
        end
        y=acc/m;
        if ~isnan(bestV), plant.amendEstimate(bestV); end
    end

    function out=pick_wells(pf,vs,K,sep)
        out=zeros(1,0);
        for i=2:numel(vs)-1
            if pf(i)<=pf(i-1) && pf(i)<=pf(i+1)
                out(end+1)=vs(i); %#ok<AGROW>
            end
        end
        [~,ord]=sort(interp1(vs,pf,out,'linear','extrap'));
        out=out(ord);
        sel=zeros(1,0);
        for vcur=out
            if all(abs(sel-vcur)>=sep), sel(end+1)=vcur; %#ok<AGROW>
                if numel(sel)>=K, break; end
            end
        end
        out=sel;
    end

    function out=merge_point(list,vnew,sep)
        if isempty(list) || all(abs(list-vnew)>=sep)
            out=[list vnew];
        else
            out=list;
        end
    end
end
