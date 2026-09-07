function etav = eta_v_of(etaT)
%ETA_V_OF Opazo et al. 2022 Eq.(14)/(30) 闭式: 诱导速度比 eta_v = v_u/v_l(eta_T)。
% 论文核验值 eta_v(1)=1.78077 (Leishman 等推力特例 0.5616 的倒数)。
% 逐元素运算, 保持输入方向(行/列均可)。
etav = 2.0./(sqrt(1.0./etaT.^3 + 4.0./etaT.^2 + 8.0./etaT + 4.0) ...
    - 1.0./etaT - 2.0);
end
