# 开发状态与下一步

## 架构与问题定义（2026-09-01）

新增 [`architecture/01_problem_definition.md`](architecture/01_problem_definition.md) 至 [`architecture/05_verification_traceability.md`](architecture/05_verification_traceability.md)，形成 Wind-Plane-Control-Evaluation 的建议逻辑架构、运行场景、接口字典及需求-MoE/MoP-证据追溯。建议将“固定高度圆周盘旋等待下的在线平均功率最小化”作为待指导教师确认的最终主任务，直线无风速度ESC保留为开发基线；详见待确认的 [`decisions/ADR-001-objective-selection.md`](decisions/ADR-001-objective-selection.md)。

[`decisions/ADR-002-rl-readiness.md`](decisions/ADR-002-rl-readiness.md) 已记录当前决策：正式RL开发暂缓，现有 `speed_rl_residual` 仅保留为接口预研和候选插件；在任务口径、功率对象、统一接口、Harness、强基线及未见场景门槛成立前，不扩大训练或作“RL优于基线”结论。该架构文档不改变平台唯一执行路线的当前顺序。M2 的 120 s / `[90,120] s` 修订协议已通过多轮复验，第三轮在原样脏入口下背靠背完整链 2/2 PASS 且九场景 CSV 逐位一致；链尾 `result.pass` 硬断言也通过负向证明。但第三轮真实受控断言失败发现：脚本工作区中的 `onCleanup` 在异常退出时没有恢复调用者 global，第二轮关于“错误路径全部关闭”的结论被修订（[`evidence/M2_REACCEPT_ROUND3_CODEX_20260902.md`](evidence/M2_REACCEPT_ROUND3_CODEX_20260902.md)）。M2 数值与正常路径通过、工程自动化部分通过；M3 接口设计可以继续，`.slx` 结构集成暂缓。

## 总览：算法线三模块并行，平台线已完成 M0-C 接口集成、M1 鲁棒性验收与 M2 eta 分配器

| 工作线 | 当前状态 | 可作出的结论 | 不能作出的结论 |
|---|---|---|---|
| `modules/ratio_esc` | 可运行的单变量在线 ESC、Simulink 一致性与代理对象验收 | 代理对象上存在受边界约束的因果寻优行为 | 真实 X8 节能、偏航安全、已部署飞控 |
| `modules/speed_esc` | 2026-09-01 并入。平飞速度 ESC（η=1），窗口回归估计为主、解调为对照；14 单元测试、14 组 Python 逐样本复现、6 组 Simulink 一致性、74 性能场景 | 代理功率曲线上速度变量因果寻优行为成立，且与原 Python 方案逐样本一致 | 真实 X8 节能、速度定位全场景达标（63/74，未达标场景如实记录）、实机飞控 |
| `modules/speed_rl_residual` | 2026-09-01 并入。速度基线之上的 TD3 残差修正（虚拟风场/电池/轨迹代理）；11 单元测试、20 未见风种子零硬约束违规 | 代理对象上残差接口可用：可观测风解析残差 -1.25% 功率（19/20 种子）、TD3 恒定风候选 -3.02% | 不规则风下 RL 有效（TD3 候选 0–1/20 种子胜出，如实记录为训练起点）、任何飞行相关结论 |
| `modules/speed_shift_search` | 2026-09-01 并入。速度优化任务1：平移曲线瞬时跳变黑箱直搜（tracker=Brent+迟滞监测）；16 单元测试、144 幕横评 | 代理曲线上直搜类算法的样本效率/再跟踪/能耗量化：tracker 跳变恢复 9–20 步、全程能耗 0.21%，优于连续 ESC（0.64%）与网格（19.7%） | 真实 X8 节能、实机瞬时跳变假设（实机有速度动态，见 speed_esc） |
| `modules/speed_rugged_search` | 2026-09-01 并入。速度优化任务2：崎岖多峰曲线滤波全局寻优（multistart）；13 单元测试、滤波研究 25 组、20 种子消融 | 对称崎岖代理上"无偏移"量化达成：全局命中 100%、跨种子偏置 −0.044 m/s（门槛 ±0.05）；滤波 argmin 结构偏置已量化（选谷/定位分层依据） | 非对称曲线下的无偏性（对称设计是前提）、2% 噪声下精度极限约 ±0.46 m/s（如实记录） |
| `modules/unified_search` | 2026-09-01 并入。速度优化任务1+2整合：调试二次曲线+对称崎岖+平移调度统一对象，能耗感知算法 ea_multistart，统一 MOP/MOE 评价；13 单元测试、8 门槛 | 计入搜索能耗后全遍历非最优：崎岖静态 1 小时窗 ea 平均 MOE=0.9927 > multistart 0.9924，搜索步数 165 vs 400（20 种子）；jumpUp 恢复 67 步、jumpDown 29 步、dy 零误触发 | 慢漂（ramp）恢复慢于跳变（9/10 种子 ≤1.6，尾部种子如实记录）；演示面板仅 tracker/esc（定稿口径），ea 等其余算法在包内供验收横比；真实 X8 节能 |
| `harness`（指标层） | 2026-09-01 实现。三模块架构（environment/aircraft 黑箱/console）+ 1 小时任务窗 MOP/MOE；4 单元测试 | 统一口径横比成立：MOE_energy=Emin/E_actual，fixed 上界 1.0000、multistart 0.9912、grid 0.9905、esc 0.9819、single_golden 0.9226 | 风场场景（任务3-5 待接入）、真实瓦级标定（Pmin_W 为代理换算） |
| `models/px4_x8` | 阶段 0、M0-A、M0-B、M0-C、M1 已放行；M2 数值与正常成功路径通过、异常恢复未通过（第三轮部分通过） | 脏入口下旁路与原基线零差异；M0-B 安全注入 4/4；M2 修订协议（120 s、[90,120] 收敛末窗、门槛不变）下 S1/S2/S3 = −0.26%/−0.29%/−0.23%，第三轮同会话背靠背双链 2/2 且 CSV 哈希一致；链尾 `result.pass` 硬断言成立 | 脚本内 `onCleanup` 在真实断言错误后不恢复调用者 global，不能宣称异常路径一键闭环；不外推真实功率/风场；esc 中心收敛受 PWM 量化分辨率限制 |

飞控平台的唯一执行基线是 [`PROJECT_EXECUTION_ROADMAP.md`](PROJECT_EXECUTION_ROADMAP.md)。M0-B 复核缺陷已修复并通过独立再验收（[`evidence/M0B_RERUN_20260901.md`](evidence/M0B_RERUN_20260901.md)、[`evidence/M0B_REACCEPT_CODEX_20260901.md`](evidence/M0B_REACCEPT_CODEX_20260901.md)）。**M0-C 已通过验收（[`evidence/M0C_TRIALS_20260901.md`](evidence/M0C_TRIALS_20260901.md)），M1 已通过验收（[`evidence/M1_ROBUSTNESS_20260901.md`](evidence/M1_ROBUSTNESS_20260901.md)）。M2 的受约束分配器、ESC 接线和修订后数值门槛通过；第三轮复验 [`evidence/M2_REACCEPT_ROUND3_CODEX_20260902.md`](evidence/M2_REACCEPT_ROUND3_CODEX_20260902.md) 确认脏入口背靠背双链与链尾硬断言，但重新打开脚本异常退出恢复问题。当前 M3 只继续接口、仲裁与场景设计；`.slx` 结构集成等待第四轮关闭异常清理**；不做 RL。

**独立复验确认（2026-09-01，`00fd67e`）**：基线、四个速度场景、四类故障注入均实际复跑通过；另在保存快照上验证姿态保护和完整功率故障恢复（9.001 s 释放 fallback、11 s 回到 active/9 m/s）。详细证据与非阻塞建议见 [`evidence/M0B_REACCEPT_CODEX_20260901.md`](evidence/M0B_REACCEPT_CODEX_20260901.md)。M0-B 阶段可放行；M0-C 开始实现成本窗口前须统一路线中状态 1/2 的歧义，排除 warmup、仅使用满足稳定条件的 active 样本。通过范围限于当前模型的速度通道及监视器/参考回退，不扩展为真实飞行安全或真实节能结论。

### 已验证的模型平台证据

- `air.slx`：MATLAB R2022b 手动更新、仿真 0--10 s 成功，10001 个样本；摘要见 [`evidence/air_baseline_20260831_161623_summary.csv`](evidence/air_baseline_20260831_161623_summary.csv)。
- 接口审计：1 个 6DOF 块、59 条端口连接；见 [`evidence/air_interface_20260831_164903_port_connectivity.csv`](evidence/air_interface_20260831_164903_port_connectivity.csv)。
- `air_spare.slx`：M0-A 观测层完整——速度、PWM、8 维 RPM 估算、`P_est`/`E_est`（未校准估算，来源标志 0）、8 位约束标志、35 维统一日志总线与 `optimizer_enable=0` 基线模式。
- M0-A 历史验收（2026-08-31）：三个命名信号逐样本最大差 0，见 [`evidence/air_m0a_baseline_compare_20260831_201430.csv`](evidence/air_m0a_baseline_compare_20260831_201430.csv)；稳定快照 `models/px4_x8/air_m0a.slx`。2026-09-01 发现旧脚本将 DCM 误标为 `Ve`；本次已额外核验当前 M0-B 旁路下真正的 `[10001 3]` 惯性速度，与 `air` 差异仍为 0，详见独立复核报告。
- M0-B 修复与再验收（2026-09-01，[`evidence/M0B_RERUN_20260901.md`](evidence/M0B_RERUN_20260901.md)）：flags_raw 链路修复后逐位注入位 1/4/6/7 全链"触发→frozen 0.000 s→fallback 0.500 s→（位 6）恢复"；速度验收双口径——名义（roll 正弦置 0）9 m/s 均值误差 0.032 m/s、失跟 0%，扰动 5/9 m/s 1.615/1.598 m/s（与复核复跑一致）；旁路比对修正 `Ve` 端口后三信号差 0。稳定快照 `models/px4_x8/air_m0b.slx` 已替换为修复版。
- M0-C 验收（2026-09-01，[`evidence/M0C_TRIALS_20260901.md`](evidence/M0C_TRIALS_20260901.md)）：`ratioesc` 内核白名单封装 `m0c_vref_esc`（输入仅 t/v/P_e/E_e/attitude/flags，输出仅 v_ref），Interpreted MATLAB Fcn + 每输入 0.05 s ZOH 接入 selector 入 3；成本窗口按 status==2 且位 5 静默口径；三组名义配对（7/9/11 m/s）esc 均收敛（4/4/8 s）、无饱和无触发，复现组逐样本差 0；配对能量按相同连续 `[20,30] s` 网格重算后 `|ΔE|≤0.00013%`（平坦功率面，无可宣称节能）；安装器脏模型保护、旁路差 0 与注入回归（含 13 s 恢复）全绿。稳定快照 `models/px4_x8/air_m0c.slx`。
- M1 鲁棒性验收（2026-09-01，[`evidence/M1_ROBUSTNESS_20260901.md`](evidence/M1_ROBUSTNESS_20260901.md)）：27 场景矩阵（名义/5 种子 2% 噪声/0.5 s 时延/基线正弦扰动/三种子组合/四类噪声背景故障注入），全程内存注入零 `.slx` 变更；R0/WN/DL 组 8 位约束标志与 frozen/fallback 全程为零（保护链无误报）；esc 收敛 4–20 s（噪声放慢收敛，如实记录）；11 组配对 regret 最大 |0.000133%| ≪ 3% 门槛（平坦面，仅证明机制未变坏）；DL 确定性差 0；F1–F4 时序与 M0-B 验收一致且 pre 窗 8 位静默。成本统计保持注入点上游真实功率日志口径。
- M1 独立复验（2026-09-01，[`evidence/M1_REACCEPT_CODEX_20260901.md`](evidence/M1_REACCEPT_CODEX_20260901.md)）：平台线 6 个验收入口实际复跑全绿，M1 27/27 场景、11/11 配对与 4/4 故障回归通过。复验发现原 M1 证据中“DL1 与 R0 逐样本一致”措辞过强：实际 `max|dv_ref|=3.2757e-05 m/s`，严格为 0 的是 DL1/DL2 确定性复现；该表述问题不推翻 M1 PASS，证据措辞与各入口文档阶段状态已于同日修正（worklog `2026-09-01-zcode-m1-reaccept-fixes.md`）。
- M2 eta 分配器验收（2026-09-01，[`evidence/M2_ETA_20260901.md`](evidence/M2_ETA_20260901.md)）：受约束 PWM 域分配器在 `Attitude Control` 出 2 分接（η=1 恒等快速路径，旁路回归差精确 0），`ratioesc` 内核原生转速比接线（eta 经全局量交接，避免跨率依赖破坏位精确旁路）；9 场景配对（fixed 0.8/1.0/1.2 + esc 三初值 + 扰动对 + 复现组），能量门槛 S1/S2/S3 = +0.37%/−0.29%/+0.49%（≤ +0.5%），功率面实测 η=0.8/1.2 比 η=1 高 +1.59%/+0.98%（模型估算口径），复现差 0，零冻结/回退/饱和，偏航扰动 ΔM_z 名义为 0；esc 中心收敛速度受量化分辨率限制如实记录（30 s 末端 0.887/1.145，单调向 1.0）。快照 `models/px4_x8/air_m2.slx`。
- M2 独立复验（2026-09-01，[`evidence/PROJECT_REACCEPT_CODEX_20260901.md`](evidence/PROJECT_REACCEPT_CODEX_20260901.md)）：清理 M2 状态后旁路差 0，安全注入 4/4；九场景 S3 = +0.506190% 超过 +0.5% 门槛，并发现单元测试全局状态污染、量化测试与描述不匹配、部分文档门槛未进入总 PASS。
- M2 复验修复与 3 会话复验（2026-09-01，[`evidence/M2_REACCEPT_FIX_20260901.md`](evidence/M2_REACCEPT_FIX_20260901.md)）：根因定位为 uint16 舍入边界上的会话级 ulp 抖动（±0.015pp）叠加 S1/S3 接近段惩罚骑线；预注册协议修订（120 s 时程、[90,120] 收敛末窗、±0.5% 门槛不变）后 3 个新会话 3/3 全链 PASS，门槛窗最差 −0.22617%（裕量 0.73pp），单元测试自隔离经无清理链验证；unified_search 验收入口同步硬失败化。M2 恢复放行。
- M2 第二轮独立复验（2026-09-01，[`evidence/M2_REACCEPT_ROUND2_CODEX_20260901.md`](evidence/M2_REACCEPT_ROUND2_CODEX_20260901.md)）：干净状态下完整链额外复跑通过，S1/S2/S3 与修复报告逐位一致；`unified_search` 13/13 单元、8/8 门槛、`passed=1`。但承接仓库自身旧 M2 试验状态时，单元测试后旁路 `pwm_cmd` 差 2，实值 `M2_ETA_APPLIED=0.99914776890319873`；另发现会话链未断言九场景 `result.pass`。因此修订上一条“问题全部关闭”的强结论：数值协议保留 PASS，工程自动化为部分通过。
- M2 第二轮复验修复与关闭验证（2026-09-01，[`evidence/M2_REACCEPT_ROUND2_FIX_20260901.md`](evidence/M2_REACCEPT_ROUND2_FIX_20260901.md)）：链入口规范化 + onCleanup 恢复（调用者状态保留）、试验脚本自清理、链尾硬断言 `result.pass`（负向证明触发 `air:M2Session:TrialsFailed`）、单元测试统一 cleanup 含错误路径；第二轮报告 §9 五条关闭条件逐条验证通过——脏入口（原样复现状态）链 PASS、同会话背靠背双链 2/2、九场景数据与既往四方逐位一致。M2 放行，进入 M3。
- M2 第三轮独立复验（2026-09-02，[`evidence/M2_REACCEPT_ROUND3_CODEX_20260902.md`](evidence/M2_REACCEPT_ROUND3_CODEX_20260902.md)）：原样脏入口背靠背双链 2/2 PASS，九场景 CSV 哈希一致，链尾 `air:M2Session:TrialsFailed` 负向证明通过；但真实 U1/compare 断言失败后，单元测试和完整链均未恢复入口 global，证明脚本工作区 `onCleanup` 的错误路径未闭环。修订上一条“全部关闭”：M2 数值与正常路径通过，工程自动化部分通过。

### 算法线速度模块证据（2026-09-01 并入）

- `modules/speed_esc`：14 项单元测试、14 组原 Python 逐样本复现（最大误差 5.33e-15）、6 组 MATLAB/Simulink 一致性（最大差 1.25e-14）全部通过；正式种子 11--20 性能验收功率指标 74/74 达标、速度定位指标 63/74（11 个未达标场景多为二次曲线噪声场景，如实列出）。证据：[`evidence/speed_esc/report.md`](evidence/speed_esc/report.md)、[`evidence/speed_esc/scenarios.csv`](evidence/speed_esc/scenarios.csv)。
- `modules/speed_rl_residual`：11 项单元测试与适配器契约通过；20 个未见不规则风种子零硬约束违规；可观测风解析脚本 19/20 种子优于固定基准（平均功率 480.255→474.229 W，约 -1.25%）；TD3 恒定风候选同类场景 477.825→463.379 W（-3.02%），但迁移到不规则风 0/20 胜出，随机恒定风候选 1/20——均为课程训练起点而非最终策略。证据：[`evidence/speed_rl_residual/report.md`](evidence/speed_rl_residual/report.md)、[`evidence/speed_rl_residual/policy_evaluation.csv`](evidence/speed_rl_residual/policy_evaluation.csv)、TD3 检查点 `td3_candidate_*.mat`。
- `modules/unified_search`：13 项单元测试、8 项验收门槛通过（含"ea 搜索步数 < multistart 全遍历步数（全部种子）""1 小时窗 ea 平均 MOE > multistart 平均 MOE"两条能耗感知主张门槛；tracker 平坦无噪 jumpDown 恢复 ≤30 步 ≥9/10 种子；能耗开关=关时 MOE 与能耗列全部 NaN）。1 小时窗横比：ea_multistart 平均 MOE 0.9927（0.9905–0.9938）、multistart 0.9924、fixed 1.0000（不可达上界）。证据：[`evidence/unified_search/report.md`](evidence/unified_search/report.md)、[`evidence/unified_search/scenarios.csv`](evidence/unified_search/scenarios.csv)、[`evidence/unified_search/moe_1h.csv`](evidence/unified_search/moe_1h.csv)。

## 已完成

- 问题定义：在满足恒推力假设的代理对象上，在线最小化上下桨转速比对应的归一化功率。
- 五阶段演示：静态对象、固定参考反馈、微扰观察、在线ESC、RL环境接口验证。
- 因果边界：ESC和RL观测均不可读取完整功率曲线、真实最优点或解析梯度。
- 鲁棒性测试：多初值、噪声、测量延迟、隐藏最优点变化、边界、冻结和无效样本。
- Simulink：原生离散块展开微扰、高通、解调、低通、下降、投影和限速；与MATLAB健康测量仿真逐采样点一致。
- 协作材料：交互面板、模型结构图、过程动画、可读报告、测试与自动验收脚本。

## 已知局限

- `J = 1 + 4(eta - eta_optimum)^2` 是代理曲线，不是实验功率数据。
- 当前“恒推力”是建模假设，尚未通过控制分配计算实际总推力、偏航力矩或八电机饱和。
- Simulink一致性目前覆盖健康测量信号；冻结和无效数据恢复在MATLAB控制器API中验证。
- RL接口已经可运行，但没有训练策略，不能以此宣称强化学习优于ESC。
- 未接PX4、QGC、SITL/HITL、真实电压电流、螺旋桨台架数据或实机。
- `speed_esc` 的两条速度功率曲线与 `speed_rl_residual` 的风场/电池/轨迹代理均为虚拟对象，三者功率模型互不相同，跨模块不得直接横比节能率；`speed_esc` 速度定位指标 63/74（未全达标）；`speed_rl_residual` 的 TD3 候选在不规则风下尚未胜出基线。

## 下一步优先级

1. 先关闭 M2 第三轮 R3-F1/R3-F2：把链、试验和单元测试入口函数化（或显式 catch-cleanup-rethrow），真实覆盖 compare/injection/trials 错误出口并证明 global/persistent 恢复；同时可继续 M3 两个 ESC 的更新/保持/优先级仲裁、稳定窗口、约束总线和同场景比较方案文档，暂不改 `.slx`。
2. 用台架、CFD/BEMT或文献校准数据替换代理功率对象，明确参数来源、适用区间和误差。
3. 建立给定总推力与零偏航力矩条件下的上下桨分配器，输出可行性、饱和和约束违规标志。
4. 将 `measuredPower` 对接真实或SITL的电压、电流与时间戳；加入日志回放测试。
5. 在固定的训练/验证场景划分下训练TD3等策略，并与ESC、固定比值基线使用同一扰动和评价口径比较（`speed_rl_residual` 的课程训练与未见种子评估口径可直接沿用）。
6. 再考虑速度寻优与转速比寻优的交替或多频耦合，不能在单变量对象未标定前宣称二维优化成果。
7. 评估是否用 `modules/speed_esc` 的回归估计器内核替换 `M0C v Ref ESC` 中的解调内核，并按 `M0C_SPEED_ESC.md` §7 重新验收。

## 当前可引用的结果边界

仓库内的验收通过只支持以下表述：

> 在恒推力假设下的归一化代理模型中，所实现的单变量转速比ESC能够在预设噪声、延迟和最优点变化场景下保持有限、受边界约束的在线寻优行为，并与其原生Simulink离散实现一致。

> 在虚拟速度功率代理曲线（二次/三次）上，平飞速度ESC（窗口回归梯度估计）在正式种子下功率指标 74/74 场景达标、速度定位 63/74 场景达标，且与原Python方案逐样本一致；在不规则风场虚拟代理中，可观测风解析残差可在多数未见种子上降低平均代理功率，TD3 残差候选在恒定风场景有效、在不规则风场景尚未超过基线。

不支持“真实八旋翼节能百分比”“已解决偏航影响”“强化学习优于传统控制”或“算法已部署飞控”等表述。
