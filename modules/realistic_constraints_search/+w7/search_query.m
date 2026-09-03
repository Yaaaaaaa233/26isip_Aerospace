function f = search_query(plant, qs)
%SEARCH_QUERY 维护运行中argmin的查询句柄(任务7版: 经指令就位包装器qs)。
% 每次(就位)评估后, 把"迄今最小功率的速度"写入该行的估计列。
% estimate 语义 = 看到本次测量后算法的当前信念(与任务6一致)。
best=Inf; bestV=NaN;
f=@query;
    function J=query(v)
        J=qs(v,'search');
        if J<best, best=J; bestV=v; end
        plant.amendEstimate(bestV);
    end
end
