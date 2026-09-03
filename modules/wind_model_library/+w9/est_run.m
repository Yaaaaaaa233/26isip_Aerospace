function info = est_run(plant, p, n)
%EST_RUN 在线风EKF估计 + 解析调度跟踪(模型法策略, 任务7新增)。
% 原理: 用额定功率曲线形状作内部模型, 4状态EKF x=[wx;wy;dwx;dwy] 在线估计
% 风矢量与风趋势, 按解析调度 v_cmd = −q̂ + sqrt(q̂² + V*² − |θ̂|²) 直接解算
% 当前最优速度(技术路线§3公式)。背景: 实际半径(50-150 m)下最优快速漂移,
% 宽行程探针法带宽不足(见验收横比); 模型法的带宽由估计收敛速度决定,
% 趋势状态外推补偿估计滞后。
% 收敛鲁棒性(吸取的教训, 见开发记录):
%   a) 完整J0含涟漪建模——涟漪斜率是u≈V*附近的主要信息来源;
%   b) R_eff取"噪声+模型失配底噪"(步均值测量 vs 步末状态、死推航向误差),
%      新息用Huber降权(2.5σ)而非硬门限——硬门限+协方差膨胀会进入
%      "拒绝→膨胀→大增益→拍边"的恶性循环(实测算θ̂拍投影边界的教训);
%   c) 每步风增量限幅, |θ̂|<V*投影, 趋势限幅。
% 激励=指令上的小幅交替dither(estDither)。
% 因果口径(红线1): 只接收带噪测量功率与自身指令; 航向不读对象内部状态,
% 由指令死推重建 ψ̂' = v_cmd/R(与真航向仅差执行暂态的小漂移)。
qs=w9.settled_q(plant,p,n);
x=[0;0;0;0]; Pp=diag([1 1 0.04 0.04]);
Reff=(p.estRmis)^2;                          % 噪声+失配底噪
Qa=p.estQa;
F=[1 0 p.tEval 0; 0 1 0 p.tEval; 0 0 1 0; 0 0 0 1];
Q=Qa*[p.tEval^4/4 0 p.tEval^3/2 0; 0 p.tEval^4/4 0 p.tEval^3/2;...
      p.tEval^3/2 0 p.tEval^2 0; 0 p.tEval^3/2 0 p.tEval^2];
I4=eye(4);
psiHat=0; kStep=0; vCmd=p.optimum0; vHat=p.optimum0;
thetaHist=zeros(0,2);
while plant.count()<n
    kStep=kStep+1;
    % ---- 预测步 ----
    x=F*x; Pp=F*Pp*F.'+Q;
    theta=x(1:2);
    nm=hypot(theta(1),theta(2));
    if nm>p.optimum0*0.99, theta=theta*(p.optimum0*0.99/nm); end
    qHat=cos(psiHat)*theta(1)+sin(psiHat)*theta(2);
    w2Hat=theta(1)^2+theta(2)^2;
    disc=qHat^2+p.optimum0^2-w2Hat;
    if disc>0, vHat=-qHat+sqrt(disc); else, vHat=-qHat; end
    vHat=min(max(vHat,p.lower+0.5),p.upper-0.5);
    vCmd=vHat;
    dith=p.estDither*(1-2*mod(kStep,2));
    % ---- 指令就位查询, 死推航向 ----
    c0=plant.count();
    PmNew=qs(vCmd+dith,'est');
    sUsed=plant.count()-c0;
    if ~isfinite(PmNew), break; end
    for j=1:sUsed
        psiHat=mod(psiHat+(vCmd+dith)/p.turnRadius*p.tEval,2*pi);
    end
    % ---- EKF更新步: P ≈ J0(|v·t̂+θ|), Huber降权新息 ----
    tx=cos(psiHat); ty=sin(psiHat);
    u=hypot((vCmd+dith)*tx+x(1),(vCmd+dith)*ty+x(2));
    h=w9.base_curve(u,p);
    dJ=w9.base_curve_grad(u,p);
    g=dJ/max(u,0.5);
    H4=[g*((vCmd+dith)*tx+x(1)), g*((vCmd+dith)*ty+x(2)), 0, 0];
    S=H4*Pp*H4.'+Reff;
    K=Pp*H4.'/S;
    innov=PmNew-h;
    w=1; ar=abs(innov)/sqrt(S);
    if ar>2.5, w=2.5/ar; end                 % Huber: 大新息线性降权不拒绝
    dx=K*(innov*w);
    dx(1:2)=max(-p.estStepClamp,min(p.estStepClamp,dx(1:2)));
    x=x+dx;
    x(1:2)=min(max(x(1:2),-p.optimum0*0.99),p.optimum0*0.99);
    x(3:4)=min(max(x(3:4),-0.5),0.5);
    Pp=(I4-K*H4)*Pp; Pp=(Pp+Pp.')/2;
    thetaHist(end+1,:)=x(1:2).'; %#ok<AGROW>
end
while plant.count()<n
    plant.q(vCmd,'hold'); plant.amendEstimate(vCmd);
end
info=struct('best',vCmd,'bestP',NaN,'windEst',x(1:2),'steps',kStep,...
    'mode','est','thetaHist',thetaHist);
end
