# M1 扰动、噪声与时延鲁棒性 工作步骤与验收基线

状态：**实施中（2026-09-01 立项）**。来源：`docs/PROJECT_EXECUTION_ROADMAP.md` §5 M1 与 §6"下一次实际工作"。本文档是 M1 的执行基线：先落文档，再实施，实施完成后按 §7 判据验收并回填 §8。

红线（沿袭并加严）：`air.slx` 只读；**本阶段零 `.slx` 变更**——全部注入在内存接线、每场景从磁盘重载模型（M0-B 注入脚本模式）；不接入 `eta` 分配器，不做 RL；算法不得接触模型内部最优值、解析梯度或 PWM 控制权；P_est 未校准，一切能耗结论只作"模型估算"口径。

## 1. 目的与预期管理

检验 M0-C 闭环不是理想条件下的偶然结果：在 ESC 在线运行下注入测量退化与扰动，验证收敛保持、安全链零误触发、regret 门槛成立，并让回退/恢复行为在退化测量下再次过一遍。

**诚实预期（写明，防止为数字调参）**：M0-C 已确认工作点附近 P–v 面平坦（共同网格配对 |ΔE|≤0.00013%）。因此 M1 的 regret 门槛（≤3%）在当前未校准模型上**近平凡**——平坦面上任何合法策略的配对差都应接近 0。M1 的验收对象是**鲁棒性行为本身**（噪声/时延下 ESC 不发散、安全链不误触发、故障时序不退化），**不是**任何功率改善。regret 数字只证明"没有变坏"，不证明"有优化价值"。

## 2. 注入设计

### 2.1 注入点与因果边界

`M0A Power Measurement` 输出 1（`P_est` 真实值）同时喂两个消费者：`M0C P ZOH` 入 1（ESC 的 `P_e`）与 `M0A Constraint Flags` 入 4（功率安全监视）。M1 的主注入操作是**逐目的地重接**这两条线到退化链输出（M0-B 注入模式，不动输出端口的其他分支）：

```
M0A Power Measurement 出1 ──┬── (原线保持) 日志 m0a_P_est_W / E_est 等其余分支
                            ├── [时延链 z⁻¹⁰ (0.05 s×10), 初值 251] ──┐
                            └──────────────────────────────────────── + Sum ──┬── M0C P ZOH 入1
                            Random Number (σ, Seed) ──────────────────────────┘   └── M0A Constraint Flags 入4
```

- **两个消费者看到一致的退化测量**（真实传感器退化语义）；ESC 与监视器不因注入而信息不对称。
- **能量/成本统计保持真实功率口径**：`m0a_P_est_W` 日志留在注入点上游，regret、`Eclean` 等指标不被测量噪声污染；测量退化只体现在安全链行为与 ESC 决策中。
- 脚本运行时断言两条被重接线的原源都是 `M0A Power Measurement` 出 1（防拓扑漂移）。
- 时延链初值 251 W（额定巡航）：前 0.5 s 输出恒 251，避免从 0 开始的虚假功率跌落误触位 6/7。
- 噪声：Random Number，Mean 0、Variance `(0.02×251)² ≈ 25.2`（σ≈5.02 W）、SampleTime 0.004（与 P_est 4 ms 网格同率）、Seed 为场景种子（**每对的 fixed 臂与 esc 臂用同一种子 → 同一噪声实现，公平配对**）。
- 0.05 s 之外的采样细节（噪声与 P_est 网格相位差引起的拍频）不影响 0.05 s 级消费者，不作处理。

### 2.2 故障回归的噪声背景（F 组）

F 组在 2% 噪声背景下重跑 M0-B 四类注入，判据保持 M0-B 原语义：

- F1/F2/F3（pwm_edge / yaw_rate / nan_power）：主 P 通路插噪声链（同 §2.1），故障注入照旧重接 `M0A Constraint Flags` 入 1 / 入 2——两个操作作用于不同输入端口，可叠加；
- F4（power_rec）：故障源（251 + 1349 脉冲 Sum）后再串同一噪声 Sum，重接入 4；ESC 侧 P 保持原线（fallback 后 selector 主导参考，ESC 输入退化与否不影响安全判据，如实记录该口径）；
- F 组用 `mode='fixed', center0=9`（与 M0-B 注入回归语义一致，排除 ESC 在线搜索干扰）。

### 2.3 风扰动口径

复用 M0-C DT2 口径：`Attitude Control/InputConditioning/Sine Wave` 保持基线幅值（即 M0-B 验收过的原正弦扰动场景）。名义场景将幅值置 0（仅内存，不保存）。

## 3. 场景矩阵

公共设置同 M0-C：`speed_loop_enable=1`、`optimizer_enable=1`、`v_ref_manual=5`、StopTime 30 s（F4 为 13 s）、每场景磁盘重载模型。全部场景 center0 = 9 m/s。

| 组 | 场景 | 注入 | 种子 | 模式（臂） | 判据集 |
|---|---|---|---|---|---|
| R0 | 名义复现 | 无 | — | fixed + esc | A + B + regret |
| WN1–WN5 | 2% 功率噪声 | §2.1 噪声 | 11–15 | fixed + esc ×5 | A + B + regret |
| DL1 | 0.5 s 时延 | §2.1 时延链 | — | fixed + esc | A + B + regret |
| DL2 | DL1 重复 | 同上 | — | esc | 确定性：与 DL1-esc 逐样本 max\|dv_ref\|<1e-9 |
| WD1–WD2 | 风扰动（基线正弦） | 无 | — | fixed + esc | C（如实报告，不 gate）+ regret |
| CM1–CM3 | 噪声+时延+风 | 全部叠加 | 21–23 | fixed + esc ×3 | C + regret |
| F1–F4 | 故障回归 | 2% 噪声背景 + M0-B 注入 | 31–34 | fixed | D |

共 30 次仿真。种子分配固定写入脚本，不得随结果调整。

判据集：
- **A（收敛与带宽，esc 臂）**：收敛时间存在（周期均值窗 <0.1 m/s 口径，同 M0-C）；t≥6 s 后 `v_ref ∈ [5.95, 12.05]`；
- **B（安全零误触发，R0/WN/DL 全程）**：8 位约束标志全程静默、零 frozen、零 fallback——2%≈5 W 噪声与 0.5 s 时延**不得**触发任何保护位（这是 M1 的核心新证据）；
- **C（扰动场景，WD/CM）**：`v_ref` 全程在带内；安全动作（frozen/fallback）如实报告触发次数与恢复；末段（t≥25 s）参考回到 |v_ref−9|≤0.51（若未恢复，如实记录失败条件）；
- **D（故障回归，F1–F4）**：M0-B 全部判据照搬（pre active、位触发 ≤0.05 s、frozen ≤0.10 s、fallback ≤1.0 s、fallback 参考界、power_rec 严格恢复）；加严——pre 窗（[5,6) s）**8 位全部零**（噪声背景不产生任何误触发）。

## 4. 统计与 regret 口径

- 每对（fixed 臂, esc 臂）同种子同注入实现；`regret% = 100×(E_esc − E_fixed)/E_fixed`，E 为**真实功率日志**在两次运行**相同连续时间网格**、公共 `[20,30] s` 窗上的 `trapz` 积分（932c55d 加固口径：不用各自 active 掩码；网格不一致即报 `air:M1:PairTimeGridMismatch`）；
- 每臂另按 M0-C 口径报告：clean（active 且位 5 静默）窗跟踪误差、P 均值、`Eclean`、收敛时间、trips、位 5 占比、PWM [min max]；
- 回退行为统计：WD/CM/F 组的 frozen/fallback 次数、fallback 持续时长、恢复后参考回到 9±0.51 的时刻——"无优化 / M0 优化 / 回退"三方行为在同一矩阵下可引用。

## 5. 实现（`models/px4_x8/run_air_m1_robustness.m`）

单脚本场景矩阵驱动：设 `global M0C_ESC_PARAMS` → 磁盘重载模型 → 内存注入（§2）→ `sim` → 逐臂统计（复用 M0-C `evalRun` 判据逻辑）→ 归档 `results/air_m1_robustness/<时间戳>/`（每 run `.mat` + `summary.csv` + `pairs_regret.csv`）。无 `diag_*` 前置；调试期临时脚本不入库。

## 6. 结构变更回归（红线，M1 收尾必跑）

本阶段零 `.slx` 变更，但仍须全绿（AGENTS.md 平台线清单）：

1. `test_m0c_esc_unit`；2. `test_m0c_installer_dirty_guard`；3. `run_air_m0c_trials`；4. `run_air_m0a_baseline_compare`；5. `run_air_m0b_safety_injection`。

路线 §6 非阻塞项（`M0B Flags Override/Att Demux` 空支路告警清理）**本次不做**，仅记录——避免为诊断噪声引入模型快照变更。

## 7. 验收判据（对应路线图 M1 门槛：2% 功率噪声、0.5 s 时延、regret ≤3%）

1. §3 判据集 A+B 在 R0/WN/DL 全部臂成立（噪声/时延下收敛保持、安全零误触发）；
2. 全部 fixed/esc 对的 `regret% ≤ 3`（含负值如实报告；平坦面预期 |regret|≈0）；
3. DL2 与 DL1-esc 逐样本 max|dv_ref| < 1e-9（确定性重复）；
4. C 组（WD/CM）不 gate 通过性，但触发/恢复行为须完整报告；若扰动下收敛或恢复失败，按路线允许"记录失败条件与修订理由"处理，不得以放宽安全约束换取指标；
5. D 组 4/4 通过（M0-B 判据 + pre 窗零误触发加严）；
6. §6 回归 5 脚本全绿；
7. 结论边界：所有能耗表述只作"模型估算"；regret 门槛满足不构成任何真实节能证据（§1）。

## 8. 验收结果（待验收后回填）

## 9. 交付物清单

- 文档：本文档、`docs/evidence/M1_ROBUSTNESS_<日期>.md`（含机器可读 summary/regret CSV 路径）、worklog `YYYY-MM-DD-zcode-m1-robustness.md`、`DEVELOPMENT_STATUS`/roadmap 状态回填；
- 代码：`models/px4_x8/run_air_m1_robustness.m`；
- 模型：**无**（零 `.slx` 变更，`air_m0c.slx` 仍为当前稳定快照）；
- 结果：`results/air_m1_robustness/<时间戳>/`（不入库）。
