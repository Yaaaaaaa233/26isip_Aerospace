function [rStar, P1] = mt_chain_valley(gamma, c)
%MT_CHAIN_VALLEY 给定干扰因子 gamma 的 MT 链谷底桨比 r*_mt(gamma) 与等转速功率 P(1;gamma)。
% 注意: r↔η_T 映射随 γ 变化, P(1;γ) 必须取"该 γ 下 r=1"对应的 η_T。
% 漂移映射与功率水平因子都在此基础上按增量取值(见 config.m 第3步)。
etaG=linspace(0.30,14.0,1600);
rMap=w11.r_of_etaT(etaG,c,c.cdw,gamma);
Pm=w11.chain_power_at(etaG,rMap,c,c.cdw,gamma);
[~,im]=min(Pm);
rStar=rMap(im);
eta1=interp1(rMap,etaG,1.0,'pchip');   % 该 γ 下 r=1 的推力比
P1=w11.chain_power_at(eta1,1.0,c,c.cdw,gamma);
end
