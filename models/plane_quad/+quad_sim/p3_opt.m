function opt = p3_opt()
%QUAD_SIM.P3_OPT P3 算法验证预注册(单一事实源, 先于数据冻结; 方案 §4.3)。
% 按 R6 单机 b40: 验证前提"功率谷存在 + 谷随风移动 ⇒ 在线寻优有意义", 算法同机互比,
% 不做机型矩阵(2026-10-11 叶安裁决)。
% 任务: 固定时长 240 s 定速巡航窗, 风相位三段(头风 4 -> 静风 -> 顺风 4 m/s, 各 80 s),
%   功率谷随风相位移动; 策略=速度指令(t_dwell >=2 s 驻留语义, 接口 §10)。
%   评分 = 同窗电能量 E_wh(同窗可比); MOE = E_known/E_arm(内部归一化, C9 禁外引)。
% 臂(openloop/sweepcal/known, 见 +quad_sim/p3_arm):
%   openloop  固定 8 m/s(先验, 无反馈基线)
%   sweepcal  在线三点扫 + 二次拟合定谷(周期 30 s, 每点驻留 3 s, 只读 P̂)
%             G-P4 轻量版预注册(2026-10-14 冻结, 先于复评数据; 方案 §4.6/§4.7):
%             样本支撑选谷(锚定实测最优样本, 不外推)+邻域钳位(maxStep)+曲率门槛
%             (curvMin_pp1)+探针边界防退化+尾窗 2 s; 门槛数值不动, 改的是算法
%   known     oracle 上界(真值扫描逐风相位 v*, 显式 oracle, 不受因果门约束)
%   purerl    不在本机复现(无训练栈), 声明裁剪(Q 系 purerl 结论不迁移)
%   (2026-10-15 勘误: 多臂适配补上训练栈, purerl 族/rl/hybrid 已上机互比,
%    见 +quad_sim/p3_multiarm_opt 与其勘误登记; 本文件门槛/任务/原三臂不动)
% 敏感性(Q1 式, 施于估计口径 P̂, 对地速; 与 Q1 空速口径差在此声明):
%   s1 常数乘性偏差 {±3, ±5}%; s2 线性倾斜 {±0.7, ±1.4} %/m/s;
%   ±5/±1.4 档 = 探针, 报告不设门。
% 真值扫描: vGrid x 3 风相位(60 s 定速窗, 尾 30 s 均值) -> oracle 图 + E1 扩带证据。
% 门槛(预注册, 2026-10-11 先于运行冻结; 修改须勘误登记后重评):
%   G-P0 全臂完成窗口且能量有限
%   G-P1 双口径排序一致 + top 赢面漂移 <=1pp(M6 同款)
%   G-P2 因果门: 策略信息面仅白名单字段(结构强制 + 硬断言)
%   G-P3 RERUN 同会话逐位
%   G-P4 |s1|<=3% 或 |s2|<=0.7 档 sweepcal 赢面磨损 <=1pp
%   排序结论/MOE/E4/E5 = 结果交付, 不设门。
windPhases = [4 0 -4];              % 头风 4 -> 静 -> 顺风 4(风矢量 x 分量, m/s)
phaseT = [0 80 160 240];            % 相位边界(s)
mission = struct('T_s',240,'dt_s',0.01,'seed',20261011, ...
    'windPhases_mps',windPhases,'phaseBounds_s',phaseT, ...
    'vGrid_mps',4:14,'sweepT_s',60,'sweepTail_s',30, ...
    'vMin_mps',4,'vMax_mps',14,'vInit_mps',8, ...
    'cycle_s',30,'dwell_s',3,'tDwellMin_s',2);
arms = struct('openloop_v',8,'sweepcal',struct('cycle_s',30,'dwell_s',3, ...
    'tail_s',2,'probeOff_mps',1.5,'supportExt_mps',0,'maxStep_mps',1.5, ...
    'curvMin_pp1',0.5,'vMin_mps',4,'vMax_mps',14,'vInit_mps',8));
sens = struct('s1_pct',[3 -3 5 -5],'s2_pct_mps',[0.7 -0.7 1.4 -1.4], ...
    'gate_s1_pct',3,'gate_s2_pct_mps',0.7);
gates = struct('driftMax_pp',1.0,'sensWearMax_pp',1.0, ...
    'policyFields',{{'t','v','x','Phat','Vmeas','Ehat','cmd'}});
opt = struct('mission',mission,'arms',arms,'sens',sens,'gates',gates);
end
