function opt = realism_opt()
%QUAD_SIM.REALISM_OPT P2 控制现实性磨损矩阵预注册(单一事实源, 先于数据冻结)。
% 依据 docs/QUAD_SIM_MODEL_PLAN_20261011.md §4(控制现实性清单)与 §4.1(门槛预注册)。
% 形态对齐 Q1 敏感性套件(q39.q1_opt): OAT 因子族(单因子逐档) + 典型整链角点 +
% 复跑确定性档; 硬门只设在 REF/典型整链两档(极端档=敏感性探针, 如实报告不设门,
% 与 Q1 ±5% 合成档同定位)。
%
% 因子族(8 个现实性参数, 与 +quad_sim/config 同名, 全零默认=逐位无操作):
%   D 时延族    meas_delay_s        0.1 / 0.2 / 0.5 s(GPS 级速度测量通道, T1 0.2 为典型;
%               整帧语义已勘误, 见方案 §4.1 与 realism_run 头注)
%   K 执行器族  ctrl_period_s(指令保持/算法步) + pwm_slew_us_per_s + pwm_quant_us
%               K1 典型: 0.02 s / 1500 us/s / 1 us    K2 严酷: 0.05 s / 400 / 4
%   N 噪声族    meas_noise_V_pct + est_noise_pct
%               N1 典型: 0.5% + 1.2%(T1)             N2: 1.0% + 2.4%
%   TYP 典型整链: 上述典型值全开(测量 0.2s + 算法步 0.02s + 执行保持 + 噪声链)
%   RERUN      REF 同参重跑(同会话逐位确定门)
%
% 任务(预注册): 固定航程 200 m 巡航(前后各悬停 5 s), 策略=巡航速度
%   {3..9} m/s, 头风 2.5 m/s + 确定性阵风剧本(风扰剧本, 方案 §4);
%   噪声用固定种子 mt19937ar(共同随机数, 跨策略/跨格公平)。
% 指标: E_wh(机上电总能量, 同一趟旅行为可比口径) / 磨损 wear_pp =
%   100*(E_cell-E_REF)/E_REF / 赢面 gap_pp = 100*(E_2nd-E_best)/E_best /
%   估计链 bias_pct = 100*(Ehat-E)/E(重标定账, C3/C7 绝对值只报告)。
% MOE 口径: 内部统一归一化, 禁止外引(C9)。
mission = struct('dist_m',200,'hover_s',5,'maxTime_s',240, ...
    'speeds_mps',[3 4 5 6 7 8 9],'seed',20261011, ...
    'wind_base_mps',2.5,'wind_sin_amp',0.5,'wind_sin_T_s',23, ...
    'wind_gust_mps',1.5,'wind_gust_windows_s',[20 25; 45 50], ...
    'stepFrom',[5 8],'step_secs',60);
% 门槛(预注册, 2026-10-11 先于运行冻结; 修改须走勘误登记后重评):
gates = struct( ...
    'argminStable', true, ...        % G-R1 典型整链最优速度选择与 REF 一致
    'marginWearMax_pp', 1.0, ...     % G-R2 典型整链 top-2 赢面磨损 <=1pp(M6 同款)
    'marginFloor_pp', 2.0, ...       % 近平手带: REF 差距 <2pp 的策略对=不可分辨, 报告不判
    'estWearMax_pp', 2.0, ...        % G-R5 估计链偏差磨损 |bias(TYP)-bias(REF)| <=2pp
    'overshootMax_pct', 20.0, ...    % G-R4 阶跃超调 <=20% 步长(REF 与 TYP 两档)
    'settleMax_s', 20.0);            % G-R4 就位(±0.1 m/s 保持 2s) <=20 s
opt = struct('mission',mission,'gates',gates);
opt.cells = [ ...
    local_cell('REF','ref',0) ...
    local_cell('D1','delay',0.1) local_cell('D2','delay',0.2) local_cell('D5','delay',0.5) ...
    local_cell('K1','sat',1) local_cell('K2','sat',2) ...
    local_cell('N1','noise',1) local_cell('N2','noise',2) ...
    local_cell('TYP','typical',1) ...
    local_cell('RERUN','rerun',0)];
end
function cl = local_cell(id, family, level)
d = struct('ctrl_period_s',0,'cmd_delay_s',0,'meas_delay_s',0, ...
    'meas_noise_V_pct',0,'pwm_slew_us_per_s',0,'pwm_quant_us',0, ...
    'est_delay_s',0,'est_noise_pct',0);
switch id
    case {'D1','D2','D5'}
        d.meas_delay_s = level;
    case 'K1'
        d.ctrl_period_s = 0.02; d.pwm_slew_us_per_s = 1500; d.pwm_quant_us = 1;
    case 'K2'
        d.ctrl_period_s = 0.05; d.pwm_slew_us_per_s = 400; d.pwm_quant_us = 4;
    case 'N1'
        d.meas_noise_V_pct = 0.5; d.est_noise_pct = 1.2;
    case 'N2'
        d.meas_noise_V_pct = 1.0; d.est_noise_pct = 2.4;
    case 'TYP'
        d.ctrl_period_s = 0.02; d.cmd_delay_s = 0.02; d.meas_delay_s = 0.2;
        d.meas_noise_V_pct = 0.5; d.pwm_slew_us_per_s = 1500; d.pwm_quant_us = 1;
        d.est_delay_s = 0.2; d.est_noise_pct = 1.2;
end
cl = struct('id',id,'family',family,'level',level,'deg',d);
end
