function info = sweepcal_run(plant, p, n)
%SWEEPCAL_RUN 全比域快扫标定 + 在线精化(w11主角, 纯因果, 曲线/干扰未知)。
% 方法论逐项移植自 3.4 sweepcal_run(含2026-09-08全部修复):
% Phase A 标定(前 swSteps 步): 桨比双向斜坡扫(上行60%+下行40%, 航向错开),
%   采集 (死推航向ψ̂, 指令桨比r, 带噪功率P) 样本, 联合辨识
%     min_{f,θ} Σ (P_i − f(r_i − δ̂(ψ_i)))²,  δ̂(ψ)=a0+a1·cosψ+b1·sinψ, f=四次式;
%   û*类比: r̂* = argmin f̂ 只在样本覆盖的 u 范围内搜索(禁止外推) +
%   样本支撑谷底选择(内点极小中选±0.04支撑最大者, 防边缘假谷自我确认)。
%   删半程预热拟合(单向扫样本上 (f,θ) 不可辨识, 其 argmin 无意义)。
% Phase B 在线精化(其余预算):
%   - 每步闭式调度 r_cmd = r̂* + δ̂(ψ̂);
%   - 每 swRefitEvery 步重拟合(标定块永久+最近窗), SSE 改善才接受;
%   - 每 ucProbeEvery 步一对 ±ucProbeDelta 探针(上下交替), 割线曲率自校正,
%     探针信赖域: r̂* 只在当前曲线支撑谷底 rArg±0.08 内动(大幅修正只能来自重拟合)。
% 因果口径(红线1): 只用带噪功率+自身指令(航向死推 ψ̂'=V/R? 否——ψ̂ 由指令死推
%   ψ̂'=r无关; 转迹运动学 ψ'=V(t)/R 与指令无关, 控制器按同式重算)+tEval;
%   p 为 ctrl_view 白名单——不含真值 rStar0/case/γ场/MT链参数任何真值。
qs=w11.settled_q(plant,p,n);
% 标定块(永久) + 最近窗口(环形)
calPsi=zeros(1,p.swSteps); calR=zeros(1,p.swSteps); calP=zeros(1,p.swSteps);
Wn=max(60,round(p.swWinMax));
rnPsi=zeros(1,Wn); rnR=zeros(1,Wn); rnP=zeros(1,Wn);
nr=0; psiUnw=0;
% 双向扫: 上行(60%步数)+下行(40%步数)——同一桨比在不同航向各出现一次。
nUp=ceil(0.6*p.swSteps);
rSw=[linspace(p.swLo,p.swHi,nUp), linspace(p.swHi,p.swLo,p.swSteps-nUp)];
coefs=NaN(1,5); thSm=[0;0;0]; rKept=nan(1,0); rKeptCal=nan(1,0);
rStar=0.5*(p.swLo+p.swHi);            % 初值=扫描区间中点(无任何先验)
rArg=rStar;                           % 当前曲线的支撑谷底(探针信赖域中心)
rLo=p.swLo; rHi=p.swHi;               % argmin 允许的 u 范围(随拟合集更新)
phase=1; calibSteps=NaN; fitRms=NaN; kStep=0; v=NaN;
bEst=p.ucB0; sPrev=NaN; rPrev=NaN;
rHat=nan(1,n); thEst=nan(3,n); phHist=2*ones(1,n);
while plant.count()<n
    kStep=kStep+1;
    kp=kStep-p.swSteps;                % 相对标定结束的步数(Phase B用)
    if kStep<=p.swSteps
        r=rSw(kStep); tag='calib';     % Phase A: 全比域斜坡扫
    else
        % ---- Phase B: 闭式调度 r_cmd = r̂* + δ̂(ψ̂) ----
        r=rStar+thSm(1)+thSm(2)*cos(psiUnw)+thSm(3)*sin(psiUnw);
        r=min(max(r,p.lower+0.02),p.upper-0.02);
        tag='refine';
        % ---- 探针对(上下交替): 每 ucProbeEvery 步占2步 ----
        sgn=(-1)^floor(kp/p.ucProbeEvery);
        if mod(kp,p.ucProbeEvery)==1
            r=min(max(r+sgn*p.ucProbeDelta,p.lower+0.02),p.upper-0.02); tag='probe';
        elseif mod(kp,p.ucProbeEvery)==2
            r=min(max(r-sgn*p.ucProbeDelta,p.lower+0.02),p.upper-0.02); tag='probe';
        end
    end
    c0=plant.count();
    Pm=qs(r,tag);
    if ~isfinite(Pm), kStep=kStep-1; break; end
    sUsed=plant.count()-c0;
    tStart=(plant.count()-sUsed)*p.tEval;
    for j=1:sUsed                       % 航向死推: ψ̂'=V(t)/R(飞行模式为任务参数, 非对象真值)
        psiUnw=psiUnw+w11.mission_speed(p,tStart+(j-0.5)*p.tEval)/p.turnRadius*p.tEval;
    end
    % ---- 样本入库 ----
    if kStep<=p.swSteps
        calPsi(kStep)=psiUnw; calR(kStep)=r; calP(kStep)=Pm;
    end
    if phase==2
        if nr<Wn, nr=nr+1;
        else
            rnPsi(1:end-1)=rnPsi(2:end); rnR(1:end-1)=rnR(2:end);
            rnP(1:end-1)=rnP(2:end);
        end
        rnPsi(nr)=psiUnw; rnR(nr)=r; rnP(nr)=Pm;
    end
    % ---- Phase A 标定点: 全程正式拟合(无半程预热——单向扫不可辨识) ----
    if kStep==p.swSteps
        [coefs,thSm,fitRms,rLo,rHi,rKept]=w11.fit_curve_interf(calPsi(1:kStep),...
            calR(1:kStep),calP(1:kStep),p);
        rStar=w11.curve_argmin(coefs,rLo,rHi,p,rKept);
        rArg=rStar;
        rKeptCal=rKept;               % 标定块样本u(支撑判据永久用它——近期窗会被
                                      % "当前控在哪"污染, 用它选谷底会自我确认)
        phase=2; calibSteps=kStep;
        rPrev=rStar; sPrev=NaN;
    end
    % ---- Phase B: 曲线重拟合(每 swRefitEvery 步) + 探针更新 r̂* ----
    % (可辨识性口径: 近窗样本聚在窄 r 区间, δ 与 c0 在窄窗上不可辨识——故本域
    %  不做速度包式 δw 增量修正; 均匀漂移由"标定块+近窗"重拟合的 argmin 跟踪,
    %  谐波分量由 θ̂ 冻结传递。)
    if phase==2 && mod(kStep,p.swRefitEvery)==0 && nr>=30
        % (1) 曲线重拟合(冻结θ: 线性最小二乘唯一, 稳定不跳变)
        psSet=[calPsi, rnPsi(1:nr)];
        rSet=[calR,   rnR(1:nr)];
        pSet=[calP,   rnP(1:nr)];
        [coefsN,~,fitRmsN,rLoN,rHiN,rKeptN]=w11.fit_curve_interf(psSet,rSet,pSet,p,thSm);
        sseOld=w11.curve_sse(coefs,thSm,psSet,rSet,pSet,p);
        sseNew=w11.curve_sse(coefsN,thSm,psSet,rSet,pSet,p);
        if sseNew < sseOld*0.999
            coefs=coefsN; rLo=rLoN; rHi=rHiN; fitRms=fitRmsN; rKept=rKeptN;
        end
        rSup=rKeptCal; if isempty(rSup), rSup=rKeptN; end
        rStar=w11.curve_argmin(coefs,rLo,rHi,p,rSup);
        rArg=rStar;
    end
    if phase==2 && mod(kp,p.ucProbeEvery)==2 && nr>=2
        sPair=(rnP(nr-1)-rnP(nr))/(2*p.ucProbeDelta);  % +δ采样在nr-1
        if ~isnan(sPrev) && abs(rStar-rPrev)>0.005
            bRaw=abs(sPair-sPrev)/abs(rStar-rPrev);
            bEst=max(0.05,0.8*bEst+0.2*min(bRaw,8.0));
        end
        if abs(sPair)>p.ucThr
            du=-p.ucGain*sPair/max(bEst,0.05);
            du=min(max(du,-0.02),0.02);
            rPrev=rStar;
            % 探针信赖域: r̂*只允许在当前曲线支撑谷底 rArg±0.08 内——大幅修正
            % 只能来自重拟合argmin(2026-09-08修复移植)。
            rStar=min(max(rStar+du,rArg-0.08),rArg+0.08);
            rStar=min(max(rStar,p.lower+0.03),p.upper-0.03);
            sPrev=sPair;
        else
            sPrev=NaN;   % 噪声门限以下: 不更新也不累积割线
        end
    end
    rHat(kStep)=rStar; thEst(:,kStep)=thSm; phHist(kStep)=phase;
end
while plant.count()<n
    plant.q(v,'hold'); plant.amendEstimate(v);
end
info=struct('best',v,'bestP',NaN,'mode','sweepcal',...
    'rHat',rHat,'thEst',thEst,'phase',phHist,'coefs',coefs,...
    'calibSteps',calibSteps,'fitRms',fitRms,'rStar',rStar,'rLo',rLo,'rHi',rHi,...
    'thFinal',thSm,'bEst',bEst);
end
