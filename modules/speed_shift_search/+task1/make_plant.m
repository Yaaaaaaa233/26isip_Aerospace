function plant = make_plant(scn, c)
%MAKE_PLANT Black-box query adapter with evaluator-side logging.
% 黑箱口径：搜索器只能调用 plant.q(v,tag) 拿到一个功率标量；
% 真值列(powerTrue/optimumTrue/minPowerTrue)只进评价日志，不返回给搜索器。
%
% 每次调用 = 一个评估步：速度瞬时生效(任务1设定)，停留 tEval 秒读一次功率。
% plant.q(v,tag)        提交速度 v，返回测量功率；tag 记录算法侧相位
% plant.amendEstimate(v) 修正刚写入那一行的"算法当前最优估计"
% plant.count()         已消耗的评估步数(上限 c.duration)
% plant.table()         评价日志表(全部真值列)
n=c.duration; rows=zeros(n,8); tags=cell(n,1); k=0; rng(scn.seed);
plant=struct('q',@q,'amendEstimate',@amend,'count',@countFcn,'table',@tbl);
    function c=countFcn()
        c=k;   % 嵌套函数共享工作区；匿名函数@()k会在创建时快照, 永远返回0
    end
    function J=q(v,tag)
        assert(k<n,'task1:Plant','Evaluation budget exhausted.');
        k=k+1; t=(k-1)*c.tEval;
        [dx,dy]=task1.shift_truth(scn,t);
        truth=task1.power_map(v-dx,c)+dy;
        measured=truth*(1+scn.noiseSigma*randn);
        rows(k,:)=[k,t,v,measured,truth,c.optimum0+dx,task1.power_map(c.optimum0,c)+dy,NaN];
        tags{k}=tag; J=measured;
    end
    function amend(vestimate)
        rows(k,8)=vestimate;
    end
    function out=tbl()
        assert(k==n,'task1:Plant','Run incomplete: %d of %d steps.',k,n);
        out=table(rows(:,1),rows(:,2),rows(:,3),string(tags),rows(:,4),rows(:,5),...
            rows(:,6),rows(:,7),rows(:,8),...
            'VariableNames',{'step','time','speed','tag','powerMeas','powerTrue',...
            'optimumTrue','minPowerTrue','estimate'});
    end
end
