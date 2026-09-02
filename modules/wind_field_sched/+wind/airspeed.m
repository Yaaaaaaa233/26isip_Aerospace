function out = airspeed(v, c, t)
%AIRSPEED 空速换算（对象侧物理，TASKS_1_5_ROUTE §3）。
%   u = v·t̂(t) + w(t),  t̂ = (cosψ, sinψ),  ψ = 2πt/T_circle
%   |u|² = v² + 2v·q + |w|²,  q = t̂ᵀw（风的航向投影）
% 输出: out.u2 |u|², out.q, out.w2 |w|², out.psi 航向角
t=t(:)'; v=v(:)';
psi=2*pi*t/c.circlePeriod;
[wx,wy]=wind.wind_truth(c,t);
q=cos(psi).*wx+sin(psi).*wy;
w2=wx.^2+wy.^2;
u2=v.^2+2*v.*q+w2;
out.u2=u2; out.q=q; out.w2=w2; out.psi=psi;
out.wx=wx; out.wy=wy;
end
