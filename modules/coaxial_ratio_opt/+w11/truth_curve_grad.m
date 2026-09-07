function dP = truth_curve_grad(r, c)
%TRUTH_CURVE_GRAD 真值曲线对桨比的导数(链形状的链式法则 + 涟漪导数; γ=1形状)。
% d/dr [α·(P_mt/P1)^κ] = α·κ·(P_mt/P1)^(κ-1)·(dP_mt/dr)/P1, 逐元素(.*)、方向保持。
h = 1e-5;
Pp = w11.mt_chain(r+h,c,1.0); Pm = w11.mt_chain(r-h,c,1.0);
dMt = (Pp-Pm)./(2*h);
shape = (w11.mt_chain(r,c,1.0)/c.chainP1Ref).^c.kappa;
u = r - c.rStar0;
dRip = -c.rippleA1*(2*pi/c.rippleL1).*sin(2*pi*u/c.rippleL1 + c.rippleF1) ...
       -c.rippleA2*(2*pi/c.rippleL2).*sin(2*pi*u/c.rippleL2 + c.rippleF2);
dP = c.shapeAlpha*c.kappa*shape.^(1-1/c.kappa).*(dMt/c.chainP1Ref) + dRip;
end
