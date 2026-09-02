# AGENTS.md

本文件面向在本仓库工作的 AI 编码代理（Codex、ZCode、Claude Code 等），同样适用于人类协作者。开始任何改动前，先按下面的入口读取对应文档，不要凭猜测修改接口。

## 项目概要

共轴八旋翼（X8）在线能耗优化研究仓库，由四类可独立推进的内容组成：

- `modules/`：核心在线算法、搜索与风场研究、强化学习预研；
- `models/`：PX4 X8 Control平台与后续Plane物理对象；
- `harness/`：统一场景、MOP/MOE和公平评价；
- `integration/`：算法、Plane与Control的适配接入。

全部模块名称、生命周期、运行入口、证据和负责人登记只在 [`modules/README.md`](modules/README.md) 维护。当前进度只在 [`docs/DEVELOPMENT_STATUS.md`](docs/DEVELOPMENT_STATUS.md) 维护；不要在本文件复制模块计数或实验结果。

平台注意事项：`models/px4_x8` 当前 M2 已放行，下一步为 M3；本机 R2022b 单进程长序列仿真有堆损坏风险，批量验收使用 `verify_m2_round4_closure` 的分段模式。

## 必读文档

| 何时读 | 文档 |
|---|---|
| 不确定文档角色或权威关系 | `docs/README.md`（文档导航、唯一事实来源与更新触发条件） |
| 每次开工前 | `docs/DEVELOPMENT_STATUS.md`（当前状态、已知局限、下一步优先级） |
| 新增、合并或冻结模块 | `modules/README.md`（模块登记表） |
| 改动 ESC / RL 接口 | `docs/COLLABORATION.md`（接口签名与因果约定） |
| 涉及飞控平台线 | `docs/PROJECT_EXECUTION_ROADMAP.md`（唯一执行基线）与 `docs/interfaces/M0A_OBSERVABILITY.md` |
| 改动速度 ESC / 残差 RL 模块 | `modules/speed_esc/docs/`（整合说明、数据与RL边界、验证记录）、`modules/speed_rl_residual/docs/`（接口契约、验证记录） |
| 需要引用已核验事实 | `docs/evidence/`（只有这里的内容可作为结论引用） |

## 环境

MATLAB R2022b；运行 Simulink 模型需要 Simulink，运行 RL 接口需要 Reinforcement Learning Toolbox。

```matlab
cd modules/ratio_esc
run_acceptance   % 提交前必须全绿
qa_ui            % 改动交互面板或导出逻辑时额外运行
run_demo         % 生成 A--E 阶段结果图与动画

cd ../speed_esc
run_speed_acceptance  % 单元、Python复现、Simulink一致性与74场景性能验收
run_speed_demo        % 两类曲线×三版本与解调对照图表
qa_speed_ui           % 改动面板时额外运行

cd ../speed_rl_residual
run_checks(false)     % 单元测试、适配器契约与20个不规则风种子（提交前必须全绿）
run_checks(true)      % 另外执行 1 回合 TD3 训练冒烟
run_demo              % 圆周+正弦风接口演示

cd ../speed_shift_search
tests_task1               % 16项单元测试
run_task1_acceptance      % 144幕横评验收
qa_task1_demo             % 改动面板时额外运行

cd ../speed_rugged_search
tests_task2               % 13项单元测试
run_task2_acceptance      % 滤波研究+消融+门槛验收
qa_task2_demo             % 改动面板时额外运行

cd ../../harness
run_harness               % 指标层单元测试 + 1小时窗MOE横比
```

换新机器后的第一件事：先跑通对应模块的验收脚本确认基线为绿，再开始任何修改。

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
run_air_m0b_safety_injection
```

## 硬性红线

1. **因果边界**：控制器与 RL 观测只能接收测量功率、实际被控量（转速比或平飞速度）、采样时间和有效性标志；完整功率曲线、真实最优点、解析梯度不得进入控制器或 RL 观测。
2. **对象升级位置**：物理对象升级只替换 `power_map`、`plant_advance`、`measure`（约束量在对象侧输出 `constraint_flags`），不得修改 ESC 的因果接口签名。
3. **结论边界**：仓库内验收结果只支持 `docs/DEVELOPMENT_STATUS.md` "当前可引用的结果边界"所列表述；不得在任何文档或对外输出中宣称真实节能百分比、偏航安全、RL 优于 ESC 或已部署飞控。
4. **版本控制**：不提交 `slprj/`、`*.slxc`、临时动画帧、重复日志、本地自动保存文件（见 `.gitignore`）。

## 验收基础设施规则

改动验收入口、验收链或全局量状态管理时，必须遵循 [`docs/ACCEPTANCE_AUTOMATION_RULES.md`](docs/ACCEPTANCE_AUTOMATION_RULES.md)。三条硬要求：

1. 验收入口必须是**函数**并返回机器可查的 `result`；链内每一段必须硬断言，禁止只打印 FAIL。
2. 写全局量的入口必须"快照 → 规范化 → onCleanup 恢复（成功与错误路径）"；新增全局量先登记 `ACCEPTANCE_AUTOMATION_RULES.md` §7 注册表。
3. 清理/恢复/确定性等运行时声明只能以**真实注入失败的测试**为证；验收基础设施修复必须跑全"入口状态 × 退出路径"覆盖矩阵，数值结论同时报告裕量与抖动。

## 提交约定

- 提交前运行 `run_acceptance`；涉及面板或导出的修改，再运行 `qa_ui`。
- `.slx` 为二进制文件、不可合并：同一模型文件同一时间只在一条分支上修改；两条工作线避免并行改动同一个模型。
- 文档用中文；提交信息简明说明改动属于哪条工作线（沿用现有英文提交风格亦可）。
- 新增或大改文件须按 [`docs/AUTHORSHIP.md`](docs/AUTHORSHIP.md) 记录真实负责人、贡献者、审核状态和AI协助；不得用Git提交账号代替实际署名，也不得给未参与者虚构贡献。

## 会话记录与交接（跨 agent 连续性）

每次有实际改动的工作会话结束前完成交接：

1. **始终新增 `docs/worklog/` 交接简报**：文件名 `YYYY-MM-DD-主题.md`，内容为提炼后的要点（模板见 `docs/worklog/README.md`）。
2. **仅在状态发生变化时回写 `docs/DEVELOPMENT_STATUS.md`**：模块生命周期、阶段放行、可引用结果、主要局限或下一步优先级发生变化才更新。普通说明、重排或拼写修正不机械改状态文档，减少多人并行冲突。

只提交提炼后的简报，不要把 agent 对话原文、原始终端日志或超长运行输出提交进仓库；原始会话记录保存在本地即可。新会话的推荐启动顺序：读本文件 → 读 `DEVELOPMENT_STATUS.md` → 需要背景时回溯 `docs/worklog/`。
