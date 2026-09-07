function info = hybrid_run(plant, p, n)
%HYBRID_RUN 标定后在线消融主角：首飞全比域标定(冻结曲线) + 干扰场增量修正 + 信赖域探针。
% 动机(速度包3.3问题移植): "首飞标定后, 在线该用轻机器还是继续重拟合?"——
% 本策略把在线算力重心从"重新学曲线"移到"跟踪干扰漂移":
% Phase A 标定(前 swSteps 步, 与sweepcal完全一致): 桨比双向斜坡扫, 联合辨识 (f̂,θ̂);
% Phase B 在线——相对sweepcal的改动:
%   (1) 在线重心转向探针跟踪: 相对冻结 f̂ 的漂移由探针斜率辨识(±ucProbeDelta
%       对偶探针, 割线曲率自校正, 信赖域 rArg±0.08)——窄窗上唯一可辨识的
%       相对漂移通道; 每 hyInterfEvery 步用探针活动更新"干扰活动"记忆;
%   (2) 曲线维护更稀: 每 hyRefitEvery=60 步才冻结θ线性重解f, 双向接受
%       (联合集SSE改善>hySseMargin 且 标定块SSE不退化>0.5%), 触发条件=干扰活动;
%   (3) 维护后无论接受与否都重锚(信赖域中心=当前曲线支撑谷底)。
% 消融结论(速度包3.3/3.4): 恒定干扰下 task2式在线成立(机器简单); 漂移下
% 标定污染+无再锚定的限制是否复现, 由 run_checks/tests 如实记录(允许负结果)。
% 因果口径(红线1): 只用带噪功率+自身指令+任务参数死推航向; p 为 ctrl_view 白名单。
qs=w11.settled_q(plant,p,n);
calPsi=zeros(1,p.swSteps); calR=zeros(1,p.swSteps); calP=zeros(1,p.swSteps);
Wn=max(60,round(p.swWinMax));
rnPsi=zeros(1,Wn); rnR=zeros(1,Wn); rnP=zeros(1,Wn);
nr=0; psiUnw=0;
nUp=ceil(0.6*p.swSteps);
rSw=[linspace(p.swLo,p.swHi,nUp), linspace(p.swHi,p.swLo,p.swSteps-nUp)];
coefs=NaN(1,5); thSm=[0;0;0]; rKept=nan(1,0); rKeptCal=nan(1,0);
rStar=0.5*(p.swLo+p.swHi);
rArg=rStar;
rLo=p.swLo; rHi=p.swHi;
phase=1; calibSteps=NaN; fitRms=NaN; kStep=0; nRefit=0; r=NaN;
bEst=p.ucB0; sPrev=NaN; rPrev=NaN; gAct=false;   % 干扰活动(触发曲线维护)
rHat=nan(1,n); thEst=nan(3,n); phHist=2*ones(1,n);
while plant.count()<n
    kStep=kStep+1;
    kp=kStep-p.swSteps;
    if kStep<=p.swSteps
        r=rSw(kStep); tag='calib';
    else
        r=rStar+thSm(1)+thSm(2)*cos(psiUnw)+thSm(3)*sin(psiUnw);
        r=min(max(r,p.lower+0.02),p.upper-0.02);
        tag='infer';
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
    for j=1:sUsed
        psiUnw=psiUnw+w11.mission_speed(p,tStart+(j-0.5)*p.tEval)/p.turnRadius*p.tEval;
    end
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
    if kStep==p.swSteps
        [coefs,thSm,fitRms,rLo,rHi,rKept]=w11.fit_curve_interf(calPsi(1:kStep),...
            calR(1:kStep),calP(1:kStep),p);
        rStar=w11.curve_argmin(coefs,rLo,rHi,p,rKept);
        rArg=rStar;
        rKeptCal=rKept;
        phase=2; calibSteps=kStep;
        rPrev=rStar; sPrev=NaN;
    end
    % ---- Phase B: 探针跟踪(每 ucProbeEvery 步) + 低频曲线维护(每 hyRefitEvery 步) ----
    % (可辨识性口径: 相对冻结 f̂ 的漂移由探针斜率辨识——这是窄窗上唯一可辨识的
    %  相对漂移通道; 速度包式 δw 增量修正在本域窄窗上退化, 不采用。)
    if phase==2 && mod(kp,p.hyInterfEvery)==0 && nr>=2
        % 探针活动记忆: 最近一次探针斜率(带0.7衰减)——曲线维护的触发条件
        if nr>=2
            sNow=abs((rnP(nr-1)-rnP(nr))/(2*p.ucProbeDelta));
            gAct = max(sNow, gAct*0.7) > 0.45;
        end
    end
    if phase==2 && mod(kp,p.hyRefitEvery)==0 && nr>=30 && gAct
        psSet=[calPsi, rnPsi(1:nr)];
        rSet=[calR,   rnR(1:nr)];
        pSet=[calP,   rnP(1:nr)];
        [coefsN,~,fitRmsN,rLoN,rHiN,rKeptN]=w11.fit_curve_interf(psSet,rSet,pSet,p,thSm);
        sseOldU=w11.curve_sse(coefs,thSm,psSet,rSet,pSet,p);
        sseNewU=w11.curve_sse(coefsN,thSm,psSet,rSet,pSet,p);
        sseOldC=w11.curve_sse(coefs,thSm,calPsi,calR,calP,p);
        sseNewC=w11.curve_sse(coefsN,thSm,calPsi,calR,calP,p);
        if sseNewU < sseOldU*p.hySseMargin && sseNewC < sseOldC*1.005
            coefs=coefsN; rLo=rLoN; rHi=rHiN; fitRms=fitRmsN; rKept=rKeptN;
            rStarN=w11.curve_argmin(coefs,rLo,rHi,p,rKept);
            rStar=min(max(rStarN,rStar-0.03),rStar+0.03);   % r̂*限速(防标定污染跳变)
            nRefit=nRefit+1;
        end
        % 维护后重锚(无论接受与否): 信赖域中心=当前曲线支撑谷底(标定块样本判据)。
        rSup=rKeptCal; if isempty(rSup), rSup=rKept; end
        rArg=w11.curve_argmin(coefs,rLo,rHi,p,rSup);
        rStar=min(max(rStar,rArg-0.08),rArg+0.08);
        rStar=min(max(rStar,p.lower+0.03),p.upper-0.03);
    end
    if phase==2
        if mod(kp,p.ucProbeEvery)==2 && nr>=2
            sPair=(rnP(nr-1)-rnP(nr))/(2*p.ucProbeDelta);
            if ~isnan(sPrev) && abs(rStar-rPrev)>0.005
                bRaw=abs(sPair-sPrev)/abs(rStar-rPrev);
                bEst=max(0.05,0.8*bEst+0.2*min(bRaw,8.0));
            end
            if abs(sPair)>p.ucThr
                du=-p.ucGain*sPair/max(bEst,0.05);
                du=min(max(du,-0.02),0.02);
                rPrev=rStar;
                rStar=min(max(rStar+du,rArg-0.08),rArg+0.08);
                rStar=min(max(rStar,p.lower+0.03),p.upper-0.03);
                sPrev=sPair;
            else
                sPrev=NaN;
            end
        end
    end
    rHat(kStep)=rStar; thEst(:,kStep)=thSm; phHist(kStep)=phase;
end
while plant.count()<n
    plant.q(r,'hold'); plant.amendEstimate(r);
end
info=struct('best',r,'bestP',NaN,'mode','hybrid',...
    'rHat',rHat,'thEst',thEst,'phase',phHist,'coefs',coefs,...
    'calibSteps',calibSteps,'fitRms',fitRms,'rStar',rStar,'rLo',rLo,'rHi',rHi,...
    'thFinal',thSm,'bEst',bEst,'nRefit',nRefit);
end
