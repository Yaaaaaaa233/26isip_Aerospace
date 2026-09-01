# 2026-09-01 速度ESC与残差RL模块并入主仓库

## 本次做了什么

- 将队友 fork（Yaaaaaaa233/26isip_Aerospace，领先 11 个提交）fast-forward 合并进 `main`：PX4 X8 平台（阶段0/M0-A/M0-B 及复核修复）、AGENTS.md、worklog 约定、ROADMAP、M0-C 方案文档全部进入本仓库。
- 新增 `modules/speed_esc/`：平飞速度在线 ESC（η=1，窗口回归梯度为主、同频解调为对照），来自本地工程 `speed_esc_matlab`；含 26 函数包、程序化 Simulink 模型、14 组 Python 对齐 fixtures 与单元测试；`results/` 不入库（遵守提交约定第 4 条）。
- 新增 `modules/speed_rl_residual/`：速度基线之上的 TD3 残差修正（不规则风/电池/轨迹代理），来自本地工程 `speed_rl_residual`；同样不含 `results/`。
- 精选证据入库 `docs/evidence/speed_esc/`（验收报告、74 场景汇总、各场景总览图与指标、V3 过程动画、Simulink 结构图）与 `docs/evidence/speed_rl_residual/`（验收报告、三份策略评估 CSV、接口演示图、三个 TD3 训练检查点 `.mat`）。
- 规则文档适配：AGENTS.md 概览扩为四条线并补验收命令；COLLABORATION.md 补两个新模块的接口契约与认领行（提交约定原文未动）；ROADMAP §5"RL 仅在 M4 后"与 §6 增补算法线预研定位说明（M0-C 采用 ratioesc 内核的决定未变）；DEVELOPMENT_STATUS.md 总览/证据/局限/优先级/结果边界同步扩充。

## 关键决策与理由

- **结果入库策略**：维持"仿真输出不进版本库、精选证据入 docs/evidence"的原有约定，不改为全量上传。理由：results 可由固定种子验收脚本一键重建；git 历史永久保留会随实验迭代不可逆膨胀；该约定由队友写入 COLLABORATION.md 与 .gitignore，单方面修改影响协作。TD3 候选 `.mat` 作为训练产物（模型检查点）例外保留在 evidence 中。
- **M0-C 内核不动**：`modules/speed_esc` 并入后，M0-C 仍按 `M0C_SPEED_ESC.md` 采用 `modules/ratio_esc` 内核做速度语义映射；speed_esc 的回归估计器定位为后续内核替换候选（已写入 DEVELOPMENT_STATUS 下一步第 6 条），避免未验收就更换执行基线。
- **红线第 1 条外延**：AGENTS.md 因果边界中"实际转速比"扩写为"实际被控量（转速比或平飞速度）"，属忠实外延而非放宽；完整曲线/最优点/解析梯度禁入的红线原文保留。
- **speed_rl_residual 定位**：明确为优化算法线在虚拟代理上的预研，不受也不触碰"RL 仅在 M4 后"的平台接入红线；不得据此宣称飞行相关结论。

## 遗留问题 / 风险

- 两个新模块的验收数据为并入前在本地工程运行所得（2026-08-31/09-01，MATLAB R2022b）；本仓库工作区内未重跑（本机当前会话无 MATLAB 执行记录），换机器后应先跑 `run_speed_acceptance` 与 `run_checks(false)` 确认基线为绿。
- `modules/speed_esc/README.md` 引用的外部工程 `energy_data_rl`（`make_context_speed_env` 的可选依赖）不在本仓库，需自行放置同级目录。
- 三套代理功率模型（ratio_esc / speed_esc / speed_rl_residual）口径不同，已写入已知局限，防止跨模块横比节能率。

## 下一步

- 平台线：按 `docs/interfaces/M0C_SPEED_ESC.md` 实施 M0-C（五组配对试验 + 回归 + 快照 `air_m0c.slx`）。
- 算法线：`speed_rl_residual` 按课程继续训练不规则风策略；`speed_esc` 等待 M0-C 验收后评估内核替换。

## 验收状态

- run_acceptance（ratio_esc）：未运行（本次未改动该模块代码，沿用其既有验收结论）。
- run_speed_acceptance / run_checks：未在本仓库工作区重跑，结果以并入前的 evidence 归档为准（见上"遗留问题"第 1 条）。
