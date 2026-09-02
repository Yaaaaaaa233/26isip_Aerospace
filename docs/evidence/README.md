# 项目证据导航

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：周航正
主要撰写：Codex
技术贡献：项目组各模块负责人（实验、复验和结果材料）
审核：待项目组审核
AI协助：Codex（证据分类与引用边界整理，2026-09-02）

本目录只保存能够支撑项目结论的报告、机器可读结果和必要图表。先从 [`../DEVELOPMENT_STATUS.md`](../DEVELOPMENT_STATUS.md) 确认“可以说什么”，再到这里找证据；工作日志和演示截图不能单独代替验收证据。

## 证据等级

| 等级 | 含义 | 可以支持的结论 |
|---|---|---|
| `proxy` | 人工或文献趋势构造的代理对象 | 算法逻辑、接口、收敛与相对比较 |
| `sim_calibrated` | 参数有来源并经过校准的物理仿真 | 指定模型和参数范围内的仿真结论 |
| `sitl` | 软件在环闭环结果 | 飞控软件链和接口行为 |
| `replay` | 真实日志回放 | 对已有数据的离线适配与评价 |
| `measured` | 台架或飞行实测 | 明确设备、工况和误差范围内的实测结论 |

当前项目的算法节能结果主要属于 `proxy`；PX4-X8功率为 `estimated`。实机数据尚缺失，不能把代理结果写成真实八旋翼节能率。

## 算法与场景证据

- [`speed_esc/`](speed_esc/)：平飞速度ESC。
- [`speed_rl_residual/`](speed_rl_residual/) 与 [`speed_rl_pytorch/`](speed_rl_pytorch/)：残差RL环境、对拍、候选训练和负结果。
- [`speed_shift_search/`](speed_shift_search/)、[`speed_rugged_search/`](speed_rugged_search/) 与 [`unified_search/`](unified_search/)：平移、多峰和统一搜索。
- [`wind_circle_search/`](wind_circle_search/)、[`sin_wind_search/`](sin_wind_search/)、[`ortho_wind_search/`](ortho_wind_search/) 与 [`wind_field_sched/`](wind_field_sched/)：圆周、正弦、正交和空速风场调度。
- [`adaptive_search/`](adaptive_search/)：自适应算法比较。
- [`mop_moe/`](mop_moe/)：指标和效能评价。

## PX4-X8平台证据

- 基线与M0-A：`air_baseline_*`、`air_interface_*`、`air_m0a_*`。
- M0-B与M0-C：[`M0B_RERUN_20260901.md`](M0B_RERUN_20260901.md)、[`M0B_REACCEPT_CODEX_20260901.md`](M0B_REACCEPT_CODEX_20260901.md)、[`M0C_TRIALS_20260901.md`](M0C_TRIALS_20260901.md)。
- M1：[`M1_ROBUSTNESS_20260901.md`](M1_ROBUSTNESS_20260901.md) 与 [`M1_REACCEPT_CODEX_20260901.md`](M1_REACCEPT_CODEX_20260901.md)。
- M2：从 [`M2_ETA_20260901.md`](M2_ETA_20260901.md) 到各轮 `M2_REACCEPT_*`；历史第六轮修复批次在 `2d36288` 留有 42/42 证据，但第七轮当前提交独立复跑记为 11/42：c5 两条最小链输出一致，却未生成阶段 CSV/done 标记，验收自动化仍为 PARTIAL。当前应优先引用 [`M2_REACCEPT_ROUND7_CODEX_20260902.md`](M2_REACCEPT_ROUND7_CODEX_20260902.md)，不能把历史批次直接当作当前提交的完整复验。

## 新证据最少包含

1. 负责人、贡献者、审核状态和AI协助。
2. 对象/模型版本、代码提交、配置、随机种子和评价窗口。
3. 指标单位、门槛、实际数值、通过或未通过。
4. `proxy/sim_calibrated/sitl/replay/measured` 证据等级。
5. 已知局限和不支持的外推结论。
6. 能复跑的入口以及必要的CSV、MAT或日志；大体积原始输出不重复提交。
