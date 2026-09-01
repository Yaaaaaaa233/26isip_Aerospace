function plant = make_plant(c)
%MAKE_PLANT Black-box query adapter with evaluator-side logging. Task 2: static.
% 黑箱口径：搜索器只能调用 plant.q(v,tag) 拿到一个(带噪)功率标量；
% 真值列(powerTrue/vGlobal/minPowerTrue)只进评价日志，不返回搜索器。
% 每次调用 = 一个评估步：瞬时生效(沿用任务1设定)，停留 tEval 秒读一次功率。
% 噪声：相对高斯 σ；可选野值(impulse=true 时以 impulseRate 概率叠加
% ±impulseSize 均匀脉冲——供中值滤波对照)。
n = c.duration; rows = zeros(n,7); tags = cell(n,1); k = 0;
[~, vG, PG] = task2.power_map([], c);
rng(c.seed);
plant = struct('q',@q,'amendEstimate',@amend,'count',@countFcn,'table',@tbl, ...
    'truthCurve',@()task2.power_map(linspace(c.lower,c.upper,601),c), ...
    'globalOptimum',vG,'globalPower',PG);
    function c0 = countFcn()
        c0 = k;   % 嵌套函数共享工作区；匿名函数会按创建时快照, 永远返回0
    end
    function J = q(v, tag)
        assert(k < n, 'task2:Plant', 'Evaluation budget exhausted.');
        k = k + 1;
        truth = task2.power_map(v, c);
        measured = truth * (1 + c.noiseSigma*randn);
        if c.impulse && rand < c.impulseRate
            measured = measured + (2*rand-1)*c.impulseSize;
        end
        rows(k,:) = [k, v, measured, truth, vG, PG, NaN];
        tags{k} = tag; J = measured;
    end
    function amend(vestimate)
        rows(k,7) = vestimate;
    end
    function out = tbl()
        assert(k == n, 'task2:Plant', 'Run incomplete: %d of %d steps.', k, n);
        out = table(rows(:,1), rows(:,2), rows(:,3), string(tags), rows(:,4), ...
            rows(:,5), rows(:,6), rows(:,7), ...
            'VariableNames', {'step','speed','powerMeas','tag','powerTrue', ...
            'globalOptimum','minPowerTrue','estimate'});
    end
end
