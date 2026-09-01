# 2026-09-01 M1 扰动、噪声与时延鲁棒性验收通过

## 本次做了什么

- 会话开工核查：主库 `origin/main` 已前移至 `932c55d`（治理"加了又撤"4 个提交 + 另一会话的 M0-C 验收加固）。本地 `main` 快进对齐，恢复 origin 双 push URL（Zhoucmd6 主库 + Yaaaaaaa233 fork），fork `main` 同步快进。
- 新增执行基线 `docs/interfaces/M1_ROBUSTNESS.md`（场景矩阵、注入口径、判据；先文档后实施）。
- 新增 `models/px4_x8/run_air_m1_robustness.m`：27 场景固定种子矩阵——名义 R0、5 种子 2% 功率噪声、0.5 s 时延（含确定性重复）、基线正弦扰动 WD、3 种子噪声+时延+风组合 CM、名义背景 2% 噪声下 M0-B 四类故障注入 F1–F4。全部注入为内存接线、逐场景磁盘重载，**零 `.slx` 变更**。
- 新增 `models/px4_x8/diag_m1_probe.m`：P_est 拓扑探针。
- 验收通过后回填：基线 §8、`docs/evidence/M1_ROBUSTNESS_20260901.md` + 两个机器可读 CSV、`DEVELOPMENT_STATUS`、路线 §4/§5-M1/§6、模型 README、AGENTS.md 平台线清单（加入 `run_air_m1_robustness`）。

## 关键决策与理由

- **注入点**：`M0A Power Measurement` 出 1 的两个 ZOH 消费者（`M0C P ZOH` = ESC、`M0A P Est ZOH 1ms` = 功率监视器上游）被重接到同一退化链，二者看到一致退化测量；`m0a_P_est_W` 等日志分支保持在真实信号上——成本/regret 用真实功率，测量退化只体现在安全链与 ESC 决策。首轮曾按错误假设直连监视器入 4，被运行时断言 `air:M1:UnexpectedSource` 拦截（首轮归档 `20260901_155726` 不通过），探针核实拓扑后修正。
- **F 组名义背景**：基线正弦下位 5 在 pre 窗本有活动，与加严判据"pre 窗 8 位全静默"冲突；F 组改为 roll 置 0，M0-B 判据 c1–c6 逐条不变。
- **时延链**：10×0.05 s Unit Delay，初值 251 W（避免虚假功率跌落误触位 6/7）；噪声 4 ms 阶梯高斯（σ=0.02×251 W），fixed/ESC 配对同种子同噪声实现。
- **诚实结论**：regret 最大 |0.000133%| ≪ 3% 门槛，是平坦功率面的预期结果，只证明"测量退化未使机制变坏"，不构成节能证据；噪声/组合把 esc 收敛从 4 s 放慢到 8–20 s，如实记录、未调参掩盖。

## 遗留问题 / 风险

- `P_est` 仍未校准：M1 的全部结论限于当前代理对象与名义注入口径，不外推真实传感器/风场/功耗。
- 扰动场景 clean 窗占比 0.39–0.46（位 5 随正弦间歇置位），与 M0-B 口径一致，未改善也不构成回退。
- `M0B Flags Override/Att Demux` 空支路告警仍未清理（非阻塞，避免为诊断噪声引入模型变更）。
- 回归脚手架细节：`run_air_m0c_trials.m` 是脚本（非函数），`run()` 进共享工作区会污染循环变量 `k`；单条 `-batch` 串多个脚本时末尾 `fprintf` 标签可能串行，不影响脚本本体判定，但多脚本串联时建议各自独立调用。

## 下一步

- M2：上下桨转速比 ESC（`eta` 分配器）——先落方案文档（八电机配对与 `eta` 定义、受约束 `X8 Control Allocator`、`ratio_esc` 代价换接平台 `P_est`、eta 0.8/1.0/1.2 配对基线）。M2 起涉及 `.slx` 结构变更，单分支修改与旁路回归红线照旧。
- 待用户确认后的独立复验（沿 M0-B/M0-C 惯例）。

## 验收状态

- M1 矩阵：27/27 通过（归档 `results/air_m1_robustness/20260901_160420/`）。
- 平台线回归 5 脚本：unit / dirty-guard / baseline-compare（差 0）/ safety-injection 4/4 / m0c-trials 全部 PASS。
- 本轮零 `.slx` 变更；`air_m0c.slx` 仍为当前冻结快照。
