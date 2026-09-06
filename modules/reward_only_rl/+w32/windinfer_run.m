function info = windinfer_run(plant, p, n)
%WINDINFER_RUN 功率调制风矢量推断 + 闭式地速调度(任务3.2主角策略, 纯因果)。
% 任务设定(用户口径): 空速最优点 u* 已知且固定(曲线先验), 风对控制器未知;
% 控制器只有功率仪表盘(带噪)、自身指令地速、采样时间与轨迹几何。
% 原理: 转圈时航向扫过风场, 功率随航向被调制 P(ψ)=J0(|v·t̂(ψ)−w|):
%   - 曲线规整的周期波动 → 大概率恒定风(波动源于转圈时方向在变);
%   - 毛糙、前后窗解不一致 → 风在变。
% 实现: 滑动窗内二维非线性最小二乘反演 w=(wx,wy)(多起点Gauss-Newton);
%   窗长自适应: 半窗解一致(残差白)→加长窗(精度↑); 半窗解分歧→缩短窗
%   (跟踪↑), 并输出风况判定 '恒定风'/'变化风'。
% 调度: 每步用当前 ŵ 与死推航向 ψ̂ 闭式解算 v_cmd = q̂+√(q̂²+u*²−|ŵ|²),
%   q̂ = t̂·ŵ(顺风分量为正; 顺风→最优地速加大)。
% 与探针类方法(est/qnewton)的本质区别: 全程无速度dither——激励来自转圈
% 本身的航向扫描, 收敛后不付探针能耗; 且锁定后 u=|v*t̂−w|=u* 沿圆周恒定,
% 任何风估计误差都会重新引入功率调制被观测到, 构成负反馈自校正。
% 可辨识性守卫: 窗内航向累计扫角 < wiSweepMin 时不更新(保持上一解)。
% 因果口径(红线1): 只用带噪测量功率(plant.q)、自身指令序列(死推
% ψ̂'=v_cmd/R)、采样时间与有效性标志; 不读风真值/航向真值/曲线真值。
qs=w32.settled_q(plant,p,n);
% ---- 窗口尺寸按转圈周期标定(单位: 采样步数) ----
Tcirc=2*pi*p.turnRadius/max(p.optimum0,1);
Wmax=max(30,round(1.6*Tcirc/p.tEval));
Wmin=max(15,round(0.35*Tcirc/p.tEval));
W=min(max(round(0.8*Tcirc/p.tEval),Wmin),Wmax);
bufPsi=zeros(1,Wmax); bufV=zeros(1,Wmax); bufP=zeros(1,Wmax);
nb=0;                                    % 缓冲内样本数
ang=(0:7)*pi/4; mag=[1.5 3.5 6.0];       % 多起点网格: 8方向×3幅值
S=zeros(numel(ang)*numel(mag),2); ii=0;
for m=mag
    for a=ang
        ii=ii+1; S(ii,:)=[cos(a)*m, sin(a)*m];
    end
end
wSm=[0;0];                               % EMA平滑风估计(调度用)
psiUnw=0;                                % 累计(不卷绕)航向, 供扫角/三角函数
regime='初始化'; pauseGrow=0; shrinkVote=0; seLast=NaN; nDisc=0; kStep=0; v=p.initialSpeed;
windEst=nan(2,n); psiHist=nan(1,n); winHist=nan(1,n); regHist=cell(1,n);
while plant.count()<n
    kStep=kStep+1;
    % ---- 1) 闭式调度: 当前航向 + 当前风估计 → 最优地速 ----
    tx=cos(psiUnw); ty=sin(psiUnw);
    q=tx*wSm(1)+ty*wSm(2);
    disc=q^2+p.optimum0^2-(wSm(1)^2+wSm(2)^2);
    if disc>0, v=q+sqrt(disc); else, v=max(q,0); nDisc=nDisc+1; end
    v=min(max(v,p.lower+0.3),p.upper-0.3);
    % ---- 2) 指令就位查询(时延+限幅一致规则), 指令死推航向 ----
    c0=plant.count();
    Pm=qs(v,'infer');
    if ~isfinite(Pm), kStep=kStep-1; break; end
    sUsed=plant.count()-c0;
    for j=1:sUsed
        psiUnw=psiUnw+v/p.turnRadius*p.tEval;
    end
    % ---- 3) 测量入滑动窗(指令地速+死推航向+带噪功率) ----
    if nb<Wmax
        nb=nb+1;
    else
        bufPsi(1:end-1)=bufPsi(2:end); bufV(1:end-1)=bufV(2:end);
        bufP(1:end-1)=bufP(2:end);
    end
    bufPsi(nb)=psiUnw; bufV(nb)=v; bufP(nb)=Pm;
    % ---- 4) 窗内二维NLS反演风矢量(每步, 便宜) ----
    wUse=min(nb,W); i0=nb-wUse+1; idx=i0:nb;
    sweep=psiUnw-bufPsi(i0);
    if wUse>=Wmin && sweep>=p.wiSweepMin
        [wNew,se,ok]=fitWind(idx,S);
        if ok
            seLast=se;
            wSm=p.wiEwma*wNew+(1-p.wiEwma)*wSm;
        end
    end
    % ---- 5) 半窗一致性 → 窗长自适应 + 风况判定(每5步) ----
    if mod(kStep,5)==0 && wUse>=2*Wmin && sweep>=2*p.wiSweepMin
        iMid=i0+floor(wUse/2);
        if (bufPsi(iMid-1)-bufPsi(i0))>=0.5*p.wiSweepMin
            [w1,se1,ok1]=fitWind(i0:iMid-1,wSm.');
            [w2h,se2,ok2]=fitWind(iMid:nb,wSm.');
            if ok1 && ok2
                dW=norm(w2h-w1);
                % 显著性门槛: 两半窗各自协方差合成, 3σ显著 + 模型失配地板。
                thr=max(0.35, 3.0*sqrt(se1^2+se2^2));
                if ~isfinite(thr), thr=0.60; end
                if dW>thr
                    shrinkVote=shrinkVote+1;     % 连续两票才缩窗(抗噪)
                else
                    shrinkVote=0;
                end
                if shrinkVote>=2
                    W=max(Wmin,round(0.7*W));    % 风在变: 缩窗提跟踪
                    regime='变化风';
                    pauseGrow=round(0.5*Tcirc/p.tEval);
                    shrinkVote=0;
                else
                    if shrinkVote==0, regime='恒定风'; end
                    if pauseGrow<=0 && shrinkVote==0
                        W=min(Wmax,round(1.15*W));   % 风恒定: 加窗提精度
                    else
                        pauseGrow=pauseGrow-5;
                    end
                end
            end
        end
    end
    % ---- 6) 记录 ----
    windEst(:,kStep)=wSm; psiHist(kStep)=mod(psiUnw,2*pi);
    winHist(kStep)=W; regHist{kStep}=regime;
end
while plant.count()<n                    % 末段预算兜底
    plant.q(v,'hold'); plant.amendEstimate(v);
end
info=struct('best',v,'bestP',NaN,'mode','windinfer',...
    'windEst',windEst,'psiHat',psiHist,'window',winHist,...
    'regime',{regHist},'nDisc',nDisc,'windStd',seLast);

    function [w,se,ok]=fitWind(idxSet,starts)
        % 滑动窗非线性最小二乘: min Σ(P_i − J0(|v_i·t̂_i − w|))²。
        % 多起点Gauss-Newton; 返回最优解、风估计标准差(窗内协方差)与可行性。
        ps=bufPsi(idxSet); vv=bufV(idxSet); Pm=bufP(idxSet);
        ps=ps(:); vv=vv(:); Pm=Pm(:);        % 统一列向量(高斯-牛顿按列堆叠)
        cx=vv.*cos(ps); cy=vv.*sin(ps);
        bestSse=Inf; w=[0;0]; ok=false; se=NaN;
        for sIdx=1:size(starts,1)
            w2=starts(sIdx,:).';
            for it=1:5
                rx=cx-w2(1); ry=cy-w2(2);
                u=max(hypot(rx,ry),0.3);
                g=w32.base_curve_grad(u,p);          % dP/du
                J=[g.*(-rx./u), g.*(-ry./u)];        % dP/dw
                e=Pm-w32.base_curve(u,p);
                ds=(J.'*J+1e-9*eye(2))\(J.'*e);
                w2=w2+ds;
                if max(abs(ds))<1e-4, break; end
            end
            w2=min(max(w2,-12),12);
            rx=cx-w2(1); ry=cy-w2(2);
            u=max(hypot(rx,ry),0.3);
            e=Pm-w32.base_curve(u,p);
            sse=sum(e.^2);
            if sse<bestSse
                bestSse=sse; w=w2; ok=true;
                g=w32.base_curve_grad(u,p);
                JB=[g.*(-rx./u), g.*(-ry./u)];
                s2=bestSse/max(numel(idxSet)-2,1);
                A=(JB.'*JB+1e-9*eye(2))\eye(2);
                se=sqrt(max(s2*trace(A)/2,0));
            end
        end
    end
end
