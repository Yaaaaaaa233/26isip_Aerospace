function [P, Om_u, Om_l] = mt_chain(r, c, gamma)
%MT_CHAIN Opazo et al. 2022 (J. Aircraft 60(2)) Eq.(27)-(35) MT 链: 桨比→功率。
% 输入 r = eta_Omega = Omega_u/Omega_l (上/下), 返回该桨比下的每臂总功率 P(W)
% 与上下桨转速(rad/s)。gamma 为等效诱导干扰因子(默认1, 基准标定态)。
% 链条(与论文公式一一对应, 恒定总拉力 T=c.totThrust, 定桨距变转速):
%   (27)(28) Tu = T·etaT/(1+etaT), Tl = T/(1+etaT)
%   (29)     vu = sqrt(Tu/(2 rho A))
%   (14)(30) eta_v(etaT) 闭式 (eta_v(1)=1.780777, 与论文一致)
%   (31)     vl = vu/eta_v
%   (32)     Om_u = sqrt(Tu/aT)
%   (25)(26) 下桨在上桨下洗(有效爬升流速 Up=cdw·(vu+gamma·vl))中的 BET 截面推力积分:
%            Tl = aT·Om_l² − c2·Up·Om_l,  c2 = Nb·rho·clalpha·R²/4 → 正根
%   (34)(35) Pu = k·Tu·vu + (sigma·cd/8)·rho·A·(Om_u R)³
%            Pl = k·Tl·(vu+gamma·vl) + (sigma·cd/8)·rho·A·(Om_l R)³
% r→etaT 反演: r(etaT)=Om_u/Om_l 严格单调增, 在预计算网格上 pchip 插值。
if nargin<3, gamma=1.0; end
etaT = w11.r2etaT(r,c);
Tu = c.totThrust*etaT./(1.0+etaT);
Tl = c.totThrust./(1.0+etaT);
vu = sqrt(Tu./(2.0*c.rho*c.diskA));
etav = w11.eta_v_of(etaT);
vl = vu./etav;
Up = c.cdw*(vu + gamma*vl);
Om_u = sqrt(Tu./c.aT);
Om_l = (c.c2*Up + sqrt((c.c2*Up).^2 + 4.0*c.aT.*Tl))./(2.0*c.aT);
P = c.kInd*Tu.*vu + c.sigCd8*c.rho*c.diskA.*(Om_u*c.rotorR).^3 ...
  + c.kInd*Tl.*(vu + gamma*vl) + c.sigCd8*c.rho*c.diskA.*(Om_l*c.rotorR).^3;
end
