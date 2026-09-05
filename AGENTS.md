# AGENTS.md

本文件面向在本仓库工作的 AI 编码代理（ZCode、Codex、Claude Code 等），同样适用于人类协作者，是项目的顶层入口文档。开始任何改动前，先按下面的入口读取对应文档，不要凭猜测修改接口。

项目组：周航正、霍奕茗、于跃、叶安、王健祺
本版修订：2026-09-05（按当日「接口定义与验收标准研讨会」更新顶层设计、接口标准与两阶段任务路线）
审核：待项目组审核
AI协助：ZCode（按会议决议重组本文件，待人工复核精简）

## 项目概要

共轴八旋翼（X8）固定高度圆周盘旋的在线能耗优化。核心闭环（2026-09-05 会议确立）：

> 算法侧每个控制周期输出**目标速度 `v_ref`** → 仿真系统执行（惯性、限幅、风扰、电池）并回传**实际速度、位置、功率** → 算法据此调整 → 评价器以 Percent（算法预测最优能耗 vs 实际仿真能耗）验收。

四类内容：

- `modules/`：核心在线算法、搜索与风场研究、强化学习预研；
- `models/`：统一 Plane 物理对象（`+plane`）与 PX4 X8 验证平台（`+x8phys`）；
- `harness/`：统一场景、MOP/MOE 与公平评价；
- `integration/`：算法、Plane 与 Control 的适配接入。

模块清单、生命周期、运行入口与负责人只在 [`modules/README.md`](modules/README.md)；当前进度与可引用结论只在 [`docs/DEVELOPMENT_STATUS.md`](docs/DEVELOPMENT_STATUS.md)；本文件不复制动态清单。

## 当前阶段与任务路线（对外验收口径）

两阶段验收 + 一次汇报，详见 [`docs/SIM_ACCEPTANCE_ROUTE.md`](docs/SIM_ACCEPTANCE_ROUTE.md)：

| 阶段 | 时间 | 内容 | 验收 |
|---|---|---|---|
| S0 冻结 | 9/5–9/7 | 文档评审、R0 概念确认、场景预注册 | 文档与 ADR 冻结 |
| Task 1 开环 | 9/8–9/11 | 基础功能验证：ENV 收口、harness↔Plane 对接、fixed / nominal_sched 直跑 | 接口符合性 + 物理门槛 + Percent 报告 |
| Task 2 闭环 | 9/12–9/18 | 基于上一圈历史数据的闭环优化：ESC / qnewton / 圈级重规划 vs 开环配对横评 | Percent 改进 + 安全链 + 分层报告 |
| 汇报 | 9/19 | 学术表达 | 结论不超出状态页边界 |

算法侧信息结构三步走（每步只放宽一个假设，前一步是后一步的基线与上界）：**① 曲线已知 + 风已知** → 解析最优调度，开环执行（Task 1，Oracle 上界参照）；**② 曲线已知 + 风未知** → 在线风估计 + 解析调度（Task 2）；**③ 曲线未知 + 风未知** → 黑箱在线寻优 ESC / qnewton / RL 残差（Task 2，正式在线策略的默认口径）。详见 [`docs/SIM_ACCEPTANCE_ROUTE.md`](docs/SIM_ACCEPTANCE_ROUTE.md) §2.1。

平台线：M3 第二轮验收 F 项已由第三轮修复关闭（修复方复验），**待项目组独立复验后 M3 代理阶段方可收口**；本机 R2022b 单进程长序列仿真有堆损坏风险，批量验收使用分段模式。

## 接口标准（会议决议摘要）

1. **控制权**：算法侧每控制周期输出目标速度 `v_ref`（后续加 `eta_ref`），不输出加速度、姿态、PWM 等物理量；仿真侧执行并回传实际状态。
2. **保持语义**：两次指令之间，仿真按最近一次 `v_ref` 热运行（零阶保持）。
3. **物理限制（仿真侧职责）**：实际速度一阶惯性（`speed_tau_s=1.0` s）+ 变化率限幅（2 m/s²）+ 定义域夹断 + 风扰动；实际速度不得瞬时跳变。
4. **数据流**：输入仿真 = 场景设置（运动半径 R、风速参考）+ 每周期 `v_ref`；仿真回传 = 实际速度（地速/空速）、位置、功率（及能量、SOC、8 位约束标志）。
5. **解耦**：仿真不读算法内部状态；算法只读带时间戳/有效性标志的测量值，不读真值、未来风或完整功率曲面。
6. **一致性**：NE 坐标系；符号约定 `v_air = v_ground − wind`；字段与单位权威见 [`docs/architecture/04_interface_dictionary.md`](docs/architecture/04_interface_dictionary.md)。

精确签名、字段表、单位与一致性清单见 [`docs/interfaces/SIM_ALGO_INTERFACE.md`](docs/interfaces/SIM_ALGO_INTERFACE.md)（R0 冻结后，接口变更必须走 ADR）。

## 必读文档

| 何时读 | 文档 |
|---|---|
| 不确定文档角色或权威关系 | [`docs/README.md`](docs/README.md)（文档导航、唯一事实来源与更新触发条件） |
| 对外验收、任务路线、Percent 定义 | [`docs/SIM_ACCEPTANCE_ROUTE.md`](docs/SIM_ACCEPTANCE_ROUTE.md) |
| 改动仿真/算法接口 | [`docs/interfaces/SIM_ALGO_INTERFACE.md`](docs/interfaces/SIM_ALGO_INTERFACE.md) → [`docs/architecture/04_interface_dictionary.md`](docs/architecture/04_interface_dictionary.md) |
| 每次开工前 | [`docs/DEVELOPMENT_STATUS.md`](docs/DEVELOPMENT_STATUS.md)（当前状态、已知局限、下一步优先级） |
| 新增、合并或冻结模块 | [`modules/README.md`](modules/README.md)（模块登记表） |
| 改动 ESC / RL 接口 | [`docs/COLLABORATION.md`](docs/COLLABORATION.md)（接口签名与因果约定） |
| 涉及飞控平台线 | [`docs/PROJECT_EXECUTION_ROADMAP.md`](docs/PROJECT_EXECUTION_ROADMAP.md)（唯一执行基线）与 `docs/interfaces/M0A`–`M3` 各阶段接口 |
| 进行 R0 决策或验收治理 | [`docs/decisions/`](docs/decisions/)（ADR-001、ADR-003、ADR-004） |
| 需要引用已核验事实 | [`docs/evidence/`](docs/evidence/)（只有这里的内容可作为结论引用） |

## 环境

MATLAB R2022b；运行 Simulink 模型需要 Simulink；运行 RL 接口需要 Reinforcement Learning Toolbox。各模块完整运行入口见 [`modules/README.md`](modules/README.md)；最常用验收入口：

```matlab
cd modules/ratio_esc && run_acceptance       % 提交前必须全绿
cd ../speed_esc && run_speed_acceptance
cd ../speed_rl_residual && run_checks(false)  % 提交前必须全绿
cd ../../harness && run_harness               % 指标层单元测试 + 1小时窗MOE横比
cd ../models/plane && run_plane_acceptance    % Plane P0-P4 契约
```

飞控平台线改动至少运行：

```matlab
cd models/px4_x8
test_m0c_esc_unit
test_m0c_installer_dirty_guard
run_air_m0c_trials
run_air_m1_robustness
test_m2_eta_esc_unit
run_air_m2_trials
run_air_m0a_baseline_compare
```

换新机器后的第一件事：先跑通对应模块的验收脚本确认基线为绿，再开始任何修改。

## 硬性红线

1. **因果边界**：控制器与 RL 观测只能接收测量功率、实际被控量（转速比或平飞速度）、采样时间和有效性标志；完整功率曲线、真实最优点、解析梯度、风真值与未来风不得进入控制器或 RL 观测。
2. **接口冻结**：[`docs/interfaces/SIM_ALGO_INTERFACE.md`](docs/interfaces/SIM_ALGO_INTERFACE.md) 经 R0 冻结后，签名、字段、单位或符号约定的变更必须新增 ADR 并同步接口字典与受影响适配器测试；物理对象升级只替换对象侧（`power_map` / `plant_advance` / `measure` 的等价层，或整体替换 Plane/X8PHYS 对象），不得修改接口签名。
3. **结论边界**：仓库内验收结果只支持 [`docs/DEVELOPMENT_STATUS.md`](docs/DEVELOPMENT_STATUS.md)「当前可引用的结果边界」所列表述；不得宣称真实节能百分比、偏航安全、RL 优于 ESC 或已部署飞控；Percent 结论一律标注 V1 桌面仿真等级。
4. **版本控制**：不提交 `slprj/`、`*.slxc`、临时动画帧、重复日志、本地自动保存文件（见 `.gitignore`）。

## 验收基础设施规则

改动验收入口、验收链或全局量状态管理时，必须遵循 [`docs/ACCEPTANCE_AUTOMATION_RULES.md`](docs/ACCEPTANCE_AUTOMATION_RULES.md)。三条硬要求：

1. 验收入口必须是**函数**并返回机器可查的 `result`；链内每一段必须硬断言，禁止只打印 FAIL。
2. 写全局量的入口必须「快照 → 规范化 → onCleanup 恢复（成功与错误路径）」；新增全局量先登记 `ACCEPTANCE_AUTOMATION_RULES.md` §7 注册表。
3. 清理/恢复/确定性等运行时声明只能以**真实注入失败的测试**为证；数值结论同时报告裕量与抖动（Percent 报告同样适用）。

跨模块验收统一采用 ADR-003 分层治理：分别报告功能实现、验收基础设施、环境限制和文档证据；缺陷关闭必须保留原始复现、针对性负向和既有回归证据。

## 提交约定

- 提交前运行对应模块的验收脚本；涉及面板或导出的修改，再运行对应 `qa_*`。
- 修改仓库结构、文档入口、模块登记或主要状态后，运行 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_repo_governance.ps1`。
- `.slx` 为二进制文件、不可合并：同一模型文件同一时间只在一条分支上修改；两条工作线避免并行改动同一个模型。
- 文档用中文；提交信息简明说明改动属于哪条工作线（沿用现有英文提交风格亦可）。
- 新增或大改文件须按 [`docs/AUTHORSHIP.md`](docs/AUTHORSHIP.md) 记录真实负责人、贡献者、审核状态和 AI 协助；不得用 Git 提交账号代替实际署名，也不得给未参与者虚构贡献。

## 会话记录与交接（跨 agent 连续性）

1. 每次有实际改动的工作会话结束前，新增 `docs/worklog/YYYY-MM-DD-主题.md` 交接简报（模板见 [`docs/worklog/README.md`](docs/worklog/README.md)）；只提交提炼后的要点，不提交 agent 对话原文、原始终端日志或超长运行输出。
2. 仅在状态发生变化时回写 [`docs/DEVELOPMENT_STATUS.md`](docs/DEVELOPMENT_STATUS.md)：模块生命周期、阶段放行、可引用结果、主要局限或下一步优先级发生变化才更新。

新会话的推荐启动顺序：读本文件 → 读 `DEVELOPMENT_STATUS.md` → 需要背景时回溯 `docs/worklog/`。
