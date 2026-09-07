function [P, Pmin] = truth_curve(r, c)
%TRUTH_CURVE 归一化真值功率-桨比曲线(γ=1 形状; 漂移/水平因子由 plant 侧另行施加)。
% P*(r) = shape2(r) + rip(r − rStar0):
%   shape2 = α·(P_mt(r;cdw,1)/P_mt(1;cdw,1))^κ + β —— 链形状经功率变换(深度标定
%            κ=log(case)/log(chainDepth)) + 仿射微调(吸收涟漪在锚点的取值);
%   rip    = 双余弦涟漪(任务2式崎岖, 谷底补偿: x=0处值=−(A1+A2)、导数=0)。
% 锚点精确成立: P(rStar0)=ratioCase, P(1)=1, 全局谷底唯一且恰在 rStar0。
% Pmin = ratioCase。α/β 见下方闭式(由锚点条件解出)。
u = r - c.rStar0;
rip = c.rippleA1*cos(2*pi*u/c.rippleL1 + c.rippleF1) ...
    + c.rippleA2*cos(2*pi*u/c.rippleL2 + c.rippleF2);
shape = (w11.mt_chain(r,c,1.0)/c.chainP1Ref).^c.kappa;
P = c.shapeAlpha*shape + c.shapeBeta + rip;
Pmin = c.ratioCase;
end
