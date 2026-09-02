function [log, info] = run_algorithm(name, scn, c)
%RUN_ALGORITHM 统一程序调度器：在指定平移场景上用指定算法跑完整一幕。
% name:
%   'ea_multistart' 能耗感知全局寻优(推荐: 局部优先+证据升级+周期复探)
%   'multistart'    任务2全扫描基线(61点遍历, 对照"完全遍历"策略)
%   'tracker'       任务1平移跟踪基线(Brent+迟滞监测, 低噪场景设计点)
%   'grid'          网格全遍历后锁定(基线)
%   'esc'           连续极值寻优(基线)
%   'spsa'          随机同步扰动逼近(任务6新增: 成对±探针+EWMA, 适配时变风场)
%   'bayes'         贝叶斯代理寻优(任务6新增: GP回归+置信下界采集+滑窗)
%   'qnewton'       二次模型牛顿寻优(任务6新增: 交错三点stencil+曲率EWMA)
%   'fixed'         全程停在基准最优(评价上界参照, 仅静态场景有意义)
%   'single_golden' 单起点局部夹逼(陷阱对照)
% 算法侧白名单：不传场景真值/曲线/噪声/种子(红线1)。
p=c;   % 统一config即白名单(对象真值由plant持有, 不经p传递)
plant=wsearch.make_plant(scn,c);
n=c.duration;
switch name
    case 'ea_multistart'
        info=wsearch.ea_run(plant,p,n);
    case 'multistart'
        info=wsearch.multistart_run(plant,p,n);
    case 'tracker'
        info=wsearch.tracker_run(plant,p,n);
    case 'esc'
        info=wsearch.esc_run(plant,p,n);
    case 'spsa'
        info=wsearch.spsa_run(plant,p,n);
    case 'bayes'
        info=wsearch.bayes_run(plant,p,n);
    case 'qnewton'
        info=wsearch.qnewton_run(plant,p,n);
    case 'grid'
        v=linspace(p.lower,p.upper,round((p.upper-p.lower)/p.gridResolution)+1);
        fv=inf(size(v));
        for k=1:numel(v), fv(k)=plant.q(v(k),'scan'); plant.amendEstimate(NaN); end
        [~,i]=min(fv);
        info=struct('best',v(i),'bestP',fv(i),'evals',numel(v));
        holdRest(plant,v(i),n);
    case 'fixed'
        while plant.count()<n
            plant.q(c.optimum0,'hold'); plant.amendEstimate(c.optimum0);
        end
        info=struct('best',c.optimum0,'bestP',NaN,'evals',0);
    case 'single_golden'
        f=@(v)q1(v);
        a=max(p.lower,c.initialSpeed-1.4); b=min(p.upper,c.initialSpeed+1.4);
        s=wsearch.brent_search(f,a,b,p.tol,p.maxSearchEval);
        info=struct('best',s.x,'bestP',s.fx,'evals',plant.count());
        holdRest(plant,s.x,n);
    otherwise
        error('wsearch:RunAlgorithm','Unknown algorithm: %s',name);
end
info.name=name; info.scenario=scn.kind; info.seed=c.seed;
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
