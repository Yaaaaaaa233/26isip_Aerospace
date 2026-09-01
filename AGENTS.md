# AGENTS.md

本文件面向在本仓库工作的 AI 编码代理（Codex、ZCode、Claude Code 等），同样适用于人类协作者。开始任何改动前，先按下面的入口读取对应文档，不要凭猜测修改接口。

## 项目概要

共轴八旋翼（X8）在线能耗优化研究仓库，当前有四个并行模块/工作线：

- `modules/ratio_esc/` — 上下桨转速比在线极值寻优（ESC）可运行模块（MATLAB/Simulink + RL 环境接口），对象是恒推力假设下的归一化代理功率模型。
- `modules/speed_esc/` — 平飞速度在线 ESC 模块（配比固定 η=1），窗口回归梯度估计为主、同频解调为对照；虚拟功率曲线代理对象上完成 74 场景性能验收，并与原 Python 方案逐样本对齐。
- `modules/speed_rl_residual/` — 在速度基线（固定值/ESC/解析式）之上叠加 TD3 残差修正 `v_ref = guard(v_base + Δv)` 的算法线预研模块；对象为不规则风场下的虚拟代理，含电池与圆周/直线轨迹工况。
- `models/px4_x8/` — PX4 X8 Simulink 验证平台，阶段 0、M0-A、M0-B、M0-C 已完成；M0-C 已把 `ratio_esc` 内核作速度语义映射后接入，当前下一项为 M1 扰动、噪声与时延鲁棒性。

## 必读文档

| 何时读 | 文档 |
|---|---|
| 每次开工前 | `docs/DEVELOPMENT_STATUS.md`（当前状态、已知局限、下一步优先级） |
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
```

换新机器后的第一件事：先跑通对应模块的验收脚本确认基线为绿，再开始任何修改。

飞控平台线改动至少运行：

```matlab
cd models/px4_x8
test_m0c_esc_unit
test_m0c_installer_dirty_guard
run_air_m0c_trials
run_air_m1_robustness
run_air_m0a_baseline_compare
run_air_m0b_safety_injection
```

## 硬性红线

1. **因果边界**：控制器与 RL 观测只能接收测量功率、实际被控量（转速比或平飞速度）、采样时间和有效性标志；完整功率曲线、真实最优点、解析梯度不得进入控制器或 RL 观测。
2. **对象升级位置**：物理对象升级只替换 `power_map`、`plant_advance`、`measure`（约束量在对象侧输出 `constraint_flags`），不得修改 ESC 的因果接口签名。
3. **结论边界**：仓库内验收结果只支持 `docs/DEVELOPMENT_STATUS.md` "当前可引用的结果边界"所列表述；不得在任何文档或对外输出中宣称真实节能百分比、偏航安全、RL 优于 ESC 或已部署飞控。
4. **版本控制**：不提交 `slprj/`、`*.slxc`、临时动画帧、重复日志、本地自动保存文件（见 `.gitignore`）。

## 提交约定

- 提交前运行 `run_acceptance`；涉及面板或导出的修改，再运行 `qa_ui`。
- `.slx` 为二进制文件、不可合并：同一模型文件同一时间只在一条分支上修改；两条工作线避免并行改动同一个模型。
- 文档用中文；提交信息简明说明改动属于哪条工作线（沿用现有英文提交风格亦可）。

## 会话记录与交接（跨 agent 连续性）

每次工作会话结束前完成两件事：

1. **回写 `docs/DEVELOPMENT_STATUS.md`**：更新对应工作线的状态、已完成项、已知局限与下一步优先级，使其始终反映仓库真实现状。
2. **在 `docs/worklog/` 新增一篇交接简报**：文件名 `YYYY-MM-DD-主题.md`，内容为提炼后的要点（模板见 `docs/worklog/README.md`）。

只提交提炼后的简报，不要把 agent 对话原文、原始终端日志或超长运行输出提交进仓库；原始会话记录保存在本地即可。新会话的推荐启动顺序：读本文件 → 读 `DEVELOPMENT_STATUS.md` → 需要背景时回溯 `docs/worklog/`。
