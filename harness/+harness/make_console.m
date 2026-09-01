function [console, log] = make_console(kind, c)
%MAKE_CONSOLE 模块3/3：控制台(我们做的算法)。只通过 aircraft.query 黑箱查询。
% kind: 'multistart' | 'single_golden' | 'grid' | 'esc' | 'fixed'
% 控制台看到的接口只有双表盘黑箱与自身白名单配置(task2.controller_config)，
% 看不到曲线/真值最优/噪声/种子(AGENTS.md红线1)。
p=task2.controller_config(c);
c2=rmfield(c,{'T','powerScaleW'});          % harness窗长 -> task2评估步数
c2.duration=round(c.T/c.tEval);
c2.tailSteps=round(60/c.tEval);
plant=task2.make_plant(c2);
n=c2.duration;
switch kind
    case 'multistart'
        info=task2.multistart_run(plant,p,n);
    case 'esc'
        info=task2.esc_run(plant,p,n);
    case 'single_golden'
        f=@(v)q1(v);
        a=max(p.lower,c.initialSpeed-p.refineSpan*2);
        b=min(p.upper,p.initialSpeed+p.refineSpan*2);
        s=task2.golden_search(f,a,b,p.tol,p.maxSearchEval);
        info=struct('best',s.x,'bestP',s.fx,'candidates',s.x,'scanSteps',0,...
            'refineSteps',plant.count(),'filteredArgmin',NaN,'filterMethod','none','filterW',0);
        holdRest(plant,s.x,n);
    case 'grid'
        v=linspace(p.lower,p.upper,round((p.upper-p.lower)/p.gridResolution)+1);
        fv=inf(size(v));
        for k=1:numel(v), fv(k)=q1(v(k)); end
        [~,i]=min(fv);
        info=struct('best',v(i),'bestP',fv(i),'candidates',v(i),'scanSteps',plant.count(),...
            'refineSteps',0,'filteredArgmin',v(i),'filterMethod','none','filterW',0);
        holdRest(plant,v(i),n);
    case 'fixed'
        while plant.count()<n
            plant.q(c.optimum0,'hold'); plant.amendEstimate(c.optimum0);
        end
        info=struct('best',c.optimum0,'bestP',NaN,'candidates',c.optimum0,...
            'scanSteps',0,'refineSteps',0,'filteredArgmin',c.optimum0,...
            'filterMethod','none','filterW',0);
    otherwise
        error('harness:Console','Unknown console kind: %s',kind);
end
console=info;
log=plant.table();

    function y=q1(v)
        y=plant.q(v,'refine');
    end
    function holdRest(plant2,v,n2)
        while plant2.count()<n2
            plant2.q(v,'hold'); plant2.amendEstimate(v);
        end
    end
end
