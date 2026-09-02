function [P, x] = power_curve(u, c, varargin)
%POWER_CURVE 仓库三次文献代理功率 P0(|u|)（speed_esc 同源，不重标定气动）。
%   P0(x) = 1 − 1.5b·x² + b·x³,  x = u/V*,  b = 2(1−P*)
%   P0(V*)=P*, P0'(V*)=0, P0''(V*)=3b/V*²>0（V*为极小点）。
% 可选输出 x=u/V*。逆运算见 inv_power。
b=2*(1-c.Pstar);
x=u(:)/c.Vstar;
P=1-1.5*b*x.^2+b*x.^3;
P=reshape(P,size(u));
end
