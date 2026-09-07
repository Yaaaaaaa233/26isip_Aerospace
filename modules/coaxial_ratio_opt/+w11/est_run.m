function info = est_run(plant, p, n)
%EST_RUN 已知曲线 + 3状态EKF跟踪干扰场(模型法策略, oracle参照)。
% est_run 的桨比域移植: 状态 x=[a0;a1;b1] (δ̂(ψ)=x'[1,cosψ,sinψ]'), 随机游走模型,
% 内部模型 f0=已知曲线(评价侧全量config), 新息 Huber 降权, 增量限幅。
% 调度: r = rStar0 + δ̂(ψ̂) + 交替dither(±estDither, 激励来源)。
% 注意: 依赖已知曲线 → oracle 参照(评价侧), 不参与因果黑箱横比。
qs=w11.settled_q(plant,p,n);
x=[0;0;0]; Pp=diag([0.01 0.005 0.005]);
Reff=(p.estRmis)^2;                          % 噪声+失配底噪
Qa=p.estQa;
Q=Qa*eye(3)*p.tEval;
I3=eye(3);
psiHat=0; kStep=0; rCmd=p.rStar0;
thHist=nan(3,n);
while plant.count()<n
    kStep=kStep+1;
    % ---- 预测步 ----
    th=x;
    th(1)=min(max(th(1),-0.15),0.15);
    th(2:3)=min(max(th(2:3),-0.10),0.10);
    rHat0=p.rStar0+th(1)+th(2)*cos(psiHat)+th(3)*sin(psiHat);
    rCmd=min(max(rHat0,p.lower+0.02),p.upper-0.02);
    dith=p.estDither*(1-2*mod(kStep,2));
    % ---- 指令就位查询, 任务参数死推航向 ----
    c0=plant.count();
    PmNew=qs(rCmd+dith,'est');
    sUsed=plant.count()-c0;
    if ~isfinite(PmNew), break; end
    tStart=(plant.count()-sUsed)*p.tEval;
    for j=1:sUsed
        psiHat=mod(psiHat+w11.mission_speed(p,tStart+(j-0.5)*p.tEval)/p.turnRadius*p.tEval,2*pi);
    end
    % ---- EKF更新步: P ≈ f0(r − δ̂(ψ)), Huber降权新息 ----
    rU=rCmd+dith;
    u=min(max(rU-(th(1)+th(2)*cos(psiHat)+th(3)*sin(psiHat)),p.lower+0.005),p.upper-0.005);
    h=w11.truth_curve(u,p);
    dJ=w11.truth_curve_grad(u,p);
    H3=dJ*[-1, -cos(psiHat), -sin(psiHat)];
    S=H3*Pp*H3.'+Reff;
    K=Pp*H3.'/S;
    innov=PmNew-h;
    w=1; ar=abs(innov)/sqrt(S);
    if ar>2.5, w=2.5/ar; end                 % Huber: 大新息线性降权不拒绝
    dx=K*(innov*w);
    dx=min(max(dx,-p.estStepClamp),p.estStepClamp);
    x=x+dx;
    x(1)=min(max(x(1),-0.15),0.15);
    x(2:3)=min(max(x(2:3),-0.10),0.10);
    Pp=(I3-K*H3)*Pp; Pp=(Pp+Pp.')/2;
    thHist(:,kStep)=x;
end
while plant.count()<n
    plant.q(rCmd,'hold'); plant.amendEstimate(rCmd);
end
info=struct('best',rCmd,'bestP',NaN,'thEst',x,'steps',kStep,...
    'mode','est','thHist',{thHist});
end
