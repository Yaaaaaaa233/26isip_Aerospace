function [log, info] = run_algorithm(name, c)
%RUN_ALGORITHM 用指定算法对崎岖静态场景跑完整一幕(共 c.duration 个评估步)。
% name:
%   'multistart'    扫描+滤波+多起点精调(任务2推荐方案)
%   'filter_argmin' 扫描+滤波后直接取argmin并锁定(消融: 只滤波不精调)
%   'single_golden' 以初始速度为中心的局部夹逼黄金分割(消融: 单起点陷阱)
%   'grid'          细网格扫描后锁定argmin(基线)
%   'esc'           连续极值寻优(基线: 局部方法遇多峰的对照)
% 除 multistart/esc 外均为"搜索后锁定"：结束后停在最优估计上直到预算用尽。
plant=task2.make_plant(c);
p=task2.controller_config(c);
n=c.duration;
switch name
    case 'multistart'
        info=task2.multistart_run(plant,p,n);
    case 'esc'
        info=task2.esc_run(plant,p,n);
    case 'single_golden'
        f=@(v) meanQuery(v);
        a=max(p.lower,p.initialSpeed-p.refineSpan*2);
        b=min(p.upper,p.initialSpeed+p.refineSpan*2);
        s=task2.golden_search(f,a,b,p.tol,p.maxSearchEval);
        info=struct('best',s.x,'bestP',s.fx,'candidates',p.initialSpeed,...
            'scanSteps',0,'refineSteps',plant.count(),'filteredArgmin',NaN,...
            'filterMethod','none','filterW',0);
        holdRest(plant,s.x,n);
    case 'filter_argmin'
        vs=linspace(p.lower,p.upper,p.scanN); pm=zeros(1,p.scanN);
        for i=1:p.scanN
            pm(i)=plant.q(vs(i),'scan'); plant.amendEstimate(NaN);
        end
        pf=task2.apply_filter(pm,p.filterMethod,p.filterW);
        [~,iMin]=min(pf); vBest=vs(iMin);
        info=struct('best',vBest,'bestP',pf(iMin),'candidates',vBest,...
            'scanSteps',plant.count(),'refineSteps',0,'filteredArgmin',vBest,...
            'filterMethod',p.filterMethod,'filterW',p.filterW);
        holdRest(plant,vBest,n);
    case 'grid'
        v=linspace(p.lower,p.upper,round((p.upper-p.lower)/p.gridResolution)+1);
        fv=inf(size(v));
        for k=1:numel(v)
            fv(k)=plant.q(v(k),'scan'); plant.amendEstimate(NaN);
        end
        [~,i]=min(fv);
        info=struct('best',v(i),'bestP',fv(i),'candidates',v(i),...
            'scanSteps',plant.count(),'refineSteps',0,'filteredArgmin',v(i),...
            'filterMethod','none','filterW',0);
        holdRest(plant,v(i),n);
    otherwise
        error('task2:RunAlgorithm','Unknown algorithm: %s',name);
end
info.name=name; info.seed=c.seed; info.noiseSigma=c.noiseSigma;
log=plant.table();

    function y=meanQuery(v)
        acc=0;
        for r=1:p.repeats
            if plant.count()>=n, break; end
            acc=acc+plant.q(v,'refine');
        end
        y=acc;
    end

    function holdRest(plant2,v,n2)
        while plant2.count()<n2
            plant2.q(v,'hold'); plant2.amendEstimate(v);
        end
    end
end
