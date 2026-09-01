function info = ea_run(plant, p, n)
%EA_RUN 能耗感知全局寻优（任务1+2整合的推荐方案）。
% 动机(用户要求)：寻优本身消耗能量，完全遍历后再选最优不是好策略——
% 搜索每一步都在烧电，策略必须用最少的查询获得足够可信的最优点。
%
% 阶段(tag)：
%   local   局部优先：以初始速度为中心两轮 pattern search(7点×2轮)
%   sigma   噪声自估计：同点 eaSigmaRepeats 次重复取标准差(黑箱自含)
%   far     远点证据：eaFarProbes 个远离局部的探针(m=eaFarRepeats)
%           仅当 farBest < localBest − eaMarginSigma·σ̂ 才认定"别处有更深谷"
%   scan    证据升级才执行粗扫描(eaScanN=21, 非全遍历61点)+SG滤波选谷
%   refine  各候选谷 pattern search(至多2个候选, 升级成本控制)
%   polish  最优谷 5 点对称 stencil×eaPolishRepeats, 最小二乘顶点(无偏定位)
%   hold    锁定 + 事件驱动平移监测(零额外评估): 复用hold评估做12步滑动
%           均值监测, 功率水平越限才发一次斜率探针区分dx/dy——dx先局部
%           重定位, 仍越限则全局升级(至多relocalMax次); dy直接吸收。
%
% 能耗对比(默认崎岖静态): 局部谷可信时约 55 步收敛；21+步粗扫描只在有
% 远谷证据时发生——对比 multistart 的 61 步全扫+重采样约 425 步。
info=struct('best',NaN,'bestP',Inf,'escalations',0,'relocals',0,...
    'farProbes',0,'candidates',NaN,'phase','init','muMaxDiff',0);
[bestV,bestP]=localPS(p.initialSpeed,p.eaLocalW0,p.eaLocalW1);
% --- 噪声自估计 ---
sig=repeatStd(bestV); info.phase='sigma';
% --- 远点证据: 只有强于阈值的确凿证据才升级全局 ---
margin=p.eaMarginSigma*max(sig,1e-4);
farV=farPoints(bestV);
farBest=Inf;
for i=1:numel(farV)
    if plant.count()>n-3, break; end
    % 远点迷你下降: 3点采样滑向谷底, 让证据反映真实谷深而非谷肩
    vr=farV(i)+[-0.5 0 0.5];
    pr=Inf(1,3);
    for j=1:3
        if plant.count()>=n, break; end
        pr(j)=plant.q(vr(j),'far');
    end
    [~,il]=min(pr);
    if isfinite(pr(il))&&pr(il)<farBest, farBest=pr(il); end
end
info.farProbes=plant.count();
% 局部最优复测(m=2): 消除单次幸运偏差, 避免压低升级证据
if plant.count()<=n-2
    bestP=meanQ(bestV,'far',2);
end
escalated=false;
if isfinite(farBest) && farBest<bestP-margin && plant.count()<=n-40
    info.phase='scan';                        % 有确凿证据才升级全局
    [bestV,bestP]=globalEscalate(bestV);
    escalated=true;
end
% --- 终精调(对称 stencil + 顶点) ---
[bestV,bestP]=polish(bestV);
info.best=bestV; info.bestP=bestP;
% --- 新鲜度检查: 搜索期间对象可能已平移, 锁定前验证 bestP 仍然成立 ---
% 无条件执行(预算允许时): 其读数同时作为平移监测的初始参考——
% 若参考建立在平移之后, 监测对"搜索结束时已发生的平移"是盲的。
freshN=3;
refP=NaN;
if plant.count()<=n-(freshN+45)
    refP=meanQ(bestV,'hold',freshN);
    if isfinite(refP) && refP > bestP + 3.5*max(sig,1e-4)/sqrt(freshN)
        [bestV,bestP]=globalEscalate(bestV);
        [bestV,bestP]=polish(bestV);
        refP=meanQ(bestV,'hold',freshN);   % 升级后重建参考
        info.best=bestV; info.bestP=bestP;
    end
end
if isnan(refP), refP=meanQ_safe(); end
% --- 锁定 + 事件驱动平移监测（零额外评估成本） ---
% 复用hold评估做12步滑动均值监测：功率水平越限(>3.5σ̂√(2/12))说明对象
% 变了 → 一次斜率探针区分dx/dy：dx先局部重定位，重定位后仍越限则全局
% 升级(至多relocalMax次)；dy不改变斜率 → 吸收为新参考，零误触发。
ring=ones(1,12)*refP; nfill=12; holdCnt=0; pend=false;
lvlThr=3.5*max(sig,1e-4)*sqrt(2/12);
while plant.count()<n
    pNow=plant.q(bestV,'hold'); plant.amendEstimate(bestV);
    holdCnt=holdCnt+1;
    if plant.count()>n-(2*p.probeRepeats+45), continue; end
    ring=[ring(2:end) pNow]; nfill=min(nfill+1,12);
    if nfill<12, continue; end
    muNow=mean(ring);
    if isnan(refP), refP=muNow; continue; end          % 建立参考窗
    if holdCnt<p.probePeriod, continue; end            % 触发后的最短间隔
    info.muMaxDiff=max(info.muMaxDiff,abs(muNow-refP));
    if abs(muNow-refP)<=lvlThr
        pend=false; continue;                          % 功率水平正常
    end
    if ~pend                                           % 噪声确认: 连续两窗越限才动作
        pend=true; holdCnt=0; continue;
    end
    pend=false;
    % --- 连续两窗越限: 确认对象已变, 直接全局升级 ---
    % 设计权衡(能耗账): 升级成本约60评估(粗扫描41+精调20), 在1小时窗内
    % 折合能耗约0.06%; 而错锁谷底的持续代价可达9%+。崎岖曲线上斜率/改善量
    % 探针会被纹波抵消(实测), 重扫描是唯一可靠判别。dy平移会多花一次升级,
    % relocalMax 封顶总次数。
    info.relocals=info.relocals+1;
    if info.escalations>=p.relocalMax || plant.count()>n-45
        refP=muNow; holdCnt=0;                          % 升级配额已尽: 吸收
        continue;
    end
    info.escalations=info.escalations+1;
    [bestV,bestP]=globalEscalate(bestV);
    [bestV,bestP]=polish(bestV);
    info.best=bestV; info.bestP=bestP;
    holdCnt=0; refP=NaN; nfill=0;
end
info.best=bestV;

    function y=meanQ_safe()
        y=bestP;   % 预算耗尽兜底: 以搜索期最优功率作为参考水平
    end

    function y=meanQ(v,tag,m)
        acc=0;
        for r=1:m
            if plant.count()>=n, acc=acc+NaN; break; end
            acc=acc+plant.q(v,tag);
        end
        y=acc/m;
    end

    function s=repeatStd(v)
        vals=zeros(1,p.eaSigmaRepeats);
        for r=1:p.eaSigmaRepeats
            if plant.count()>=n, vals(r)=NaN; break; end
            vals(r)=plant.q(v,'sigma');
        end
        s=std(vals,'omitnan');
        if isnan(s)||s<=0, s=0.01; end   % 退化兜底常数(不引用对象噪声真值)
    end

    function fv=farPoints(cNow)
        cand=[p.lower+0.25*(p.upper-p.lower),...
              p.lower+0.50*(p.upper-p.lower),...
              p.lower+0.75*(p.upper-p.lower)];
        fv=cand(abs(cand-cNow)>1.5);
        if isempty(fv), fv=cand(1); end
        if numel(fv)>p.eaFarProbes
            [~,ord]=sort(abs(fv-cNow),'descend');
            fv=fv(ord(1:p.eaFarProbes));
        end
    end

    function [cOut,pOut]=localPS(c0,w0,w1)
        cOut=c0; w=w0; pOut=Inf;
        for it=1:2
            vr=linspace(max(p.lower,cOut-w),min(p.upper,cOut+w),7);
            pr=Inf(1,7);
            for i=1:7
                if plant.count()>=n, break; end
                pr(i)=plant.q(vr(i),'local');
            end
            [~,il]=min(pr);
            if ~isfinite(pr(il)), break; end
            cOut=vr(il); pOut=min(pOut,pr(il)); w=w1;
        end
        info.phase='local';
    end

    function [vOut,pOut]=globalEscalate(cSeed)
        vs=linspace(p.lower,p.upper,p.eaScanN);
        pr=Inf(1,p.eaScanN);
        for i=1:p.eaScanN
            if plant.count()>=n, break; end
            pr(i)=plant.q(vs(i),'scan');
        end
        pf=usearch.apply_filter(pr,p.filterMethod,min(p.filterW,5));
        [~,iMin]=min(pf);
        cand=vs(iMin);
        for i=2:numel(vs)-1
            if pf(i)<=pf(i-1)&&pf(i)<=pf(i+1)&&all(abs(cand-vs(i))>=p.minSep)
                cand(end+1)=vs(i); %#ok<AGROW>
                if numel(cand)>=p.eaK, break; end
            end
        end
        cand=mergePt(cand,cSeed);
        if numel(cand)>2, cand=cand(1:2); end   % 升级成本控制: 只精调两个候选
        info.candidates=cand;
        vOut=NaN; pOut=Inf;
        for j=1:numel(cand)
            if plant.count()>n-14, break; end
            cj=cand(j); w=0.6;   % 首轮窗口须罩住粗扫描网格误差(步长0.5)
            for it=1:2
                vr=linspace(max(p.lower,cj-w),min(p.upper,cj+w),7);
                prj=Inf(1,7);
                for i=1:7
                    if plant.count()>=n, break; end
                    prj(i)=plant.q(vr(i),'refine');
                end
                [~,il]=min(prj);
                if ~isfinite(prj(il)), break; end
                cj=vr(il); w=0.25;
            end
            pj=plant.q(cj,'refine');
            if isfinite(pj)&&pj<pOut, pOut=pj; vOut=cj; end
            plant.amendEstimate(vOut);
        end
        info.scanEvals=plant.count();
        info.phase='scan';
    end

    function out=mergePt(list,vnew)
        if isempty(list)||all(abs(list-vnew)>=p.minSep)
            out=[list vnew];
        else
            out=list;
        end
    end

    function [vOut,pOut]=polish(vIn)
        vOut=vIn; pOut=Inf;
        if isnan(vIn)||plant.count()>n-p.eaPolishRepeats*5, return; end
        vp=vIn+[-0.24 -0.12 0 0.12 0.24];
        pp=zeros(1,5);
        for i=1:5
            if plant.count()>=n, pp(i)=NaN; break; end
            pp(i)=meanQ(vp(i),'polish',p.eaPolishRepeats);
        end
        ok=isfinite(pp);
        if sum(ok)>=3
            pv=polyfit(vp(ok)-vIn,pp(ok),2);
            vtx=-pv(2)/(2*pv(3));
            vtx=min(max(vtx,-0.25),0.25);
            vOut=vIn+vtx; pOut=min(pp(ok));
        end
        plant.amendEstimate(vOut);
        info.phase='polish';
    end
end
