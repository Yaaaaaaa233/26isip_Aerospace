function qs = settled_q(plant, p, n)
%SETTLED_Q 任务7指令就位查询包装器(控制器侧, 纯因果)。
% 通信时延 τ 与加速度限幅 amax 使一条新指令需 t_settle = τ + |Δv|/amax 才能物理
% 到位; 任务6算法按"指令瞬时生效"设计, 直接探针会测到过渡过程(速度还没到位)。
% 本包装器对全部算法一致施加同一条就位规则:
%   qs(v,tag) = 先以该指令平飞 s−1 步(占位, tag='settle'), 第 s 步取测量(tag=原值),
%   s = ceil((latencySec + |v−v_prev|/aMax)/tEval), 钳位到剩余预算。
% v_prev 由包装器记忆自己转发的上一条指令(含hold), 不读对象内部状态(红线1)。
% 占位步对 hold 语义保持 'hold'(指令不变的就位过程本身就是锁定平飞)。
% 预算耗尽时返回 Inf, 由调用方转入末段锁定(与任务6预算边界约定一致)。
prev=NaN;
qs=@query;
    function J=query(v,tag)
        if plant.count()>=n, J=Inf; return; end
        dv=abs(v-prev);
        if isnan(prev), dv=abs(v-p.initialSpeed); end   % 首查按初速差
        s=ceil((p.latencySec+dv/p.aMax)/p.tEval);
        s=max(1,min(s,n-plant.count()));
        if strcmp(tag,'hold'), ptag='hold'; else, ptag='settle'; end
        for i=1:s-1
            if plant.count()>=n, break; end
            plant.q(v,ptag); plant.amendEstimate(v);
        end
        if plant.count()>=n, J=Inf; return; end
        J=plant.q(v,tag); plant.amendEstimate(v);
        prev=v;
    end
end
