function [P, Pmin] = base_curve(v, c)
%BASE_CURVE 任务9标定功率曲线（归一化单位: 悬停功率=1; 瓦特=P×pHover）。
% 参考图像: DJI Mavic Pro 实测功率曲线(Battulwar et al. Eq.1, a=0, Vz=0, wind=0):
%   悬停 P(0)=103.7 W, 谷底 V*=6.3 m/s, P(20)=134.5 W。
% 结构 = 三次光滑标定曲线 S(v) + 任务2式对称涟漪(崎岖):
%   S(v): 三次多项式(config按锚点解出), 锚点 P(0)=1(悬停)、
%         P(V*)=curveCase(需求case: 谷底=悬停的95%/90%/85%)、P'(V*)=0、P(20)=p20/pHover;
%   涟漪: A1·cos(2πu/λ1+π)+A2·cos(2πu/λ2+π), u=v−V* (与任务2同参数同相位),
%         在u=0处值为−(A1+A2)、导数为0, 故全局谷底恰在 V* 且
%         Pmin = curveCase 精确成立; 涟漪使谷底比光滑曲线低 A1+A2(已补偿进锚点)。
% 任务2的测量噪声模型(相对噪声noiseSigma+可选脉冲)保留在 make_plant 中不变。
u = v - c.optimum0;
rip = c.rippleA1*cos(2*pi*u/c.rippleL1 + c.rippleF1) ...
    + c.rippleA2*cos(2*pi*u/c.rippleL2 + c.rippleF2);
P = polyval(c.curveCoef, v) + rip;
Pmin = c.curveCase;   % u=0处精确成立(对三个case均为悬停功率的95%/90%/85%)
end
