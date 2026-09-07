function plant = make_plant(scn, c)
%MAKE_PLANT 工作包w11黑箱对象（桨比表+功率表 + 评价日志）。
% 黑箱口径(AGENTS.md红线1/2): 算法侧只能调 plant.q(r,tag) 拿带噪测量、
% plant.amendEstimate(r) 修正信念、plant.count() 查预算; 接口签名与速度包
% 完全一致(对象侧升级不改控制器接口), 真值列只进评价日志。
%
% 控制量: r = eta_Omega = Ω_u/Ω_l ∈ [0.75,1.25](项目任务书表1), 开环默认 r=1。
% 执行链(类比任务7, 转速通道):
%   1) 通信时延 FIFO(latencySec): 指令入队, 到期释放, 取最新为执行目标;
%   2) 桨比变化率限幅 |dr/dt|<=slewMax(电机+ESC转速通道惯性), 无"瞬跳";
%   3) 航迹运动学 ψ'=V(t)/turnRadius —— V(t) 由飞行模式决定(与指令解耦):
%      hover(V=0) / fixed(V=fwdSpeed) / vary(V=fwdSpeed+varyAmp·sin(ωt))。
% 功率路径(每子步):
%   γ_eff = interfer_field(scn,t,ψ) + shift_truth 的 dGam;
%   [dx,dlev] = drift_of(γ_eff) —— 谷底漂移与功率水平因子(MT链映射);
%   P_sub = dlev·truth_curve(rAct − dx) + fwd_level(V)·dy;
%   步真值/测量取子步均值(能量口径); r*/γ/dx 列取步末状态。
% 测量: J = P_true·(1+noiseSigma·randn), 可选脉冲(任务2模型原样保留)。
n = c.duration; M = c.subSteps; dts = c.tEval/M;
rows = nan(n,15); tags = cell(n,1); k = 0;
rng(c.seed);
rAct = c.initialRatio; psi = 0; rTarget = c.initialRatio;   % 执行目标=最近已释放指令
tQ = zeros(1,0); rQ = zeros(1,0);          % 通信时延FIFO: [释放时刻; 指令]
plant = struct('q',@q,'amendEstimate',@amend,'count',@countFcn,'table',@tbl,...
    'truthPsi',@truthPsi,'J0min',c.ratioCase); % truthPsi仅供known oracle(评价侧)
    function cn=countFcn()
        cn=k;   % 嵌套函数共享工作区; 匿名函数会按创建时快照
    end
    function ps=truthPsi()
        ps=psi;
    end
    function Jm=q(r,tag)
        assert(k<n,'w11:Plant','Evaluation budget exhausted.');
        k=k+1;
        tStep=(k-1)*c.tEval;
        tQ(end+1)=tStep+c.latencySec; rQ(end+1)=r; %#ok<AGROW> % 指令入队
        sumP=0; sumDx=0; sumDy=0; sumDlev=0; slewStep=0;
        for m=1:M
            tNow=tStep+(m-1)*dts;
            % ---- 1) 通信时延: 释放所有到期指令, 取最新为目标 ----
            rel=tQ<=tNow+1e-9;
            if any(rel)
                rTarget=rQ(find(rel,1,'last'));
                tQ(rel)=[]; rQ(rel)=[];
            end
            % ---- 2) 桨比变化率限幅: 向执行目标趋近 |dr/dt|<=slewMax ----
            dr=rTarget-rAct;
            drr=max(-c.slewMax,min(c.slewMax,dr/dts));
            slewStep=max(slewStep,abs(drr));
            rAct=rAct+drr*dts;
            % ---- 3) 航迹运动学: ψ'=V(t)/R, V 由飞行模式决定(与指令解耦) ----
            switch scn.flightMode
                case 'hover', V=0;
                case 'fixed', V=scn.fwdSpeed;
                otherwise,    V=scn.fwdSpeed+scn.varyAmp*sin(scn.varyOmega*tNow);
            end
            psi=mod(psi+(V/c.turnRadius)*dts,2*pi);
            % ---- 干扰功率路径: γ_eff → (漂移dx, 水平dlev) → 真值曲线平移;
            %      前飞水平因子 fV(Hwang代理) 乘在整条功率上 ----
            [~,gEff]=w11.interfer_field(scn,tNow,psi);
            [dGam,dyS]=w11.shift_truth(scn,tNow);
            [dxM,dlevM]=w11.drift_of(gEff+dGam,c);
            fV=w11.fwd_level(V,c);
            Psub=dlevM*fV*w11.truth_curve(min(max(rAct,c.lower),c.upper)-dxM,c) ...
                + fV*dyS;
            sumP=sumP+Psub; sumDx=sumDx+dxM; sumDy=sumDy+dyS; sumDlev=sumDlev+dlevM*fV;
        end
        Ptrue=sumP/M; dxM=sumDx/M; dyM=sumDy/M; dlevM=sumDlev/M;
        Jm=Ptrue*(1+c.noiseSigma*randn);
        if c.impulse && rand<c.impulseRate, Jm=Jm+(2*rand-1)*c.impulseSize; end
        % ---- 步末状态的真值最优 r*(t) 与理论最低功率(评价侧专用列) ----
        tEnd=tStep+c.tEval;
        [~,gEffE]=w11.interfer_field(scn,tEnd,psi);
        [dGamE,~]=w11.shift_truth(scn,tEnd);
        [dxE,~]=w11.drift_of(gEffE+dGamE,c);
        rOpt=min(max(c.rStar0+dxE,c.lower),c.upper);
        switch scn.flightMode
            case 'hover', VE=0;
            case 'fixed', VE=scn.fwdSpeed;
            otherwise,    VE=scn.fwdSpeed+scn.varyAmp*sin(scn.varyOmega*tEnd);
        end
        rows(k,:)=[k,tStep,rAct,rTarget,Jm,Ptrue,rOpt,...
            dlevM*c.ratioCase+dyM,NaN,rad2deg(psi),dxM,dyM,slewStep*dts,VE,...
            gEffE+dGamE];
        tags{k}=tag;
    end
    function amend(rest)
        rows(k,9)=rest;
    end
    function out=tbl()
        assert(k==n,'w11:Plant','Run incomplete: %d of %d steps.',k,n);
        out=table(rows(:,1),rows(:,2),rows(:,3),rows(:,4),string(tags),...
            rows(:,5),rows(:,6),rows(:,7),rows(:,8),rows(:,9),rows(:,10),...
            rows(:,11),rows(:,12),rows(:,13),rows(:,14),rows(:,15),...
            'VariableNames',{'step','time','ratio','ratioCmd','tag','powerMeas',...
            'powerTrue','optimumTrue','minPowerTrue','estimate','headingDeg',...
            'driftDx','shiftDy','slewUsed','flightV','gammaTrue'});
    end
end
