function qs = settled_q(plant, p, n)
%SETTLED_Q 就位规则包装器(控制器侧, 纯因果; 机制与速度包同构, 变量为桨比)。
% 通信时延 τ 与桨比变化率限幅 slewMax 使一条新指令需 t_settle = τ + |Δr|/slewMax
% 才能物理到位; 直接探针会测到过渡过程(转速还没跟上)。本包装器对全部算法一致
% 施加同一条就位规则:
%   qs(r,tag) = 先以该指令运行 s−1 步(占位, tag='settle'), 第 s 步取测量(tag=原值),
%   s = ceil((latencySec + |r−r_prev|/slewMax)/tEval), 钳位到剩余预算。
% r_prev 由包装器记忆自己转发的上一条指令(含hold), 不读对象内部状态(红线1)。
% 占位步对 hold 语义保持 'hold'(指令不变的就位过程本身就是锁定运行)。
% 预算耗尽时返回 Inf, 由调用方转入末段锁定(预算边界约定与速度包一致)。
prev=NaN;
qs=@query;
    function J=query(r,tag)
        if plant.count()>=n, J=Inf; return; end
        dr=abs(r-prev);
        if isnan(prev), dr=abs(r-p.initialRatio); end   % 首查按初始桨比差
        s=ceil((p.latencySec+dr/p.slewMax)/p.tEval);
        s=max(1,min(s,n-plant.count()));
        if strcmp(tag,'hold'), ptag='hold'; else, ptag='settle'; end
        for i=1:s-1
            if plant.count()>=n, break; end
            plant.q(r,ptag); plant.amendEstimate(r);
        end
        if plant.count()>=n, J=Inf; return; end
        J=plant.q(r,tag); plant.amendEstimate(r);
        prev=r;
    end
end
