function info = sweepcal_run(plant, p, n)
%SWEEPCAL_RUN 全速度域快扫标定 + 在线精化(任务3.4主角策略, 纯因果, 曲线未知)。
% 用户建议(工作包1口径): 首飞架次全速度域快速采样(3→12 m/s)建立初始能耗模型,
% 而非仅依赖单一速度点。本策略:
% Phase A 标定(前 swSteps 步): 速度双向扫(上行3→12约90步+下行12→3约60步,
% 航向错开约0.7圈), 转圈继续; 采集
%   (死推航向ψ̂, 指令地速v, 带噪功率P)样本, 联合辨识
%     min_{f,w} Σ (P_i − f(|v_i·t̂_i − w|))²,  f = 四次多项式(归一化基, 5系数),
%   内层: 固定 w 时 f 线性最小二乘; 外层: 对 w 多起点数值下降(8方向×3幅值网格)。
%   联合辨识是必须的: 风把地速-功率关系畸变(顺风/逆风段错位), 只拟合 P~v 会把
%   风的投影误当曲线形状。标定结束得 f̂、空速最优点 û*=argmin f̂、风估计 ŵ。
%   û* 只在"样本覆盖的 u 范围"内搜索——多项式绝不做外推(外推区可任意下潜)。
% Phase B 在线精化(其余预算):
%   - 每步闭式调度 v_cmd = q̂+sqrt(q̂²+û*²−|ŵ|²), q̂=t̂·ŵ(顺风为正);
%   - 每 swRefitEvery 步重做联合拟合, 样本集 = 标定块(永久保留, 锚定全局形状)
%     + 最近窗口(跟踪缓变);
%   - 每 ucProbeEvery 步一对 ±ucProbeDelta 探针(上下交替), 由功率差斜率做
%     牛顿式微调 û*; 曲率 b 由探针历史割线自校正, 斜率低于噪声门限 ucThr 不更新。
% 因果口径(红线1): 只用带噪功率+自身指令(航向死推 ψ̂'=v_cmd/R)+tEval;
% p 为 ctrl_view 白名单——不含曲线形状/最优点u*/风/噪声任何真值。
qs=w34.settled_q(plant,p,n);
% 标定块(永久) + 最近窗口(环形)
calPsi=zeros(1,p.swSteps); calV=zeros(1,p.swSteps); calP=zeros(1,p.swSteps);
Wn=max(60,round(p.swWinMax));
rnPsi=zeros(1,Wn); rnV=zeros(1,Wn); rnP=zeros(1,Wn);
nr=0; psiUnw=0;
% 双向扫: 上行(60%步数)+下行(40%步数)——同一速度在不同航向各出现一次。
% 单向斜坡的样本是"速度×航向"一维流形(速度与航向被斜坡绑定), 风与曲线在该
% 集合上不可辨识(会落进退化盆地); 双向扫恢复二维覆盖。
nUp=ceil(0.6*p.swSteps);
vSw=[linspace(p.swLo,p.swHi,nUp), linspace(p.swHi,p.swLo,p.swSteps-nUp)];
coefs=NaN(1,5); wSm=[0;0]; uKept=nan(1,0); uKeptCal=nan(1,0);
uStar=0.5*(p.swLo+p.swHi);            % 初值=扫描区间中点(无任何先验)
uArg=uStar;                           % 当前曲线的支撑谷底(探针信赖域中心)
uLo=p.swLo; uHi=p.swHi;               % argmin 允许的 u 范围(随拟合集更新)
phase=1; calibSteps=NaN; fitRms=NaN; kStep=0; nDisc=0; v=NaN;
bEst=p.ucB0; sPrev=NaN; uPrev=NaN;
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
        tag='refine';
        % ---- 探针对(上下交替): 每 ucProbeEvery 步占2步 ----
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
    % (2026-09-08: 删去半程预热拟合——半程只有单向扫样本, 速度×航向一维流形上
    %  (f,w)不可辨识, 其argmin是垃圾且只污染显示; 曲线在标定完成时一次出炉。)
    if kStep==p.swSteps
        [coefs,wSm,fitRms,uLo,uHi,uKept]=w34.fit_curve_wind(calPsi(1:kStep),...
            calV(1:kStep),calP(1:kStep),p);
        uStar=w34.curve_argmin(coefs,uLo,uHi,p,uKept);
        uArg=uStar;
        uKeptCal=uKept;               % 标定块样本u(全域覆盖, 谷底支撑判据永久用它——
                                      % 近期窗会被"当前飞在哪"污染, 用它选谷底会自我确认)
        if kStep==p.swSteps
            phase=2; calibSteps=kStep;
            uPrev=uStar; sPrev=NaN;
        end
    end
    % ---- Phase B: 风修正(每10步) + 曲线重拟合(每20步) + 探针更新 û* ----
    % (注: 曾试"固定f̂每步精化w", 实测有害——f̂的多项式形状偏差会被w去补偿,
    %  拖偏风估计; 折中为每10步、120样本窗口的3参数修正(δw+c0, c0吸收形状偏差)。)
    if phase==2 && mod(kStep,p.swRefitEvery)==0 && nr>=30
        % (1) 风误差在线修正(3参数δw+c0, 2.1机制移植): 标定的虚假风/漂移
        %     会以每圈一次的功率调制自我暴露, 全窗口可观测并扣除。
        [dwC,~]=w34.wind_corr(rnPsi(1:nr),rnV(1:nr),rnP(1:nr),coefs,wSm,p);
        wSm=wSm+0.8*dwC;
    end
    if phase==2
        if mod(kStep,p.swRefitEvery)==0 && nr>=30
            psSet=[calPsi, rnPsi(1:nr)];
            vSet=[calV,   rnV(1:nr)];
            pSet=[calP,   rnP(1:nr)];
            % (2) 曲线重拟合(冻结w: 固定w后线性最小二乘唯一, 稳定不跳变)
            [coefsN,~,fitRmsN,uLoN,uHiN,uKeptN]=w34.fit_curve_wind(psSet,vSet,pSet,p,wSm);
            sseOld=w34.curve_sse(coefs,wSm,psSet,vSet,pSet);
            sseNew=w34.curve_sse(coefsN,wSm,psSet,vSet,pSet);
            if sseNew < sseOld*0.999
                coefs=coefsN; uLo=uLoN; uHi=uHiN; fitRms=fitRmsN; uKept=uKeptN;
                end
            uSup=uKeptCal; if isempty(uSup), uSup=uKeptN; end
            uStar=w34.curve_argmin(coefs,uLo,uHi,p,uSup);
            uArg=uStar;
        end
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
                % 探针信赖域(2026-09-08): û*只允许在当前曲线支撑谷底uArg±1.5内——
                % 湍流/涟漪的假斜率会把无界探针拖到12并自我确认(实测B=2.5复合风
                % 12种子全部中招); 局部微调交给探针, 大幅修正只能来自重拟合argmin。
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
info=struct('best',v,'bestP',NaN,'mode','sweepcal',...
    'uHat',uHat,'windEst',wEst,'phase',phHist,'coefs',coefs,...
    'calibSteps',calibSteps,'fitRms',fitRms,'uStar',uStar,'uLo',uLo,'uHi',uHi,...
    'windFinal',wSm,'nDisc',nDisc,'bEst',bEst);

end
