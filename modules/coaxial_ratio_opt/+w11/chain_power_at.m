function P = chain_power_at(etaT, r, pc, cdw, gamma)
%CHAIN_POWER_AT 给定推力比 etaT(与对应转速比 r)的 MT 链总功率(Eq.(27)-(35) 直算,
% 供标定/漂移映射使用——运行期反演见 mt_chain.m)。pc=config 物理常数结构。
if nargin<5, gamma=1.0; end
Tu = pc.totThrust*etaT./(1.0+etaT);
Tl = pc.totThrust./(1.0+etaT);
vu = sqrt(Tu./(2.0*pc.rho*pc.diskA));
vl = vu./w11.eta_v_of(etaT);
Up = cdw*(vu + gamma*vl);
Om_u = sqrt(Tu./pc.aT);
Om_l = (pc.c2*Up + sqrt((pc.c2*Up).^2 + 4.0*pc.aT.*Tl))./(2.0*pc.aT);
P = pc.kInd*Tu.*vu + pc.sigCd8*pc.rho*pc.diskA.*(Om_u*pc.rotorR).^3 ...
  + pc.kInd*Tl.*(vu + gamma*vl) + pc.sigCd8*pc.rho*pc.diskA.*(Om_l*pc.rotorR).^3;
end
