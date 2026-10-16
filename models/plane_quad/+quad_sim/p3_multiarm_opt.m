function opt = p3_multiarm_opt()
%QUAD_SIM.P3_MULTIARM_OPT 多臂适配预注册(单一事实源, 2026-10-15 先于数据冻结)。
% 方向登记(叶安 2026-10-15): "先不管电流采样器吧, 直接做多臂适配"——把 Q 系
% (w36/q39) 的 rl/hybrid/purerl 臂适配进 p3_arm 策略句柄框架, 与
% openloop/sweepcal/known 同链同窗同信息面互比。本文件冻结臂清单/臂参数/
% 试飞预训练规格; 门槛仍取 p3_opt.gates 同值(门槛不动)。
%
% ── 勘误登记(2026-10-15, 先于本批数据) ──
% p3_opt 头注"purerl 不在本机复现(无训练栈), 声明裁剪"自本登记起被本文件
% 取代: 训练栈 = quad_sim.p3_warmup(独立 realism_run 实例试飞预训练, 见下)。
% p3_opt 本身不动(门槛/任务/原三臂参数仍为冻结事实源)。
%
% ── 两个预置裁决(适配前登记) ──
% (a) hybrid/windinfer 航向激励问题: 环航平台的风辨识靠"功率-航向调制"
%     (fit_curve_wind 的 (f,w) 联合辨识 + wind_corr 增量修正在 ψ 展开下才可辨识)。
%     本链是直线任务, 信息面无航向(G-P2 白名单), plant 接口无航向自由度
%     (air_quad_tick 输入=[v_ref; wind_ned; reset])——加航向段=改 plant 契约+
%     白名单+任务书, 违反"门槛不动/接口冻结"。裁决: **剪航向风辨识模块**,
%     换成直线链 1-D 曲线平移跟踪。依据: 本链 P(v,w)=g(v+w) 精确成立
%     (P3 真值扫描三相位曲线互为严格平移, 见 quad_p3_sweep_vi.csv:
%     P_w=4(v)=P_w=0(v+4) 逐点相等~0.06 W), 平移量 s=w-w0 单参数可辨识
%     (冻结形状对齐拟合), 谷预测 v̂*=x̂*-s 平移歧义不传入地速谷。
%     边界情形: 标定谷被 [vMin,vMax] 边界截断时(x̂* 在域外), x̂* 取边界三点
%     抛物顶点(仅用于谷预测/平移对齐; 动作一律限幅 [vMin,vMax], 支撑选谷
%     规则照旧用于域内谷)。Phase A 扫描用"括号扫+早停"(见下), 不做全速域
%     平扫——全速域扫在本链能耗惩罚过大(相位 1 平扫 33 s 采 1016 W 均值,
%     超额 ~3.8 Wh, 与臂间差距同量级), 且 1-D 谷辨识只需谷邻域覆盖。
% (b) purerl 训练栈: 平台缓存预训练模型(w36.load_platform_pretrain)是环航
%     24/12 航向桶策略、平台 plant 功率曲线——本链无航向维度、P(v) 不同,
%     迁移无意义。裁决: **独立实例试飞预训练**(p3_warmup, w36 本地路径
%     warmPlant 同款语义): 预训练在另一 realism_run 实例上进行(静风定常
%     w=0, 不含评价窗风剧本信息, 同分布不同实现), 不占 240 s 任务窗能耗
%     ——"预训练步为额外试飞预算"边界照 w36 红线 3 口径声明。purerl_on/off
%     = 同一预训练的两种部署(w36 pure_rl_pre_run 同构)。
% (c) 臂为反应式(时间盲): 策略不读绝对时间做调度(禁止背剧本); 分段常值
%     相位风的谷移动只能靠测量反馈跟踪。'known' 仍是唯一显式 oracle。
%
% ── 任务/门槛(全部不动, 取自 p3_opt) ──
%   任务: 240 s 定速巡航窗, 风相位 [4 0 -4] m/s 各 80 s, v∈[4,14], vInit=8;
%         评分=同窗电能量 E_wh; t_dwell>=2 s 驻留语义(接口 §10)。
%   门槛: G-P0 全臂完成且能量有限 | G-P1 双口径排序一致 + top 赢面漂移<=1pp
%         | G-P2 白名单结构断言 | G-P3 RERUN 同会话逐位 | G-P4 sweepcal
%         赢面磨损<=1pp(|s1|<=3% 或 |s2|<=0.7 档)。
%   扩展(不改门槛值): G-P3 RERUN 覆盖扩到全部臂(成本低, 状态臂必须逐位);
%         敏感性 s1/s2 对新臂在门内档(+/-3%/+/-0.7)加报磨损行(不设门)。
%
% ── 臂清单(8) ──
%   openloop / sweepcal / known   原 P3 三臂(p3_opt 臂参数不变)
%   hybrid    Phase A 括号扫标定 + 冻结形状 1-D 平移跟踪 + 信赖域探针对
%   rl        Phase A 括号扫标定 + 学到模型内离线 REINFORCE 预训练 + 在线
%             对偶探索 REINFORCE 微调(w36 rl v3 三段式 1-D 单桶移植)
%   purerl    无扫频无模型纯在线 REINFORCE(w36 pure_rl_run 1-D 单桶移植)
%   purerl_on 试飞预训练后在线部署(lr/4, σ=0.5, 继续修正)
%   purerl_off 试飞预训练后冻结贪心部署(零探索零学习)
%
% ── 共同采样语义(移植口径; 测量语义 v2 见勘误登记 2) ──
%   每驻留 dwell_s 的整段 1 Hz 子均值 (v实,P̂) 对即样本; 样本配对用实测地速
%   info.v。w36 settled_q 的 p3 等价由驻留整段+回归给出(本链速度环 τ≈2.9 s,
%   等稳态驻留不可行)。测量只读 info 面(G-P2 白名单, harness 逐调用断言)。
m = struct('T_s',240,'dt_s',0.01,'seed',20261011, ...
    'windPhases_mps',[4 0 -4],'phaseBounds_s',[0 80 160 240], ...
    'vGrid_mps',4:14,'sweepT_s',60,'sweepTail_s',30, ...
    'vMin_mps',4,'vMax_mps',14,'vInit_mps',8,'tDwellMin_s',2);
% ---- Phase A 括号扫(rl/hybrid 共用, p3_phase_a) ----
% 从 vInit 起向下优先双向 1 m/s 步进; 每样本后判停:
%   (i) 域内括号: 运行最优点有相邻三点(网格), 三点抛物顶点落在括号内且
%       曲率 >= curvMin_pp1 -> 停(谷已括住);
%   (ii) 域边界谷: 最优点在 vMin/vMax 且靠边三点单调朝外 -> 停(谷在域外,
%       多采无益; 顶点外推只用于谷预测);
%   (iii) maxPts 上限 -> 停。
sweep = struct('step_mps',1,'dwell_s',3,'tail_s',2,'maxPts',11, ...
    'curvMin_pp1',0.5,'vMin_mps',4,'vMax_mps',14,'vInit_mps',8);
% ---- hybrid(p3_pol_hybrid) ----
% Phase B: 每 hyWindEvery_s 用近窗 win_s 样本对冻结形状做 1-D 平移对齐
% (网格 sRange 步 0.25+抛物细化, 只用对齐后落支撑内的样本, >=3 个才更新;
%  阻尼 sDamp); 谷中心 uArg=x̂*-s(平移预测, 不限速——相位阶跃就指望它);
% 每 ucProbeEvery_s 探针对 ±ucProbeDelta(尾窗均值), 对斜率 sPair 超
% ucThr 才动, du=-ucGain*sPair/bEst 限幅 maxStepProbe, v̂* 限 uArg±trustR;
% bEst=曲率 EMA(bRaw=|ΔsPair/Δv̂*|, 跨度 [0.5 50] W/(m/s)^2, 初值=拟合曲率)。
% w36 的曲线维护机器(重拟合+SSE 守卫)裁剪: 本链曲线形状物理固定
% (P=g(v+w) 精确成立), 形状在线维护无对象; w36 维护机器针对形状偏差场景。
hybrid = struct('dwell_s',3,'tail_s',2, ...
    'hyWindEvery_s',10,'win_s',30,'sRange',[-8 8],'sDamp',0.8, ...
    'ucProbeEvery_s',20,'ucProbeDelta_mps',1.5,'ucGain',0.30, ...
    'ucThr',1.0,'trustR_mps',1.5,'maxStepProbe_mps',0.4, ...
    'bEstMin',0.5,'bEstMax',50,'escThr',6.0,'escHard',10.0,'reMaxPts',9, ...
    'escCooldown_s',40,'sRmsMax',20,'sMaxJump',4,'sweep',sweep);
% 勘误登记 2(2026-10-15, 首批数据后复评前; 数值依据见 worklog):
%   首批(vi) hybrid=44.62 Wh 排位异常(机制预期其为快跟踪臂)。数值复核
%   (标定四次式外推 vs 真曲线): 支撑外 1 m/s 误差 +31 W、arg=0 +75 W、
%   2 m/s +293 W; 大相位阶跃下平移对齐**两支歧义**(相位 3 窗口样本对
%   s=-0.8 与 s=-8 等解释, 需跨谷样本区分)——环航平台靠航向调制解决的
%   可辨识性问题在直线链无免费替代。裁决: 平移跟踪降为小漂移快路径
%   (对齐评估域扩到顶点 ±1 m/s, 该域外推误差 <=31 W), **重括号升级**为
%   大阶跃主恢复: 探针对斜率 |sPair|>escHard(单次)或连续两对同号
%   |sPair|>escThr -> 从当前 v̂* 重跑括号扫(reMaxPts 上限), 支撑选谷+边界
%   顶点逻辑重定谷, s=F.vStar-v̂* 重锚。门槛/任务/其余臂参数不动;
%   rl/purerl 跟踪短板为机制固有(微调步长/样本饥饿), 不调参不修, 如实报。
%   升级判据两轮 dev 烟测修订(hycheck, 先于复评数据): 初版 escThr=2/escHard=6
%   误触发两类——相位 1 谷在域外探针斜率恒 +37(方向指向域外, 升级无意义)、
%   平谷括号残差斜率 ~5 持续两对同号(重括号循环, E 反而升到 45.3)。终版:
%   escThr=6/escHard=10 + 方向抑制(斜率指向域外不升级) + 重括号后 40 s 冷却。
%   测量语义 v2(同批, 依据: 阶跃 8->5.5@头风4 实测速度环 τ≈2.9 s——3 s 驻留
%   永远不到位, 尾窗均值全在暂态里: 探针斜率实测 13.4 vs 物理 37.5 W/(m/s),
%   Pup 测成 635(=P(5.0)) 而非 659(=P(5.5)); 且指令/实测稳态偏移 0.16-0.38
%   是斜率标定的系统性偏差源):
%     1) 样本配对用实测地速 info.v; 2) 驻留整段的 1 Hz 子均值 (v实,P̂) 对即
%   样本(加速偏差 ±m·v·a/η≈±4 W 在上下行间自相消); 3) 探针斜率=两驻留子对
%   合并回归斜率(稳态偏移下良态); 4) 括号判停邻域判据无格点化。驻留 3 s 保留
%   (提供通过覆盖), tDwellMin>=2 s 合规。平谷下指令/实测偏移的能量代价 <0.5 W。
%   首点暂态曾把标定锚吸到 8(Benter vHat=7.89), 语义 v2 一并根治。
%   选谷同批改样本锚定(四次式 wiggle 伪极小 + 边界顶点 v/P 排序错配两 bug)。
%   平移更新加接受双门: 残差 RMS<=20 W(拒两支歧义错支) + |Δs|<=4(大跳变是
%   重括号职责, 快路径只管小漂移)——防重括号后错预测把 v̂* 拽回去。
% ---- rl(p3_pol_rl) ----
% Stage B 离线预训练在 g0 模型上(1-D 单桶 REINFORCE, nSim 步零飞行成本;
% 单桶下收敛到模型谷=曲线 argmin, 保留机制与环航 24 桶版同构对照),
% u 钳位 vStar±preTrust(截断拟合只在谷邻域可信, w36 同款保险)。
% Stage C 在线对偶探索(±σ 逐样本交替), bBase/Pb EMA 基线, dB 限幅 0.10。
rl = struct('dwell_s',3,'tail_s',2,'rlSigma',0.50,'rlSigmaMin',0.20, ...
    'rlLr',0.20,'dBMax',0.10,'nSim',2000,'preTrust_mps',2.5,'sweep',sweep);
% 说明: w36 rlSigma=0.30 为环航 24 桶口径; 本链功率谷浅(曲率 ~9.7 W/(m/s)^2,
% P3 真值扫描三点二阶差分), σ=0.5 保配对差信号 SNR(lr/dB 限幅照 w36)。
% ---- purerl 族(p3_pol_purerl) ----
% 对偶交替 ±σ0(plHold 样本换号), bBase EMA 基线, 邻域核删除(单桶无邻域),
% σ 退火 0.996/样本到 σmin。dwell 2 s=登记下限 tDwellMin(样本饥饿是纯在线
% RL 的主要短板, 短驻留换样本率是该臂的算法选择)。
purerl = struct('dwell_s',2,'tail_s',1,'plSigma0',1.20,'plSigmaMin',0.50, ...
    'plLr',10.0,'plHold',2,'dBMax',0.05,'anneal',0.996);
% 试飞预训练(p3_warmup): 独立 realism_run 实例, 静风定常(w=0, 不泄漏
% 评价窗相位剧本身份), warmT_s=600 固定预算(可复现优先于 w36 的收敛早停),
% 种子=评价种子+17(w36 同款偏移)。部署: on=lr/4=2.5 σ=0.5 继续修正;
% off=冻结贪心 μ(单桶下即恒速, 反应式策略无状态可依——诚实退化, 如实报)。
warmup = struct('T_s',600,'seedOffset',17,'windPhases_mps',0, ...
    'dwell_s',2,'tail_s',1,'onLr',2.5,'onSigma',0.50);
arms = {'openloop','sweepcal','hybrid','rl','purerl','purerl_on','purerl_off','known'};
sens = struct('s1_pct',[3 -3 5 -5],'s2_pct_mps',[0.7 -0.7 1.4 -1.4], ...
    'gate_s1_pct',3,'gate_s2_pct_mps',0.7,'newArmGatedOnly',true);
opt = struct('mission',m,'sweep',sweep,'hybrid',hybrid,'rl',rl, ...
    'purerl',purerl,'warmup',warmup,'arms',{arms},'sens',sens);
end
