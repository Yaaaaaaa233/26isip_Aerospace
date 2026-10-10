function o = baseline(name)
%QUAD_SIM.BASELINE 建模调整方案机型参数包(2026-10-11, docs/QUAD_SIM_MODEL_PLAN_20261011.md)。
% 用法: c = quad_sim.config(quad_sim.baseline('b40'));   % 其后仍可叠 name/value 覆盖
% 三套机型(工作簿《世界记录四旋翼》R1/R2 裁决口径):
%   'bg'  背景参照: MN1005 KV90 + G40x13.1, 12S, 7.196 kg
%   'b40' BASELINE 40: U8lite KV150 + PA40X13.1W, 7S, 9.581 kg(按 BOM, R2)
%   'b42' BASELINE 42: 42 寸方案, 7S, 8.654 kg
% 映射来源: 工作簿电机台架表逐表拟合(n_krpm 口径, T[kgf]=a*n^2, P[W]=poly3),
%   域内拟合误差 T<=0.1%(R2=0.999), P<=2.2%; 域外(如 bg 悬停点低于表域下沿 18%)
%   为外推, 见妥协登记 C7。装配级悬停功率与工作簿汇总的偏差在验收输出中如实报告。
% PM-L1 口径(方案 P1): 风致 loadFactor 外推系数 = 0, 风效应只留 H3 诱导+废阻;
%   x8phys 外推路径保留以便复现 Q2 证据(trim_run 的 Jgain 开关不受影响)。
% 电池(方案 R4 合计建模): 等效单包; 4 块独立 7S 电池经细线秒级拉平 -> 电气等价
%   7S4P, 细线承担的飞控功耗折入 aux_power_W(15 W 声明)。
% 数值口径: workbook_baseline_20261011 —— 全部为工作簿/台架表推导, 仍非老师参数,
%   不可外引为真实机型结论(妥协登记 C8/C9)。
narginchk(1,1);
name = char(name);
o = struct('placeholder',true,'placeholder_tag','workbook_baseline_20261011', ...
    'power_source','bench_synth','power_model_id','bench_workbook_fit_v1', ...
    'motor_tau_s',0.08, ...                     % 保持声明值(C8, 待实机辨识)
    'rotor_advance_power_gain',0, ...           % PM-L1: 外推项关闭
    'rotor_axial_power_gain',0, ...
    'aux_power_W',15.0, ...                     % 飞控/遥测 10~15 W 经细线供电(R4)
    'drag_coefficient',[1.0; 1.0; 1.1], ...
    'drag_area_m2',[0.30; 0.30; 0.273]);        % CdA 沿声明值(C1, Hwang 试飞反推法待标)
switch name
    case 'b40'
        o.plane_model_id = 'quad_sim_b_workbook_b40_v1';
        o.mass_kg = 9.581;                      % BOM 总重(R2): 电池 5660 g + 空机 3921 g
        o.arm_m = 1.00;                         % 2 m 碳管 x2 交叉, X 架半臂长
        o.rotor_radius_m = 0.508;               % PA40X13.1W, 40 in
        o.ceiling_kn_rpm_per_V = 2573/24;       % 台架满载顶(U8lite@6S 表末行)
        o.omega_max_radps = 2*pi*2573/60;
        o.max_power_W = 2850;                   % 4 x 713 W(表末行电功率)
        o.battery_n_ser = 7; o.battery_n_par = 4;
        o.battery_capacity_Ah = 96;             % 4 x 24 Ah(ZE12070117A 电芯报告)
        o.battery_cutoff_V = 16.1;              % 2.3 V/芯(电芯报告放电终止)
        o.battery_r_cell_ohm = 0.012;
        o.bench_V_nom = 24;
        o.bench_P_coef = [132.208565 -468.986418 768.635032 -411.475581];
        o.bench_T_coef_desc = [0.877076 0 0];   % kgf = 0.877076*n_krpm^2 (R2=0.999)
        o.inertia_kgm2 = quad_sim.inertia_from_bom(0.630, 1.00, 0.315, 2.00, 2, 6.139);
    case 'b42'
        o.plane_model_id = 'quad_sim_b_workbook_b42_v1';
        o.mass_kg = 8.654;                      % BOM 总重: 电池 5660 g + 空机 2994 g
        o.arm_m = 0.75;                         % 声明值: 1.5 m 管 x3 布局含义待确认(C7)
        o.rotor_radius_m = 0.5372;              % PAD 42.3x14.2
        o.ceiling_kn_rpm_per_V = 2573/24;
        o.omega_max_radps = 2*pi*2573/60;
        o.max_power_W = 2850;
        o.battery_n_ser = 7; o.battery_n_par = 4;
        o.battery_capacity_Ah = 96;
        o.battery_cutoff_V = 16.1;
        o.battery_r_cell_ohm = 0.012;
        o.bench_V_nom = 24;                     % 与 b40 同一电机台架表
        o.bench_P_coef = [132.208565 -468.986418 768.635032 -411.475581];
        o.bench_T_coef_desc = [0.877076 0 0];
        o.inertia_kgm2 = quad_sim.inertia_from_bom(0.630, 0.75, 0.110, 1.50, 3, 3.354);
    case 'bg'
        o.plane_model_id = 'quad_sim_b_workbook_bg_v1';
        o.mass_kg = 7.196;                      % BOM 总重: 电池 4000 g + 空机 3196 g
        o.arm_m = 0.75;                         % 声明值: BOM 无臂长(C7)
        o.rotor_radius_m = 0.508;               % G40x13.1, 40 in
        o.ceiling_kn_rpm_per_V = 2882/47.33;    % 台架满载顶(MN1005 KV90@12S 表末行)
        o.omega_max_radps = 2*pi*2882/60;
        o.max_power_W = 5820;                   % 4 x 1455.9 W(表末行)
        o.battery_n_ser = 12; o.battery_n_par = 4;
        o.battery_capacity_Ah = 31.5;           % R1: 1360 Wh @340 Wh/kg / 43.2 V
        o.battery_cutoff_V = 27.6;              % 2.3 V/芯
        o.battery_r_cell_ohm = 0.030;           % 7.9 Ah 级电芯声明值(C3)
        o.bench_V_nom = 47.9;
        o.bench_P_coef = [171.119074 -618.072098 1081.998275 -629.626959];
        o.bench_T_coef_desc = [1.115948 0 0];   % kgf = 1.115948*n_krpm^2 (R2=0.999)
        o.inertia_kgm2 = quad_sim.inertia_from_bom(0.559, 0.75, 0.200, 1.50, 2, 4.360);
    otherwise
        error('quad_sim:Baseline','Unknown baseline: %s', name);
end
% config 在 struct 合并前已固化这两个派生字段, 参数包必须显式同步(kv 惯例=ceiling,
% 见 config 尾部; 内阻 = n_ser*r_cell/n_par), 否则覆盖不生效(b40 悬停坠落事故, 2026-10-11)。
o.kv_rpm_per_V = o.ceiling_kn_rpm_per_V;
o.battery_resistance_ohm = o.battery_n_ser*o.battery_r_cell_ohm/o.battery_n_par;
end
