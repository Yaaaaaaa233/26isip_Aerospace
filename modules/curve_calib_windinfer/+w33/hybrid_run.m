function info = hybrid_run(plant, p, n)
%HYBRID_RUN 任务3.3主角(消融实验)：首飞全速域标定 + task2式在线(冻结曲线, 风修正+信赖域探针)。
% 动机(用户口径, 2026-09-07): "先通过首飞全飞拟合速度-功率曲线, 然后用task2的算法"
% ——把在线算力的重心从"重新学曲线"(task3)移到"跟踪风"(task2)。本策略是该设想的
% 最忠实实现, 任务3.3即"标定后在线该用什么"的受控消融实验(结论见文末与README):
% Phase A 标定(前 swSteps 步, 与sweepcal完全一致): 速度双向斜坡扫(上行约60%+
%   下行约40%, 航向错开约0.7圈), 联合辨识
%     min_{f,w} Σ (P_i − f(|v_i·t̂_i − w|))²,  f = 四次多项式(归一化基);
%   û*=argmin f̂ 只在样本覆盖的u范围内搜索(禁止外推)。
% Phase B 在线(其余预算)——相对sweepcal的改动:
%   (1) 风修正更细: 每10步( sweepcal每20步)做 wind_corr 增量风修正(3参数δw+c0,
%       2.1"功率调制反推风"的增量形式); c0吸收f̂形状偏差, w只吃航向调制信息。
%   (2) 曲线维护更稀: 每 hyRefitEvery=60 步( sweepcal每20步)才冻结w线性重解f,
%       双向接受(联合集SSE改善>hySseMargin 且 标定块SSE不退化>0.5%)。
%   (3) 探针锚加**标定信赖域**(û*限制在标定argmin±1.5 m/s): 本对象族曲线物理
%       固定, û*漂移只能是估计失败。
% 消融结论(2026-09-07, 证据见README调参史与run_task33_checks):
%   恒定风/零风: 冻结曲线在线成立——2.35%/2.80%(sweepcal 1.91%, 差距=维护机器
%   的简单性代价), 用户设想在风不漂移时可用;
%   变风: **不成立**(11-14%, 劣于开环4.8%)——机理: 变风污染首飞标定(Phase A的
%   argmin本身落在12-15), 冻结曲线后û*没有可靠的再锚定, 信赖域中心即错;
%   sweepcal靠每20步重拟合argmin持续再锚定才稳定(其uHat轨迹同样甩到14.5再回)。
%   即: "标定后在线用task2还是task3"的答案——恒定风用task2式(本策略, 更简单),
%   变风必须继续task3式(sweepcal机器或RL)。
% 因果口径(红线1): 只用带噪功率+自身指令死推航向(ψ̂'=v_cmd/R)+采样时间;
% 曲线知识来自自己的标定拟合(非对象真值); p 为 ctrl_view 白名单。
qs=w33.settled_q(plant,p,n);
% 标定块(永久) + 最近窗口(环形)
calPsi=zeros(1,p.swSteps); calV=zeros(1,p.swSteps); calP=zeros(1,p.swSteps);
Wn=max(60,round(p.swWinMax));
rnPsi=zeros(1,Wn); rnV=zeros(1,Wn); rnP=zeros(1,Wn);
nr=0; psiUnw=0;
nUp=ceil(0.6*p.swSteps);
vSw=[linspace(p.swLo,p.swHi,nUp), linspace(p.swHi,p.swLo,p.swSteps-nUp)];
coefs=NaN(1,5); wSm=[0;0]; uKept=nan(1,0); uKeptCal=nan(1,0);
uStar=0.5*(p.swLo+p.swHi);            % 初值=扫描区间中点(无任何先验)
uArg=uStar;                           % 当前曲线的支撑谷底(探针信赖域中心)
uLo=p.swLo; uHi=p.swHi;               % argmin 允许的 u 范围(随拟合集更新)
phase=1; calibSteps=NaN; fitRms=NaN; kStep=0; nDisc=0; nRefit=0; v=NaN;
bEst=p.ucB0; sPrev=NaN; uPrev=NaN; wAct=false;   % 风活动(触发曲线维护)
uHat=nan(1,n); wEst=nan(2,n); phHist=2*ones(1,n);
while plant.count()<n
    kStep=kStep+1;
    kp=kStep-p.swSteps;                % 相对标定结束的步数(Phase B用)
    if kStep<=p.swSteps
        v=vSw(kStep); tag='calib';     % Phase A: 全速度域斜坡扫
    else
        % ---- Phase B: 闭式调度 ----
        tx=cos(psiUnw); ty=sin(psiUnw);
        q=tx*wSm(1)+ty*wSm(2);
        disc=q^2+uStar^2-(wSm(1)^2+wSm(2)^2);
        if disc>0, v=q+sqrt(disc); else, v=max(q,0); nDisc=nDisc+1; end
        v=min(max(v,p.lower+0.3),p.upper-0.3);
        tag='infer';
        % ---- 探针对(上下交替, û*的测量锚): 每 ucProbeEvery 步占2步 ----
        sgn=(-1)^floor(kp/p.ucProbeEvery);
        if mod(kp,p.ucProbeEvery)==1
            v=min(max(v+sgn*p.ucProbeDelta,p.lower+0.3),p.upper-0.3); tag='probe';
        elseif mod(kp,p.ucProbeEvery)==2
            v=min(max(v-sgn*p.ucProbeDelta,p.lower+0.3),p.upper-0.3); tag='probe';
        end
    end
    c0=plant.count();
    Pm=qs(v,tag);
    if ~isfinite(Pm), kStep=kStep-1; break; end
    sUsed=plant.count()-c0;
    for j=1:sUsed
        psiUnw=psiUnw+v/p.turnRadius*p.tEval;
    end
    % ---- 样本入库 ----
    if kStep<=p.swSteps
        calPsi(kStep)=psiUnw; calV(kStep)=v; calP(kStep)=Pm;
    end
    if phase==2
        if nr<Wn, nr=nr+1;
        else
            rnPsi(1:end-1)=rnPsi(2:end); rnV(1:end-1)=rnV(2:end);
            rnP(1:end-1)=rnP(2:end);
        end
        rnPsi(nr)=psiUnw; rnV(nr)=v; rnP(nr)=Pm;
    end
    % ---- Phase A 标定点: 全程正式拟合 ----
    % (2026-09-08: 删去半程预热拟合——半程只有单向扫样本, (f,w)不可辨识,
    %  其argmin是垃圾且只污染显示; 曲线在标定完成时一次出炉。)
    if kStep==p.swSteps
        [coefs,wSm,fitRms,uLo,uHi,uKept]=w33.fit_curve_wind(calPsi(1:kStep),...
            calV(1:kStep),calP(1:kStep),p);
        uStar=w33.curve_argmin(coefs,uLo,uHi,p,uKept);
        uArg=uStar;
        uKeptCal=uKept;               % 标定块样本u(全域覆盖, 谷底支撑判据永久用它)
        if kStep==p.swSteps
            phase=2; calibSteps=kStep;
            uPrev=uStar; sPrev=NaN;
        end
    end
    % ---- Phase B: 增量风修正(每10步) + 低频曲线维护(每hyRefitEvery步) ----
    if phase==2 && mod(kp,p.hyWindEvery)==0 && nr>=30
        % (1) 增量风修正(δw+c0, task2机制): 虚假风以每圈一次的功率调制自我暴露
        [dwC,~]=w33.wind_corr(rnPsi(1:nr),rnV(1:nr),rnP(1:nr),coefs,wSm,p);
        wSm=wSm+0.8*dwC;
        % 风活动记忆: 最近一次修正幅值(带0.7衰减)——曲线维护的触发条件
        wAct = max(norm(dwC), wAct*0.7) > 0.30;
    end
    if phase==2 && mod(kp,p.hyRefitEvery)==0 && nr>=30 && wAct
        % (2) 低频曲线维护(冻结w线性重解f), 触发条件=风活动(2026-09-08定稿):
        %     曲线本身不随时间变, 唯一时变的是风——风不动时重拟合只会拟合噪声
        %     (û*游走1.2-1.6, 实测), 风在动时重拟合才能适配新风。
        %     接受判据(双向): (a)联合集SSE改善>hySseMargin(真信号);
        %     (b)标定块SSE不退化>0.5%(不丢标定锚)。
        %     û*限速: 每次维护最多移动0.8 m/s(防变风初期标定污染导致的跳变)。
        psSet=[calPsi, rnPsi(1:nr)];
        vSet=[calV,   rnV(1:nr)];
        pSet=[calP,   rnP(1:nr)];
        [coefsN,~,fitRmsN,uLoN,uHiN,uKeptN]=w33.fit_curve_wind(psSet,vSet,pSet,p,wSm);
        sseOldU=w33.curve_sse(coefs,wSm,psSet,vSet,pSet);
        sseNewU=w33.curve_sse(coefsN,wSm,psSet,vSet,pSet);
        sseOldC=w33.curve_sse(coefs,wSm,calPsi,calV,calP);
        sseNewC=w33.curve_sse(coefsN,wSm,calPsi,calV,calP);
        if sseNewU < sseOldU*p.hySseMargin && sseNewC < sseOldC*1.005
            coefs=coefsN; uLo=uLoN; uHi=uHiN; fitRms=fitRmsN; uKept=uKeptN;
            uStarN=w33.curve_argmin(coefs,uLo,uHi,p,uKept);
            uStar=min(max(uStarN,uStar-0.8),uStar+0.8);   % û*限速
            nRefit=nRefit+1;
        end
        % 维护后重锚(2026-09-08, 无论接受与否): 信赖域中心=当前曲线的支撑谷底。
        % 支撑判据用标定块样本(近期窗会被"当前飞在哪"污染, 用它选谷底会自我确认)。
        % 旧版只在接受时才动û*且探针无界——维护被拒期间假斜率能把û*拖到12
        % (实测紫星在12而曲线谷底在6.3); 现在±1.5信赖域+支撑谷底选择双保险。
        uSup=uKeptCal; if isempty(uSup), uSup=uKept; end
        uArg=w33.curve_argmin(coefs,uLo,uHi,p,uSup);
        uStar=min(max(uStar,uArg-1.5),uArg+1.5);
        uStar=min(max(uStar,p.lower+0.5),p.upper-1);
    end
    if phase==2
        % ---- 探针更新 û*(每 ucProbeEvery 步, 与sweepcal同款) ----
        if mod(kp,p.ucProbeEvery)==2 && nr>=2
            sPair=(rnP(nr-1)-rnP(nr))/(2*p.ucProbeDelta);  % +δ采样在nr-1
            if ~isnan(sPrev) && abs(uStar-uPrev)>0.05
                bRaw=abs(sPair-sPrev)/abs(uStar-uPrev);
                bEst=max(0.004,0.8*bEst+0.2*min(bRaw,0.5));
            end
            if abs(sPair)>p.ucThr
                du=-p.ucGain*sPair/max(bEst,0.004);
                du=min(max(du,-0.4),0.4);
                uPrev=uStar;
                % 探针信赖域(2026-09-08): û*只允许在当前曲线支撑谷底uArg±1.5内。
                % 3.3曾用"标定argmin±1.5"——变风下标定argmin可被污染, 中心即错;
                % 现在中心是随维护刷新的当前曲线支撑谷底, 局部微调交给探针,
                % 大幅修正只能来自重拟合(与sweepcal同款双保险)。
                uStar=min(max(uStar+du,uArg-1.5),uArg+1.5);
                uStar=min(max(uStar,p.lower+0.5),p.upper-1);
                sPrev=sPair;
            else
                sPrev=NaN;   % 噪声门限以下: 不更新也不累积割线
            end
        end
    end
    uHat(kStep)=uStar; wEst(:,kStep)=wSm; phHist(kStep)=phase;
end
while plant.count()<n
    plant.q(v,'hold'); plant.amendEstimate(v);
end
info=struct('best',v,'bestP',NaN,'mode','hybrid',...
    'uHat',uHat,'windEst',wEst,'phase',phHist,'coefs',coefs,...
    'calibSteps',calibSteps,'fitRms',fitRms,'uStar',uStar,'uLo',uLo,'uHi',uHi,...
    'windFinal',wSm,'nDisc',nDisc,'bEst',bEst,'nRefit',nRefit);
end
