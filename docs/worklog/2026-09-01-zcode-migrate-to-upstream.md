# 2026-09-01 平台线工作迁移至主库（ZCode 会话简报）

## 背景

仓库方将 fork（Yaaaaaaa233）内容快进合并至主库（Zhoucmd6/26isip_Aerospace）至 `1cd3b59`（M0-C 方案），并新增 `modules/speed_esc`、`modules/speed_rl_residual` 与四模块布局规则文档（`e471d60`、`59ddde9`、`f34af0f`）。按用户指示，平台线此后直接在主库工作。本次将 M0-C 实现的两个提交（原 `4c57fe8`、`f0e1e68`）变基重放为主库 `437d84c`、`43067de`，并完成本地工作目录迁移。

## 变基冲突与解决

仅两份状态文档冲突，双方内容全部保留：

- `docs/DEVELOPMENT_STATUS.md`：主库四模块总览表（ratio_esc / speed_esc / speed_rl_residual / models/px4_x8）+ 我们把 px4_x8 行更新为"M0-C 完成"；证据条目按时间序调整为 M0-B 在前、M0-C 在后；主库"下一步 6"（M0-C 后评估以 `speed_esc` 回归估计器替换解调内核）与我们"M0-C 完成、下一项 M1"的横幅共存。
- `docs/PROJECT_EXECUTION_ROADMAP.md`：保留主库 §5 的 RL 预研注记，采纳我们"§6 下一次实际工作"的完成态改写。

模型与脚本零冲突：`models/px4_x8`（`air_m0c.slx` SHA256 `f9be88df…` 与验收时一致，14 个共用脚本与本地冻结副本逐字节内容一致）、`docs/interfaces/M0C_SPEED_ESC.md`、`docs/evidence/M0C_TRIALS_20260901.md` 干净落地。

## 主库合并带来的工作细节变化

1. **提交纪律（AGENTS.md）**：提交前跑对应模块验收；平台线 = `run_air_m0a_baseline_compare` + `run_air_m0b_safety_injection`（结构变更时另跑 `run_air_m0c_trials`）；提交信息标工作线；每轮结束更新 `DEVELOPMENT_STATUS.md` 并留 worklog。
2. **`.slx` 单分支红线**：任一模型同一时间只允许一个分支修改，M1 动 `air_spare.slx` 前先确认无并行改动。
3. **换核评估列为显式后续项**：`speed_esc` 的窗口回归估计器（FIFO 延迟配对）是 M0-C 解调内核的"验收后替换候选"——M1 的时延/噪声鲁棒性（0.5 s 时延门槛）正是其设计目标，M1 方案将把"解调核 vs 回归核"平台内对比列为工作项；该评估不改变 M1 验收门槛。
4. **RL 红线不变**：`speed_rl_residual` 属算法线虚拟代理预研，平台 M4 前不接入；三套虚拟功率曲线互不可比，跨模块节能比较仍然禁止。
5. **仿真产物不入库**：主库 `.gitignore` 已忽略 `results/`；本地历史结果目录已拷入仓库工作树（不提交），后续脚本一律从仓库副本运行（脚本位置无关，结果落仓库根 `results/`）。
6. `integration/air_esc/`、`harness/` 为占位目录：M1 不动，M4 Harness 落 `harness/`。RL 模块声明的外部依赖 `energy_data_rl` 不在仓库，属算法线问题，不影响平台线。

## 本地迁移

- 远端：`origin` → 主库 Zhoucmd6/26isip_Aerospace（日常推送目标），原 fork 保留为 `fork` 远端（备份）；回退点 `backup/pre-migration`。
- `第二阶段/models`、`第二阶段/docs` 冻结不再修改（历史存档）；工作树以仓库副本为唯一开发位置。
- 迁移后从仓库副本复跑 compare + 注入回归确认绿基线（结果见本轮归档）。
