function dP = base_curve_grad(v, c)
%BASE_CURVE_GRAD 标定曲线对速度的导数 dP/dv(解析: 三次多项式导数+涟漪导数)。
dS = polyval(polyder(c.curveCoef), v);
u = v - c.optimum0;
dRip = -c.rippleA1*(2*pi/c.rippleL1)*sin(2*pi*u/c.rippleL1 + c.rippleF1) ...
       -c.rippleA2*(2*pi/c.rippleL2)*sin(2*pi*u/c.rippleL2 + c.rippleF2);
dP = dS + dRip;
end
