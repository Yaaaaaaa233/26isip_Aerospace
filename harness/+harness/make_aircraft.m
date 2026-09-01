function ac = make_aircraft(c)
%MAKE_AIRCRAFT 模块2/3：飞机模型 = 双表盘黑箱(速度表+功率表)。
% 对控制台暴露的接口(全部物理量的"测量面")：
%   ac.query(v, t) -> P_meas   设定速度、读取功率(瞬时执行+带噪测量)
%   ac.gauges()     -> 结构体   两个表盘的当前读数(速度/最近功率)
% 评价侧(不出现在控制台)：true_power、Pmin 曲线、全局最优点。
%
% 因果边界(AGENTS.md红线1)：query 只返回测量功率；真值与曲线只进评价日志。
% 功率模型=调试二次曲线+对称崎岖项(任务2对象, 静态无平移)；
% environment 的风当前恒零——任务3-5接入风场时, 空速=|v*t̂+w| 在此换算,
% 黑箱接口不变(对象升级位置, 红线2)。
[~, vG, PG] = task2.power_map([], cfgAsTask2(c));
rng(c.seed);
ac=struct('query',@query,'gauges',@gauges,'truth',@truth,'Pmin',PG,'vStar',vG);
speedNow=NaN; powerNow=NaN;
    function Jm=query(v, t)
        %#ok<NASGU> % t 预留给时变对象/风场
        J=truePower(v);
        Jm=J*(1+c.noiseSigma*randn);
        if c.impulse && rand<c.impulseRate, Jm=Jm+(2*rand-1)*c.impulseSize; end
        speedNow=v; powerNow=Jm;
    end
    function g=gauges()
        g.speed=speedNow; g.power=powerNow;
    end
    function J=truePower(v)
        J=task2.power_map(v,cfgAsTask2(c));
    end
    function out=truth()
        % 评价侧：真值曲线+最优点+Pmin(归一化与瓦级)
        vv=linspace(c.lower,c.upper,801);
        out.curveV=vv; out.curveJ=task2.power_map(vv,cfgAsTask2(c));
        out.vStar=ac.vStar; out.PminNorm=ac.Pmin;
        out.PminW=ac.Pmin*c.powerScaleW;
    end
end

function c2 = cfgAsTask2(c)
c2=struct('lower',c.lower,'upper',c.upper,'optimum0',c.optimum0,...
    'rippleA1',c.rippleA1,'rippleL1',c.rippleL1,'rippleF1',c.rippleF1,...
    'rippleA2',c.rippleA2,'rippleL2',c.rippleL2,'rippleF2',c.rippleF2);
end
