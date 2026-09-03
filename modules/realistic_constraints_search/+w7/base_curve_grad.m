function dJ = base_curve_grad(u, c)
%BASE_CURVE_GRAD 基准曲线对空速u的导数 dJ0/du(在线估计器的雅可比用)。
% J0(u)=1+0.003(u−6)²+A1·cos(2π(u−6)/λ1+π)+A2·cos(2π(u−6)/λ2+π)
du = u - c.optimum0;
dJ = 0.006*du ...
    - c.rippleA1*(2*pi/c.rippleL1)*sin(2*pi*du/c.rippleL1 + c.rippleF1) ...
    - c.rippleA2*(2*pi/c.rippleL2)*sin(2*pi*du/c.rippleL2 + c.rippleF2);
end
