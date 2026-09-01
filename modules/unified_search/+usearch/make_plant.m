function plant = make_plant(scn, c)
%MAKE_PLANT 统一黑箱被控对象（速度表+功率表 + 评价日志）。
% 黑箱口径（AGENTS.md红线1）：算法侧只能调 plant.q(v,tag) 拿带噪测量、
% plant.amendEstimate(v) 修正信念、plant.count() 查预算；真值列只进评价日志。
% 对象：P(v,t) = base_curve(v − dx(t)) + dy(t)（严格平移, 任务1语义 × 任务2曲线）。
% minPowerTrue(t) = J0min + dy(t)（当前时刻理论最低功率, MOE的Pmin(t)）。
n = c.duration; rows = zeros(n,8); tags = cell(n,1); k = 0;
[~, J0min] = usearch.base_curve(c.optimum0, c);
rng(c.seed);
plant = struct('q',@q,'amendEstimate',@amend,'count',@countFcn,'table',@tbl,...
    'truthCurve',@truthCurve,'J0min',J0min);
    function cn=countFcn()
        cn=k;   % 嵌套函数共享工作区; 匿名函数会按创建时快照
    end
    function Jm=q(v,tag)
        assert(k<n,'usearch:Plant','Evaluation budget exhausted.');
        k=k+1; t=(k-1)*c.tEval;
        [dx,dy]=usearch.shift_truth(scn,t);
        truth=usearch.base_curve(v-dx,c)+dy;
        Jm=truth*(1+c.noiseSigma*randn);
        if c.impulse && rand<c.impulseRate, Jm=Jm+(2*rand-1)*c.impulseSize; end
        rows(k,:)=[k,t,v,Jm,truth,c.optimum0+dx,J0min+dy,NaN];
        tags{k}=tag;
    end
    function amend(vest)
        rows(k,8)=vest;
    end
    function out=truthCurve()
        vv=linspace(c.lower,c.upper,601);
        out.v=vv; out.J=usearch.base_curve(vv,c);
    end
    function out=tbl()
        assert(k==n,'usearch:Plant','Run incomplete: %d of %d steps.',k,n);
        out=table(rows(:,1),rows(:,2),rows(:,3),string(tags),rows(:,4),rows(:,5),...
            rows(:,6),rows(:,7),rows(:,8),...
            'VariableNames',{'step','time','speed','tag','powerMeas','powerTrue',...
            'optimumTrue','minPowerTrue','estimate'});
    end
end
