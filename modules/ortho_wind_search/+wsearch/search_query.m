function f = search_query(plant)
%SEARCH_QUERY Query handle that maintains a running argmin as the estimate.
% 供 grid/ternary/golden/brent 使用：每次评估后，把"迄今最小功率的速度"
% 写入该行的估计列。estimate 语义 = 看到本次测量后算法的当前信念。
best=Inf; bestV=NaN;
f=@query;
    function J=query(v)
        J=plant.q(v,'search');
        if J<best, best=J; bestV=v; end
        plant.amendEstimate(bestV);
    end
end
