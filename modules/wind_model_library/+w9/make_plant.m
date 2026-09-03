function plant = make_plant(scn, c)
%MAKE_PLANT 任务9风场模型库黑箱对象（速度表+功率表 + 评价日志）。
% 黑箱口径(AGENTS.md红线1/2): 算法侧只能调 plant.q(v,tag) 拿带噪测量、
% plant.amendEstimate(v) 修正信念、plant.count() 查预算; 接口签名与任务6
% 完全一致(对象侧升级不改控制器接口), 真值列只进评价日志。
%
% 速度语义(任务9用户口径, 对象物理与此严格一致):
%   空速 u = 地速矢量 + 风矢量 = |v·t̂ + w|,  t̂=[cosψ,sinψ]为积分航向切向;
%   功率由空速决定: P = base_curve(u − dx(t)) + dy(t) —— 空速-功率标定曲线
%   不随风移动(只随平移调度dx/dy移动); 地速-功率曲线 P(v)=base_curve(|v·t̂+w|)
%   随风平移; 仪表盘/速度日志显示地速。解析最优(地速口径):
%   v*(t) = −q + sqrt(q² + u*² − |w|²),  q = t̂·w,  u* = optimum0+dx。
% 风场为七种可选模型(wind_field.m): const/sin/square/triangle/turb/
% composite/sector(sector依赖积分航向psi, 经wind_field传入)。
% 继承任务7实际约束: 1) 转弯半径物理化 psi'=v_actual/turnRadius;
% 2) 通信时延FIFO(latencySec); 3) 加速度限幅|dv/dt|<=aMax, 无"瞬移"。
% dx/dy 为任务1式平移调度(jumps/ramps, 代表载荷/温度等非风漂移)。
% 每步真值/测量取该步内子步均值(能量口径); v*/空速/风列取步末状态。
% 日志新增评价侧列: airspeed(空速), windX/windY(步末真风分量), 供面板与
% 核对"空速=地速+风速"; 算法侧不得读取(仍只经 q/amendEstimate/count 接口)。
n = c.duration; M = c.subSteps; dts = c.tEval/M;
rows = nan(n,16); tags = cell(n,1); k = 0;
[J0min, ~] = w9.base_curve(c.optimum0, c);
rng(c.seed);
vAct = c.initialSpeed; psi = 0; vTarget = c.initialSpeed;   % 执行目标=最近已释放指令
tQ = zeros(1,0); vQ = zeros(1,0);          % 通信时延FIFO: [释放时刻; 指令]
plant = struct('q',@q,'amendEstimate',@amend,'count',@countFcn,'table',@tbl,...
    'truthCurve',@truthCurve,'J0min',J0min,'truthPsi',@truthPsi); % 评价侧oracle专用(嵌套函数取活值; 匿名函数会快照)
    function cn=countFcn()
        cn=k;   % 嵌套函数共享工作区; 匿名函数会按创建时快照
    end
    function ps=truthPsi()
        ps=psi;  % 仅供known oracle参照(评价侧), 因果策略不得使用
    end
    function Jm=q(v,tag)
        assert(k<n,'w9:Plant','Evaluation budget exhausted.');
        k=k+1;
        tStep=(k-1)*c.tEval;
        tQ(end+1)=tStep+c.latencySec; vQ(end+1)=v; %#ok<AGROW> % 指令入队
        sumP=0; sumDx=0; sumDy=0; aMaxStep=0;
        for m=1:M
            tNow=tStep+(m-1)*dts;
            % ---- 1) 通信时延: 释放所有到期指令, 取最新为目标 ----
            rel=tQ<=tNow+1e-9;
            if any(rel)
                vTarget=vQ(find(rel,1,'last'));
                tQ(rel)=[]; vQ(rel)=[];
            end
            % ---- 3) 加速度限幅: 向执行目标趋近 |dv/dt|<=aMax ----
            dv=vTarget-vAct;
            a=max(-c.aMax,min(c.aMax,dv/dts));
            aMaxStep=max(aMaxStep,abs(a));
            vAct=vAct+a*dts;
            % ---- 2) 转弯半径运动学: 航向角速度=地速/半径 ----
            psi=mod(psi+(vAct/c.turnRadius)*dts,2*pi);
            % ---- 风功率路径(空速物理): u=|v·t̂+w|, w=wind_field(t,ψ) ----
            [~,~,Vx,Vy]=w9.wind_field(scn,tNow,psi);
            ux=vAct*cos(psi)+Vx; uy=vAct*sin(psi)+Vy;
            u=hypot(ux,uy);
            [dxS,dyS]=w9.shift_truth(scn,tNow);
            Psub=w9.base_curve(u-dxS,c)+dyS;
            sumP=sumP+Psub; sumDx=sumDx+dxS; sumDy=sumDy+dyS;
        end
        Ptrue=sumP/M; dxM=sumDx/M; dyM=sumDy/M;
        Jm=Ptrue*(1+c.noiseSigma*randn);
        if c.impulse && rand<c.impulseRate, Jm=Jm+(2*rand-1)*c.impulseSize; end
        % ---- 步末状态的解析最优 v*(t) 与理论最低功率(含空速/真风列) ----
        tEnd=tStep+c.tEval;
        [~,~,VxE,VyE]=w9.wind_field(scn,tEnd,psi);
        qE=VxE*cos(psi)+VyE*sin(psi);
        w2E=VxE^2+VyE^2;
        [dxE,~]=w9.shift_truth(scn,tEnd);
        ustar=c.optimum0+dxE;
        disc=qE^2+ustar^2-w2E;               % = u*²−|w_perp|², 恒可行口径
        if disc>=0, vOpt=-qE+sqrt(disc); else, vOpt=-qE; end
        vOpt=min(max(vOpt,c.lower),c.upper);
        uEnd=hypot(vAct*cos(psi)+VxE, vAct*sin(psi)+VyE);   % 步末空速=地速+风
        rows(k,:)=[k,tStep,vAct,vTarget,Jm,Ptrue,vOpt,...
            J0min+dyM,NaN,rad2deg(psi),dxM,dyM,aMaxStep,uEnd,VxE,VyE];
        tags{k}=tag;
    end
    function amend(vest)
        rows(k,9)=vest;
    end
    function out=truthCurve()
        vv=linspace(c.lower,c.upper,601);
        out.v=vv; out.J=w9.base_curve(vv,c);
    end
    function out=tbl()
        assert(k==n,'w9:Plant','Run incomplete: %d of %d steps.',k,n);
        out=table(rows(:,1),rows(:,2),rows(:,3),rows(:,4),string(tags),...
            rows(:,5),rows(:,6),rows(:,7),rows(:,8),rows(:,9),rows(:,10),...
            rows(:,11),rows(:,12),rows(:,13),rows(:,14),rows(:,15),rows(:,16),...
            'VariableNames',{'step','time','speed','speedCmd','tag','powerMeas',...
            'powerTrue','optimumTrue','minPowerTrue','estimate','headingDeg',...
            'shiftDx','shiftDy','accelMax','airspeed','windX','windY'});
    end
end
