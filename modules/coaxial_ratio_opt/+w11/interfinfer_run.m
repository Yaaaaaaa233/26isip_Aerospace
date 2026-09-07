function info = interfinfer_run(plant, p, n)
%INTERFINFER_RUN 干扰场滑窗NLS反演 + 闭式桨比调度(已知曲线, oracle参照)。
% windinfer_run 的桨比域移植: 曲线先验已知(f=truth的控制器侧副本), 干扰场
% δ̂(ψ,t)=a0+a1·cosψ+b1·sinψ 未知——由功率随航向的调制反推(转圈本身提供激励,
% 无探针成本); 收敛后 r=0.89·先验+r̂*+δ̂(ψ) 使工作点贴住真值谷底, 任何干扰估计
% 误差都会重新引入功率偏移被观测到, 构成负反馈自校正。
% 可辨识性守卫: 窗内航向累计扫角 < ifSweepMin 时不更新(保持上一解)。
% 注意: 依赖已知曲线 → oracle 参照(评价侧), 不参与因果黑箱横比(红线1口径)。
qs=w11.settled_q(plant,p,n);
Tcirc=2*pi*p.turnRadius/max(p.fwdSpeed,1);
Wmax=max(30,round(1.6*Tcirc/p.tEval));
Wmin=max(15,round(0.35*Tcirc/p.tEval));
W=min(max(round(0.8*Tcirc/p.tEval),Wmin),Wmax);
bufPsi=zeros(1,Wmax); bufR=zeros(1,Wmax); bufP=zeros(1,Wmax);
nb=0;
% 多起点: a0 网格 ×(a1,b1)=0 + 少量谐波角点
S=[linspace(-0.06,0.06,5); zeros(2,5)].';
S=[S; [-0.02 0.02 -0.02 0.02; 0 0 0 0; -0.02 -0.02 0.02 0.02].'];
thSm=[0;0;0];
psiUnw=0;
regime='初始化'; pauseGrow=0; shrinkVote=0; seLast=NaN; kStep=0; r=p.openLoopR;
thEst=nan(3,n); psiHist=nan(1,n); winHist=nan(1,n); regHist=cell(1,n);
regHist(:)={'初始化'};
while plant.count()<n
    kStep=kStep+1;
    % ---- 1) 闭式调度: r = rStar0(曲线先验谷底) + δ̂(ψ̂) ----
    r=p.rStar0+thSm(1)+thSm(2)*cos(psiUnw)+thSm(3)*sin(psiUnw);
    r=min(max(r,p.lower+0.02),p.upper-0.02);
    % ---- 2) 指令就位查询, 任务参数死推航向 ----
    c0=plant.count();
    Pm=qs(r,'infer');
    if ~isfinite(Pm), kStep=kStep-1; break; end
    sUsed=plant.count()-c0;
    tStart=(plant.count()-sUsed)*p.tEval;
    for j=1:sUsed
        psiUnw=psiUnw+w11.mission_speed(p,tStart+(j-0.5)*p.tEval)/p.turnRadius*p.tEval;
    end
    % ---- 3) 测量入滑动窗 ----
    if nb<Wmax
        nb=nb+1;
    else
        bufPsi(1:end-1)=bufPsi(2:end); bufR(1:end-1)=bufR(2:end);
        bufP(1:end-1)=bufP(2:end);
    end
    bufPsi(nb)=psiUnw; bufR(nb)=r; bufP(nb)=Pm;
    % ---- 4) 窗内三维NLS反演 θ(每步, 便宜) ----
    wUse=min(nb,W); i0=nb-wUse+1; idx=i0:nb;
    sweep=psiUnw-bufPsi(i0);
    if wUse>=Wmin && sweep>=p.ifSweepMin
        [thNew,se,ok]=fitTheta(idx,S);
        if ok
            seLast=se;
            thSm=p.ifEwma*thNew+(1-p.ifEwma)*thSm;
        end
    end
    % ---- 5) 半窗一致性 → 窗长自适应 + 干扰况判定(每5步) ----
    if mod(kStep,5)==0 && wUse>=2*Wmin && sweep>=2*p.ifSweepMin
        iMid=i0+floor(wUse/2);
        if (bufPsi(iMid-1)-bufPsi(i0))>=0.5*p.ifSweepMin
            [t1,se1,ok1]=fitTheta(i0:iMid-1,thSm.');
            [t2,se2,ok2]=fitTheta(iMid:nb,thSm.');
            if ok1 && ok2
                dTh=norm(t2-t1);
                thr=max(0.01, 3.0*sqrt(se1^2+se2^2));
                if ~isfinite(thr), thr=0.02; end
                if dTh>thr
                    shrinkVote=shrinkVote+1;
                else
                    shrinkVote=0;
                end
                if shrinkVote>=2
                    W=max(Wmin,round(0.7*W));
                    regime='漂移干扰';
                    pauseGrow=round(0.5*Tcirc/p.tEval);
                    shrinkVote=0;
                else
                    if shrinkVote==0, regime='恒定干扰'; end
                    if pauseGrow<=0 && shrinkVote==0
                        W=min(Wmax,round(1.15*W));
                    else
                        pauseGrow=pauseGrow-5;
                    end
                end
            end
        end
    end
    % ---- 6) 记录 ----
    thEst(:,kStep)=thSm; psiHist(kStep)=mod(psiUnw,2*pi);
    winHist(kStep)=W; regHist{kStep}=regime;
end
while plant.count()<n
    plant.q(r,'hold'); plant.amendEstimate(r);
end
info=struct('best',r,'bestP',NaN,'mode','interfinfer',...
    'thEst',thEst,'psiHat',psiHist,'window',winHist,...
    'regime',{regHist},'thStd',seLast);

    function [th,se,ok]=fitTheta(idxSet,starts)
        % 滑动窗非线性最小二乘: min Σ(P_i − f0(r_i − θ·[1,cosψ,sinψ]'))²。
        % f0 = 已知曲线先验(评价侧全量config, oracle参照); 多起点Gauss-Newton。
        ps=bufPsi(idxSet); rr=bufR(idxSet); Pm=bufP(idxSet);
        ps=ps(:); rr=rr(:); Pm=Pm(:);
        bestSse=Inf; th=[0;0;0]; ok=false; se=NaN;
        for sIdx=1:size(starts,1)
            th2=starts(sIdx,:).';
            for it=1:5
                u=max(rr-(th2(1)+th2(2)*cos(ps)+th2(3)*sin(ps)),0.76);
                g=w11.truth_curve_grad(min(max(u,p.lower+0.005),p.upper-0.005),p); % dP/du
                e=Pm-w11.truth_curve(min(max(u,p.lower+0.005),p.upper-0.005),p);
                J=g.*[-ones(size(u)), -cos(ps), -sin(ps)];       % dP/dθ
                ds=(J.'*J+1e-9*eye(3))\(J.'*e);
                th2=th2+ds;
                if max(abs(ds))<1e-6, break; end
            end
            th2=[min(max(th2(1),-0.15),0.15); min(max(th2(2),-0.10),0.10); min(max(th2(3),-0.10),0.10)];
            u=min(max(rr-(th2(1)+th2(2)*cos(ps)+th2(3)*sin(ps)),0.76),1.24);
            uc=min(max(u,p.lower+0.005),p.upper-0.005);
            e=Pm-w11.truth_curve(uc,p);
            sse=sum(e.^2);
            if sse<bestSse
                bestSse=sse; th=th2; ok=true;
                g=w11.truth_curve_grad(uc,p);
                JB=g.*[-ones(size(uc)), -cos(ps), -sin(ps)];
                s2=bestSse/max(numel(idxSet)-3,1);
                A=(JB.'*JB+1e-9*eye(3))\eye(3);
                se=sqrt(max(s2*trace(A)/3,0));
            end
        end
    end
end
