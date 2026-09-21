function [Pw, parts] = est_l1(c, pwm, V, uair, decl)
%Q39.EST_L1 L1 估计器 = L0 静态映射 + 声明系数气速修正(QUAD_MIGRATION_PLAN 20260921 D1)。
%   P_hat_L1 = P_hat_L0(n_hat(pwm), V_hat)
%              - dH3 + dH5 + dDrag + aux        (声明结构气速修正, 与 trim_curve
%                                               离线分解逐项同型)
% 修正项(全部用"声明口径"系数 decl, 空缺字段回退 c 自身标定参数 = 声明上界档;
% Q4 敏感性用 decl 覆盖降档, 与 Q1 的 s1/s2 合成残差机制正交):
%   dH3   = 8 * sav(T_decl, uair)                 前飞诱导节省(动量理论, 缺失->正偏)
%   dH5   = 4 * (bench - sav) * delta(uair)       共轴惩罚作用于扣 H3 之后(植物口径)
%   dDrag = 0.5 * rho * CdA_decl * uair^3         废阻(缺失->负偏)
%   aux   = aux_decl                              辅助负载(常数)
% 悬停域(uair=0): dH3=dH5=dDrag=0, L1 = L0 + aux(补齐常数项)。
% 输入 uair = 估计空速 [m/s] —— 实机口径由"测量地速 − 风测量"合成(全仓 v_air
% = v_ground − wind 减号约定, D1 的算法侧反馈), 不得读植物真值空速输出字段
% (因果红线); 平台链测量面 wind_measured 全量可见, 故 û̂ 直接由测量通道合成,
% ŵ 迭代反馈的稳定性论断留待实机传感器集。
% 输入 c = plane.config 结构; pwm = 每电机油门 [us] (等长任意); V = 端电压 [V];
% decl = 声明系数覆盖结构体(可空)。
% 输出 Pw = 估计总功率 [W]; parts = 修正分项(诊断)。
if nargin < 4 || isempty(uair), uair = 0; end
if nargin < 5, decl = []; end
d = c;
if ~isempty(decl)
    fn = fieldnames(decl);
    for k = 1:numel(fn)
        assert(isfield(d, fn{k}), 'q39:EstL1', ...
            'decl 覆盖字段 %s 不在配置中。', fn{k});
        d.(fn{k}) = decl.(fn{k});
    end
end
[Pl0, nHat] = q39.est_l0(c, pwm, V);
bench = Pl0 / numel(pwm);            % P2 需求均分 -> 每桨台架功率相同
aD = 0.5 * d.air_density_kgpm3 * d.cda_m2 * uair^2 / d.mass_kg;
th = atan(aD / d.gravity_mps2);
TN = d.mass_kg / (8 * cos(th)) * d.gravity_mps2;   % 悬停等效单桨拉力 [N]
sav = local_ind_saving(d, TN, uair);
delta = d.coaxial_delta_base * local_vi_ratio(d, TN, uair)^d.coaxial_decay_kappa;
dH3 = 8 * sav;
dH5 = 4 * (bench - sav) * delta;
dDrag = 0.5 * d.air_density_kgpm3 * d.cda_m2 * uair^3;
Pw = max(0, Pl0 - dH3 + dH5 + dDrag + d.aux_power_W);
parts = struct('Pl0', Pl0, 'dH3', dH3, 'dH5', dH5, 'dDrag', dDrag, ...
    'aux', d.aux_power_W, 'nHat', nHat);   % nHat 诊断与 est_l0 对齐
end

function [vi, vi0] = local_vi(d, T_N, vair)
vi = 0; vi0 = 0;
if T_N <= 0 || vair <= 0, return; end
A = pi * (d.prop_diameter_m^2) / 4;
k = T_N / (2 * d.air_density_kgpm3 * A);
vi0 = sqrt(k); vi = sqrt((vair/2)^2 + k) - vair/2;
end

function ratio = local_vi_ratio(d, T_N, vair)
[vi, vi0] = local_vi(d, T_N, vair);
if vi0 > 0, ratio = vi / vi0; else, ratio = 0; end
end

function sv = local_ind_saving(d, T_N, vair)
[vi, vi0] = local_vi(d, T_N, vair);
sv = max(0, d.h3_induced_gain * T_N * (vi0 - vi));
end
