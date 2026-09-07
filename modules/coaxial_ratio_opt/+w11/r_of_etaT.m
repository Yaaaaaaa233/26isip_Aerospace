function r = r_of_etaT(etaT, pc, cdw, gamma)
%R_OF_ETAT 转速比 r=Omega_u/Omega_l 作为推力比 etaT 的函数(MT链 Eq.(27)(32) 与
% 下桨下洗二次式; 严格单调增, 供 r→etaT 反演)。pc=config 返回的物理常数结构。
% 逐元素运算, 保持输入方向。
if nargin<4, gamma=1.0; end
Tu = pc.totThrust*etaT./(1.0+etaT);
Tl = pc.totThrust./(1.0+etaT);
vu = sqrt(Tu./(2.0*pc.rho*pc.diskA));
vl = vu./w11.eta_v_of(etaT);
Up = cdw*(vu + gamma*vl);
Om_u = sqrt(Tu./pc.aT);
Om_l = (pc.c2*Up + sqrt((pc.c2*Up).^2 + 4.0*pc.aT.*Tl))./(2.0*pc.aT);
r = Om_u./Om_l;
end
