# 开发状态与下一步

更新时间：2026-09-03

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：叶安
本次修订：周航正（提出名义功率图、在线寻优、接口草图与RL位置澄清需求）
审核：待项目组审核
AI协助：Codex（路线与状态整理；M2 第六轮、第九轮与第十轮独立验收结果回填；2026-09-03问题与接口修订）

## 9月3日进度快照

| 部分 | 状态 | 当前结论 |
|---|---|---|
| 问题与架构 | 0.3修正版已形成，待组内与老师确认 | 已区分名义功率图、隐藏运行对象和在线测量；明确 `v_ref` 为沿轨迹地速参考 |
| 速度/转速比在线寻优 | 代理对象验证已完成 | 单变量 ESC、速度多峰/风场/自适应算法已有可复现实验 |
| Environment与圆周场景 | 代理研究已完成一轮，公共适配未完成 | 恒风、正弦风、双正交风及空速调度有测试；仍需拆分PathCommand、WindTruth和WindMeasurement |
| MOP/MOE 与 Harness | 指标层可用，统一场景接入未完成 | 已能在代理对象上比较算法；尚未接入同一 Plane/PX4 闭环 |
| PX4/Simulink Control 平台 | M2 已放行 | 速度通道、安全层、eta 分配器和日志链可用；下一步 M3 |
| 残差 RL | 已有独立预研，不进入平台结论 | MATLAB 环境接口、Python 对拍、TD3/BC 候选与未见种子评估已完成；隐藏风和 TD3 稳定性仍未解决 |
| Plane 物理建模 | **新增统一工作线，尚未实现** | 已有空速/风场与 PX4 6DOF 片段可复用；仍需统一执行动态、圆周需求、`P(v_air,eta)`、电池/SOC 与适配器 |
| 仓库结构与治理 | 文档口径已收敛，自动检查已加入 | 已建立文档/模块/证据索引、权威关系和历史归档；未进行大规模目录搬迁 |
| 真实数据/SITL/实机 | 尚未开始 | 当前全部节能结果均来自仿真代理数据 |

总体判断：算法与场景探索推进较快，Control 平台已经走到 M2；当前主要缺口不再是“再加一种算法”，而是建立一个所有算法都能共用的 Plane 物理对象，并在统一 Harness 中完成 Wind-Plane-Control 闭环比较。项目现处于**独立模块成果向统一物理闭环集成**的阶段。

## 9月3日问题与接口修订

- 无风仿真扫描得到的是公开名义空速功率图 `P_nom(v_air,eta)`；运行对象允许存在风、转弯、电池、执行动态和参数偏差，形成控制器不可直接读取的 `P_hidden`。
- 在线策略优化的是沿轨迹切向地速参考 `v_ref`，后续增加 `eta_ref`。实际地速、空速和功率由Plane产生，算法不直接设置飞机实际速度或PWM。
- Environment只生成风真值/风测量；Scenario/Path生成任务几何；飞机航向、地速、空速和功率属于Plane输出。接口字典已更新到0.3建议版。
- `wind_field_sched`中的真风 `known` 策略重新明确为Oracle上界；正式因果策略只能使用当前/历史测量。其局部加号风约定接入时必须适配为全仓统一的 `v_air=v_ground-wind`。
- RL位于Control慢层策略插槽，默认形式为 `v_ref=guard(v_base+delta_v_RL)`。它不是独立物理组件，也不是当前统一闭环的前置任务。
- 修正版执行路线已将算法、Plane、Environment和集成Harness拆成可并行工作包；当前只完成文档与边界修订，统一实现仍待开发。

## 仓库治理状态（2026-09-02）

- [`README.md`](README.md) 是文档权威关系入口，[`../modules/README.md`](../modules/README.md) 是模块登记表，[`evidence/README.md`](evidence/README.md) 是证据索引。
- 公共字段以 `architecture/04_interface_dictionary.md` 为准，路线图负责阶段与放行，`interfaces/M*.md` 负责阶段接线，协作文档只解释算法局部接口和适配。
- 2026-08-31工作区清单已归档，旧路径仅保留迁移说明；`tools/check_repo_governance.ps1` 用于检查模块登记、关键链接和过期入口。

## 架构与问题定义（2026-09-02）

新增 [`architecture/01_problem_definition.md`](architecture/01_problem_definition.md) 至 [`architecture/05_verification_traceability.md`](architecture/05_verification_traceability.md)，形成 Wind-Plane-Control-Evaluation 的建议逻辑架构、运行场景、接口字典及需求-MoE/MoP-证据追溯。建议将“固定高度圆周盘旋等待下的在线平均功率最小化”作为待指导教师确认的最终主任务，直线无风速度ESC保留为开发基线；详见待确认的 [`decisions/ADR-001-objective-selection.md`](decisions/ADR-001-objective-selection.md)。

[`decisions/ADR-002-rl-readiness.md`](decisions/ADR-002-rl-readiness.md) 的平台决策仍有效：虽然 `speed_rl_pytorch` 已完成 TD3/BC 独立训练与评估，但正式 RL 平台接入仍暂缓；在统一 Plane 对象、Harness、强基线及未见场景门槛成立前，不作“RL优于基线”结论。M2 的 120 s / `[90,120] s` 核心数值协议保持放行并进入 M3；第十轮在 `71acd56` 按规则 v1.7 独立复跑 52/52 PASS，R9-F1/R9-F2 具备原始复现、针对性负向、既有回归三件套并关闭。功能实现与验收基础设施均 VALIDATED；R2022b 堆损坏单独登记为 OPEN LIMITATION。分层治理的跨项目采用见 Proposed [`ADR-003`](decisions/ADR-003-layered-acceptance-closure-governance.md)，尚待项目组确认。同时按 [`PROJECT_EXECUTION_ROADMAP.md`](PROJECT_EXECUTION_ROADMAP.md) 推进 P0--P4 Plane 物理建模并行工作线。

## 总览：算法与场景模块已有多条证据线，Control 平台完成 M2，Plane 物理对象待建

| 工作线 | 当前状态 | 可作出的结论 | 不能作出的结论 |
|---|---|---|---|
| `modules/ratio_esc` | 可运行的单变量在线 ESC、Simulink 一致性与代理对象验收 | 代理对象上存在受边界约束的因果寻优行为 | 真实 X8 节能、偏航安全、已部署飞控 |
| `modules/speed_esc` | 2026-09-01 并入。平飞速度 ESC（η=1），窗口回归估计为主、解调为对照；14 单元测试、14 组 Python 逐样本复现、6 组 Simulink 一致性、74 性能场景 | 代理功率曲线上速度变量因果寻优行为成立，且与原 Python 方案逐样本一致 | 真实 X8 节能、速度定位全场景达标（63/74，未达标场景如实记录）、实机飞控 |
| `modules/speed_rl_residual` | 2026-09-01 并入。速度基线之上的 TD3 残差修正（虚拟风场/电池/轨迹代理）；11 单元测试、20 未见风种子零硬约束违规 | 代理对象上残差接口可用：可观测风解析残差 -1.25% 功率（19/20 种子）、TD3 恒定风候选 -3.02% | 不规则风下 RL 有效（TD3 候选 0–1/20 种子胜出，如实记录为训练起点）、任何飞行相关结论 |
| `modules/speed_rl_pytorch` | 2026-09-02 并入。speed_rl_residual 环境的 Python/PyTorch 逐行移植（对拍：确定性场景与 MATLAB 12 位小数一致）+ 课程 TD3 / BC 热启动 / 微调训练线（RTX 4060，训练 1730+400 回合）；4 场景 × 20 未见种子评估、全策略零硬约束违规 | Python 对拍口径下：BC 热启动（教师=真值风解析残差，仅用于生成监督数据）不规则可观测风 **-1.91%（20/20 优于固定，超过解析残差 -1.71%）**、缺测 -1.45%（20/20，超过解析 -0.95%）；从零 TD3 课程与 BC+TD3 微调均未胜出（+4~5%），失败定位在 RL 价值估计环节；隐藏风 BC 仍略差于固定（+0.4~0.8%），确认为信息瓶颈 | 隐藏风下有效、任何飞行相关结论、"RL 优于 ESC"；跨引擎（MATLAB/Python）横比仅限同口径对拍 |
| `modules/speed_shift_search` | 2026-09-01 并入。速度优化任务1：平移曲线瞬时跳变黑箱直搜（tracker=Brent+迟滞监测）；16 单元测试、144 幕横评 | 代理曲线上直搜类算法的样本效率/再跟踪/能耗量化：tracker 跳变恢复 9–20 步、全程能耗 0.21%，优于连续 ESC（0.64%）与网格（19.7%） | 真实 X8 节能、实机瞬时跳变假设（实机有速度动态，见 speed_esc） |
| `modules/speed_rugged_search` | 2026-09-01 并入。速度优化任务2：崎岖多峰曲线滤波全局寻优（multistart）；13 单元测试、滤波研究 25 组、20 种子消融 | 对称崎岖代理上"无偏移"量化达成：全局命中 100%、跨种子偏置 −0.044 m/s（门槛 ±0.05）；滤波 argmin 结构偏置已量化（选谷/定位分层依据） | 非对称曲线下的无偏性（对称设计是前提）、2% 噪声下精度极限约 ±0.46 m/s（如实记录） |
| `modules/wind_circle_search` | 2026-09-01 并入。速度优化任务3：恒定风×圆周盘旋，风的航向投影→功率曲线周期平移；EA分级监测(斜率探针+stencil重定位/升级)；19 单元测试、8 门槛 | EA 尾段跟踪误差 0.320 < tracker 0.809，搜索步数 213<261；jumpUp 恢复≥9/10 | 慢漂+风场叠加未单列门槛；个别种子错谷恢复慢（如实记录）；真实 X8 节能 |
| `modules/sin_wind_search` | 2026-09-01 并入。任务4：正弦风 W(t)=A·sin(ωt)+B（A/ω/B 可调），三模块面板(控制台/飞机模型/环境模型)首版；19 单元测试、8 门槛 | 双重时变下 EA 跟踪与步数主张成立；1小时窗 MOE EA 0.978≥0.97 | tracker 能耗占优（0.985，不做全局扫描，如实记录）；真实 X8 节能 |
| `modules/ortho_wind_search` | 2026-09-01 并入。任务5：双正交正弦风 x:A·sin(ω1t)+B / y:C·sin(ω2t)+D，异频拍频式时变；新增升级扫描去趋势与宽幅重定位；19 单元测试、8 门槛 | jumpUp 恢复 10/10 ≤260步（半数≤67）；EA 尾段均值 0.361、19/20 ≤0.85（v*摆幅±0.8口径） | 个别种子 0.6–0.84 滞后带（如实记录）；tracker 能耗占优；真实 X8 节能 |
| `modules/adaptive_search` | 2026-09-02 并入。任务6自适应算法库：spsa占空比随机扰动/bayes GP代理/qnewton割线牛顿(两相制, 新推荐)+双层MOP/MOE(性能量×任务效能分层)；28 单元测试、10 门槛 | qnewton 风场尾段 0.272<tracker 0.805、1h MOE 0.987>ea 0.975；spsa 跳变恢复 10–18 步(ea口径≤260)；bayes settle 8–18 步(定位专长) | bayes 时变尾段跟踪劣于占空比法(如实记录)；tracker 能耗优势来自平坦无噪设计点；真实 X8 节能 |
| `modules/wind_field_sched` | 2026-09-02 并入。路线§3-5交付口径的环境风场调度模块：空速物理P=P0(\|v·t̂+w\|)+解析调度+DP验证+最优匀速对照+可行性+滑窗LM在线风估计+敏感性扫描+三档信息结构；15 单元测试、8 门槛 | DP与解析一致(3.9e-6)；1h窗MOE 已知风1.000>在线0.974>匀速0.964>恒飞0.949>不知风0.938(风速信息价值3.6%)；带宽准则：短窗病态/长窗稳健 | 中频风区估计器谐振区(相位查表为下一步)；代理功率对象不代表真实X8节能 |
| `modules/unified_search` | 2026-09-01 并入。速度优化任务1+2整合：调试二次曲线+对称崎岖+平移调度统一对象，能耗感知算法 ea_multistart，统一 MOP/MOE 评价；13 单元测试、8 门槛 | 计入搜索能耗后全遍历非最优：崎岖静态 1 小时窗 ea 平均 MOE=0.9927 > multistart 0.9924，搜索步数 165 vs 400（20 种子）；jumpUp 恢复 67 步、jumpDown 29 步、dy 零误触发 | 慢漂（ramp）恢复慢于跳变（9/10 种子 ≤1.6，尾部种子如实记录）；演示面板仅 tracker/esc（定稿口径），ea 等其余算法在包内供验收横比；真实 X8 节能 |
| `harness`（指标层） | 2026-09-01 实现。三模块架构（environment/aircraft 黑箱/console）+ 1 小时任务窗 MOP/MOE；4 单元测试 | 统一口径横比成立：MOE_energy=Emin/E_actual，fixed 上界 1.0000、multistart 0.9912、grid 0.9905、esc 0.9819、single_golden 0.9226 | 风场场景（任务3-5 待接入）、真实瓦级标定（Pmin_W 为代理换算） |
| `models/px4_x8` | 阶段 0、M0-A、M0-B、M0-C、M1、M2 核心已放行；第十轮当前提交 52/52 针对性矩阵，功能与验收基础设施 VALIDATED，规则 v1.7 | 干净与脏入口下旁路与原基线零差异；M0-B 安全注入 4/4；M2 S1/S2/S3 = −0.2626%/−0.2938%/−0.2147%；R9-F1 两个原始协同篡改由独立探针以 `ManifestContract` 拒绝，contract 四类负向与全部旧回归通过；8 份日志零 U+FFFD；52 行矩阵绑定 runId `88e0204a` @ `71acd56`，c3 盖章后崩溃无害、c5 盖章前崩溃后 attempt=2 完整重执行成功，双链哈希一致 | R2022b 堆崩溃为 OPEN LIMITATION（本批自然发生两次并被规则正确处理）；report 段崩溃注入未执行；全量同会话双链未覆盖；MATLAB 输出编码属机器区域设置需跨机探针复核；不外推真实功率/风场 |
| Plane 物理建模（P0--P4） | 2026-09-02 纳入路线图，统一组件尚未实现；建议负责人霍奕茗（待组内确认） | `wind_field_sched` 的空速物理对象和 `px4_x8` 的 6DOF/执行器链可复用 | 尚无统一 `P(v_air,eta)`、圆周动力需求、电池/SOC 或与 PX4 的接入结果 |

飞控平台的唯一执行基线是 [`PROJECT_EXECUTION_ROADMAP.md`](PROJECT_EXECUTION_ROADMAP.md)。M0-B 复核缺陷已修复并通过独立再验收（[`evidence/M0B_RERUN_20260901.md`](evidence/M0B_RERUN_20260901.md)、[`evidence/M0B_REACCEPT_CODEX_20260901.md`](evidence/M0B_REACCEPT_CODEX_20260901.md)）。**M0-C、M1 已通过；M2 受约束分配器、ESC 接线和修订数值门槛保持放行。第十轮按 v1.7 四层判定在当前 `71acd56` 由入库驱动独立复跑 52/52 PASS（runId `88e0204a`，五段 attempt=1/1/1/2/1）：R9-F1 的“上限+stamps 协同篡改”和“删除 c5+声明行”两个原始复现均由独立探针以 `air:M2Verify:ManifestContract` 精确拒绝且零伪归档，R9-F2 的 8 份真实批次日志逐码点扫描零 U+FFFD；两项连同 R8-F1 满足关闭三件套。功能实现层与当前冻结验收基础设施层均 VALIDATED；环境层保持 OPEN LIMITATION——c3 盖章后、c5 盖章前各发生一次自然堆崩溃，驱动分别按 fresh done 放行和完整重执行正确处理；全量同会话双链仍未覆盖。证据见 [`evidence/M2_REACCEPT_ROUND10_CODEX_20260903.md`](evidence/M2_REACCEPT_ROUND10_CODEX_20260903.md)。M3 可继续并行推进；不做平台侧 RL。**

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
- M2 第三轮修复与第四轮关闭验证（2026-09-02，[`evidence/M2_REACCEPT_ROUND3_FIX_20260902.md`](evidence/M2_REACCEPT_ROUND3_FIX_20260902.md)）：三入口（单元测试/完整链/九场景试验）函数化并加受控错误注入钩子；真实错误注入矩阵 10/10 PASS（三类错误出口 + 试验独立成功/受控失败均精确恢复调用者状态、persistent fresh、背靠背双链 2/2 且 CSV 逐位一致、门槛值在 ±0.015pp 抖动容差内）；§9.5 的跨会话哈希一致按实测修订为同会话哈希互等 + 数值抖动容差（ulp 指纹机制在案）；同轮固化 `ACCEPTANCE_AUTOMATION_RULES.md` v1.0 并整改四处存量 `M0C_ESC_PARAMS` 渗漏。M2 放行。
- M2 第四轮独立验收（2026-09-02，[`evidence/M2_REACCEPT_ROUND4_CODEX_20260902.md`](evidence/M2_REACCEPT_ROUND4_CODEX_20260902.md)）：仓库验证器内部 10/10 PASS，两次九场景 `pairs.csv` 哈希一致；独立真实探针确认三入口 global 恢复与 persistent fresh（最大差 0），故第三轮核心缺陷关闭。但验证器自身正常返回时清空调用者 global，persistent 检查为间接推断，且 10 行矩阵不是规则 §4.3 的完整组合。修订“自动化完全闭环”为部分通过；M2 核心成果保持放行。
- M2 第四轮修复与关闭验证（2026-09-02，[`evidence/M2_REACCEPT_ROUND4_FIX_20260902.md`](evidence/M2_REACCEPT_ROUND4_FIX_20260902.md)）：验证器入口快照/onCleanup 恢复调用者 global（非空调用者正常与 `'fail'` 注入路径均复验）；persistent fresh 改为前向时间直探（发现并修复原“首次输出对比”式探针因 t=0 重初始化而永真的缺陷，加灵敏度自检）；矩阵补 clean 入口态并全面改称针对性矩阵（15 行，声明=实际），规则升 v1.1；验证器分段执行规避本机 R2022b 单进程长序列堆损坏（崩溃深度 4/8/45 次仿真不等，环境限制如实入档）。15/15 PASS，M2 放行。
- M2 第五轮独立验收（2026-09-02，[`evidence/M2_REACCEPT_ROUND5_CODEX_20260902.md`](evidence/M2_REACCEPT_ROUND5_CODEX_20260902.md)）：按独立进程完整重跑 `c1c2stale/c2clean/c3/c5/report`，15/15 PASS；双链 SHA-256 一致，S1/S2/S3 = −0.2626%/−0.2938%/−0.2147%。负向探针发现四入口只快照有限 Applied 值，NaN/Inf 错误出口变为空；`report` 无同批次/提交绑定，可在 stage 文件不变时复用旧证据返回 PASS；路径断言仅检查 `injected` 字面量。M2 核心维持放行，验收自动化修订为 PARTIAL。
- M2 第五轮修复后的第六轮独立验收（2026-09-02，[`evidence/M2_REACCEPT_ROUND6_CODEX_20260902.md`](evidence/M2_REACCEPT_ROUND6_CODEX_20260902.md)）：`c1c2stale/c2clean/c3` 合计 11/11 PASS，S1/S2/S3 = −0.2626%/−0.2938%/−0.2147%；有限/空/NaN/Inf 四态独立探针 20/20 PASS，R5-F1 关闭。C5 两次均在第二条长链中途退出，正式 39 行矩阵未完成；静态审计发现各 stage 只复制 init manifest 的提交号、未独立核验 HEAD/验证器哈希/dirty 状态，且聚合器未硬断言 CSV verdict 全 PASS。修订“五轮全部闭环”表述：M2 核心保持放行，验收自动化为 PARTIAL。
- M2 第七轮独立验收（2026-09-02，[`evidence/M2_REACCEPT_ROUND7_CODEX_20260902.md`](evidence/M2_REACCEPT_ROUND7_CODEX_20260902.md)）：当前提交 `9cf9805` 下 c1/c2/c3 实际 11/11 PASS；c5 两条最小链完成且哈希一致，但未生成 `c5.csv`/`c5.done.mat`，`report` 负向确认会拒绝缺段批次。当前提交的正式矩阵记为 11/42，验收自动化仍为 PARTIAL；历史 `2d36288` 的 42/42 证据不替代本轮独立复验。
- M2 第七轮发现修复（2026-09-02，[`evidence/M2_REACCEPT_ROUND7_FIX_20260902.md`](evidence/M2_REACCEPT_ROUND7_FIX_20260902.md)）：R7-F1 判定为环境级原生崩溃（`ff34-25df-6880-531c.dmr` 取证：c5 链完成与阶段落盘之间，代码逻辑无法免疫），按"受控韧性 + 诚实记账"修复——段入口 `<stage>.attempts` 计数器（拒记被源码绑定门拒绝的入口）、`done.attempts` 盖章、report 逐段打印、c5 链后 `bdclose` 堆释放、规则 v1.4 有界（3 次）完整重执行重试语义。两次真实进程击杀模拟证明"崩溃→计数存活→重试递增→无假证据"。修复批次 42/42 PASS，runId `e8011d58` @ `fd4ce7c`，各段第 1 次尝试完成，双链哈希与登记值一致；c3 盖章后遇一次堆崩溃退出（0xc0000374），按规则 v1.4(e) 无害放行。清理 Codex 遗留挂死 init 进程（18:07 启动未退出）。
- M2 第八轮独立验收（2026-09-02，[`evidence/M2_REACCEPT_ROUND8_CODEX_20260902.md`](evidence/M2_REACCEPT_ROUND8_CODEX_20260902.md)）：当前 `798f60e` 上独立分段复跑 42/42 PASS，runId `6ade3744`，五段 attempt=1，C5 双链 SHA-256 一致，S1/S2/S3 = −0.2626%/−0.2938%/−0.2147%，核心与数值继续放行。但将 `c5.done.attempts` 篡改为超上限的 4（marker 仍为 1）后 report 仍 42/42 PASS；仓库内也没有实际执行规则 v1.4 的有界重试驱动，attempt 直接截断写还存在崩溃窗口。验收自动化保持 PARTIAL，需关闭 R8-F1/R8-F2/R8-F3。
- M2 第八轮发现修复（2026-09-02，[`evidence/M2_REACCEPT_ROUND8_FIX_20260902.md`](evidence/M2_REACCEPT_ROUND8_FIX_20260902.md)）：R8-F1 attempt 证据升级为硬断言（存在/正整数/`manifest.maxAttempts` 上限/与持久标记一致，六类负向证明入矩阵，42→48 行）；R8-F2 有界重试驱动入库 `tools/run_m2_batch.ps1`（+8 场景驱动层测试）；R8-F3 计数器原子替换写入（pre/mid/post 三窗口钩子实证至多留下旧值或新值，损坏标记硬失败不自愈）。修复期间捕获 matlab 启动器对堆崩溃子进程报 rc=0 的真实活例（`results/batch_runs/20260902_225209` c2clean），驱动判据修正为"新鲜完成证据权威、退出码仅参考"并同步规则 v1.5(a)。正式批次由入库驱动整批重跑 48/48 PASS，runId `72300de6` @ `6f6672c`，c5 第 1 次尝试受控 taskkill 击杀→自动完整重执行→第 2 次成功（`done.attempts=2`），双链哈希与登记值一致（第 5 次跨批复现），门槛值不变。
- M2 第九轮独立验收（2026-09-03，[`evidence/M2_REACCEPT_ROUND9_CODEX_20260903.md`](evidence/M2_REACCEPT_ROUND9_CODEX_20260903.md)）：当前 `2be9857` 由入库驱动复跑 48/48 PASS，runId `1edb644d`，五段 attempt=1，C5 双链哈希一致，S1/S2/S3 = −0.2626%/−0.2938%/−0.2147%；驱动测试 8/8 与原子 marker pre/mid/post/超预算探针通过，R8-F2/R8-F3 关闭。但协同篡改 manifest 上限 + done/marker 后仍 48 PASS，删除 c5 与声明行后仍 44 PASS，新增 R9-F1（P1）：manifest 尚未与源码固定批次合同做等值断言。R8-F1 仅部分关闭，验收自动化保持 PARTIAL；另记 WinPS 5.1 日志中文编码损坏为 P2。
- M2 第九轮发现修复（2026-09-03，[`evidence/M2_REACCEPT_ROUND9_FIX_20260903.md`](evidence/M2_REACCEPT_ROUND9_FIX_20260903.md)）：R9-F1 以单一源码合同 `expectedManifestContract()` 收口——init 写入、段入口/`validateStaged`/聚合器三处等值硬断言（上限等值而非 ≥1、阶段名单/顺序/唯一全等、声明行数逐字段全等，`air:M2Verify:ManifestContract`），四类协同篡改负向（提上限含自洽 stamps/删阶段/增配齐阶段/改行数）进矩阵 48→52 行且错误必须落在合同检查本身；`cloneStaged` 改为合成完整五段 toy 防止既有负向证明被短路。R9-F2：驱动 `Invoke-LoggedNative` 按 ANSI 实际输出页解码写 UTF-8（探针实证 MATLAB -batch 管道原始字节为 GBK），驱动测试增至 9 场景（S8 编码往返零 U+FFFD）。正式批次 52/52 PASS，runId `78281368` @ `3d3fa51`；c2clean 第 1 次尝试**自然**堆崩溃（0xC0000374）→完整重执行→第 2 次成功（attempt=2 如实记账），R8 登记的"自然崩溃—重试—成功"遗留项关闭；批次 8 份日志零 U+FFFD；双链哈希第 7 次跨批复现；门槛值逐位一致。规则升 v1.6（规则 8/9）。
- M2 第十轮独立验收（2026-09-03，[`evidence/M2_REACCEPT_ROUND10_CODEX_20260903.md`](evidence/M2_REACCEPT_ROUND10_CODEX_20260903.md)）：治理提交 `71acd56` 上按 v1.7 四层判定复跑 52/52 PASS，runId `88e0204a`；驱动测试 9/9，R9-F1 两个原始协同篡改独立探针精确拒绝，R9-F2 批次日志 8/8 零 U+FFFD，R9-F1/R9-F2/R8-F1 以关闭三件套 CLOSED。c3 盖章后与 c5 盖章前各自然堆崩溃一次，驱动分别无害放行和 attempt=2 完整重执行成功，归类为环境限制而非功能回归。功能层、当前冻结验收基础设施层 VALIDATED；环境层 OPEN LIMITATION；Proposed ADR-003 待项目组确认。
- M2 第六轮发现修复（2026-09-02，[`evidence/M2_REACCEPT_ROUND6_FIX_20260902.md`](evidence/M2_REACCEPT_ROUND6_FIX_20260902.md)）：R6-F1 源码指纹在 init/段开始/盖章/report 独立现场取证（`git -C` 解耦工作目录、拒 unknown、拒脏树）；R6-F2 聚合器逐行 verdict 硬断言 + FAIL 行负向；R6-F3 C5 收缩为最小双链（nominal S1–S3）。42/42 针对性矩阵 PASS，runId `ff8636ec` @ `2d36288`，双链哈希一致，门槛值在登记抖动内；全量同会话双链仍为环境限制未覆盖组合。规则同步升版 v1.3；治理脚本 BOM 兼容性收口（PS 5.1 可运行）。

### 算法线速度模块证据（2026-09-01 并入）

- `modules/speed_esc`：14 项单元测试、14 组原 Python 逐样本复现（最大误差 5.33e-15）、6 组 MATLAB/Simulink 一致性（最大差 1.25e-14）全部通过；正式种子 11--20 性能验收功率指标 74/74 达标、速度定位指标 63/74（11 个未达标场景多为二次曲线噪声场景，如实列出）。证据：[`evidence/speed_esc/report.md`](evidence/speed_esc/report.md)、[`evidence/speed_esc/scenarios.csv`](evidence/speed_esc/scenarios.csv)。
- `modules/speed_rl_residual`：11 项单元测试与适配器契约通过；20 个未见不规则风种子零硬约束违规；可观测风解析脚本 19/20 种子优于固定基准（平均功率 480.255→474.229 W，约 -1.25%）；TD3 恒定风候选同类场景 477.825→463.379 W（-3.02%），但迁移到不规则风 0/20 胜出，随机恒定风候选 1/20——均为课程训练起点而非最终策略。证据：[`evidence/speed_rl_residual/report.md`](evidence/speed_rl_residual/report.md)、[`evidence/speed_rl_residual/policy_evaluation.csv`](evidence/speed_rl_residual/policy_evaluation.csv)、TD3 检查点 `td3_candidate_*.mat`。
- `modules/speed_rl_pytorch`（2026-09-02）：环境与 MATLAB 对拍——无风/恒定/正弦确定性场景 12 位小数逐位一致，不规则风 20 种子统计一致且 MATLAB 侧复现证据值 480.255/474.229 W；课程 TD3 从零 1730 回合在不规则可观测风 +4.55%（诊断：退化为与风无关固定偏置）；BC 热启动 h8/h32 不规则可观测 -1.91%/-1.97%（20/20）、缺测 -1.45%/-1.35%（20/20，超过解析残差）；BC+TD3 微调劣化至 +4.16%；隐藏风 BC +0.78%/+0.39%（信息瓶颈，最优空速处功率对风一阶敏感度为零）；全部策略零硬约束违规。证据：[`evidence/speed_rl_pytorch/report_final.md`](evidence/speed_rl_pytorch/report_final.md)、[`evidence/speed_rl_pytorch/summary_final.csv`](evidence/speed_rl_pytorch/summary_final.csv)、[`evidence/speed_rl_pytorch/parity_matlab_vs_python.csv`](evidence/speed_rl_pytorch/parity_matlab_vs_python.csv)、候选检查点 `modules/speed_rl_pytorch/checkpoints/`。
- `modules/wind_circle_search`（任务3）：19 项测试、8 项门槛；EA 尾段跟踪 0.320 vs tracker 0.809；证据：[`evidence/wind_circle_search/report.md`](evidence/wind_circle_search/report.md)。
- `modules/sin_wind_search`（任务4）：19 项测试、8 项门槛；正弦风口径 1 小时窗 EA 0.978 / tracker 0.985 / esc 0.970；证据：[`evidence/sin_wind_search/report.md`](evidence/sin_wind_search/report.md)。
- `modules/ortho_wind_search`（任务5）：19 项测试、8 项门槛；双正交风 1 小时窗 EA 0.975 / tracker 0.984 / esc 0.960；jumpUp 恢复 10/10；证据：[`evidence/ortho_wind_search/report.md`](evidence/ortho_wind_search/report.md)。
- `modules/adaptive_search`（任务6）：28 项测试、10 项门槛；qnewton 尾段 0.272 / 1h MOE 0.987 / spsa 恢复 10–18 步；证据：[`evidence/adaptive_search/report.md`](evidence/adaptive_search/report.md)。
- `modules/wind_field_sched`（路线§3-5交付）：15 项测试、8 项门槛；DP验证解析调度 relDiff<4e-6；1h窗三档信息结构 MOE 已知风1.000/在线0.974/不知风0.938（风速信息价值3.6%）；带宽准则：短窗(<半圈)病态、长窗(W≥90)中位超额2.2%；证据：[`evidence/wind_field_sched/report.md`](evidence/wind_field_sched/report.md)。
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
- RL 接口、Python 对拍和 TD3/BC 候选训练已经可运行，但结果仍局限于虚拟代理对象；从零 TD3 和隐藏风场表现存在明确不足，不能宣称强化学习优于 ESC。
- 未接PX4、QGC、SITL/HITL、真实电压电流、螺旋桨台架数据或实机。
- `speed_esc` 的两条速度功率曲线与 `speed_rl_residual` 的风场/电池/轨迹代理均为虚拟对象，三者功率模型互不相同，跨模块不得直接横比节能率；`speed_esc` 速度定位指标 63/74（未全达标）；`speed_rl_residual` 的 TD3 候选在不规则风下尚未胜出基线。`speed_rl_pytorch` 为该环境的 Python 移植（对拍一致），其"BC 超过解析残差"结论仅限同一 Python 引擎、可观测/缺测风口径；隐藏风与从零 TD3 的负结果如实保留；跨 MATLAB/Python 引擎不得直接横比节能率。

## 下一步优先级

1. **R0概念确认**：由周航正组织组内和老师确认ADR-001/ADR-003，冻结主任务、`v_ref`地速语义、名义功率图和在线可见信息。
2. **并行Plane线**：建议霍奕茗负责（待确认），实现最小Plane API、空地速/圆周/执行动态、`P_nom/P_hidden/P_meas`分层、电池与测量链；先独立验收，不直接改主 `.slx`。
3. **并行Environment线**：王健祺已有场景资产，建议继续统一PathCommand、NE风真值、风测量退化和训练/未见场景清单；首先关闭 `wind_field_sched` 的局部加号约定适配。
4. **并行算法/Control线**：将固定、名义调度和速度ESC适配为同一慢层接口；叶安继续M3更新/保持/优先级仲裁和PX4安全门控，Plane通过后再接入 `air_spare.slx`。M3协调方案v0.2（[`interfaces/M3_V_ETA_COORDINATION.md`](interfaces/M3_V_ETA_COORDINATION.md)）已按实施前设计审查（[`evidence/M3_DESIGN_REVIEW_CODEX_20260903.md`](evidence/M3_DESIGN_REVIEW_CODEX_20260903.md)）完成F1–F6文档级整改，待项目组确认§9五项后冻结实施。R9-F1/R9-F2已经第十轮独立关闭，R2022b堆崩溃继续按环境限制管理。
5. **统一Harness汇合**：周航正负责接口与总装，使用同一场景、随机种子、隐藏对象和约束比较固定、名义调度、ESC及Oracle上界；Oracle结果不得写成在线策略结果。
6. **数据与标定线**：用CFD/BEMT、文献或后续台架数据校准Plane参数；将`measuredPower`对接SITL或真实电压、电流与时间戳。真实数据缺失期间保留`estimated/proxy`来源标志，不把校准列作近期已完成项。
7. **RL继续后置**：当前只做接口0.3适配和信息泄漏测试。R0-R4完成且强基线仍有稳定缺口后，才以BC热启动的残差结构重新评审训练；不把RL作为Plane或Environment的前置条件。

## 当前可引用的结果边界

仓库内的验收通过只支持以下表述：

> 在恒推力假设下的归一化代理模型中，所实现的单变量转速比ESC能够在预设噪声、延迟和最优点变化场景下保持有限、受边界约束的在线寻优行为，并与其原生Simulink离散实现一致。

> 在虚拟速度功率代理曲线（二次/三次）上，平飞速度ESC（窗口回归梯度估计）在正式种子下功率指标 74/74 场景达标、速度定位 63/74 场景达标，且与原Python方案逐样本一致；在不规则风场虚拟代理中，可观测风解析残差可在多数未见种子上降低平均代理功率，TD3 残差候选在恒定风场景有效、在不规则风场景尚未超过基线。

不支持“真实八旋翼节能百分比”“已解决偏航影响”“强化学习优于传统控制”或“算法已部署飞控”等表述。
