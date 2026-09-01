# M1 独立复验报告（Codex，2026-09-01）

## 1. 结论

**平台线技术验收通过，仓库交付有条件通过。**

- M0-C 单元测试、安装器脏模型保护、M0-A 旁路比较、M0-B 故障注入、M0-C 配对试验和 M1 鲁棒性矩阵均在 MATLAB R2022b 中实际复跑通过。
- 未发现阻塞 M2 方案设计的代码或 Simulink 回归问题。
- 发现 1 项证据措辞不精确与 5 处阶段状态过期；它们不推翻 M1 的验收结论，但应由后续修改会话在封版前统一。

## 2. 被验收版本与范围

- 主库：`Zhoucmd6/26isip_Aerospace`
- 分支：`main`
- 提交：`028aad8b15406dce9b065cde5811b25c2d7ebbee`
- 提交标题：`Add M1 robustness acceptance: noise/latency/wind scenario matrix, zero slx changes`
- 环境：MATLAB/Simulink R2022b，Windows，GUI 独立会话
- 验收范围：`models/px4_x8` 平台线，重点为新增 M1 与 M0-A/B/C 回归。未重跑其他成员负责的三个算法模块全量验收。

## 3. 实际执行项

按 `AGENTS.md` 平台线清单逐项执行：

```matlab
cd models/px4_x8
test_m0c_esc_unit
test_m0c_installer_dirty_guard
run_air_m0a_baseline_compare
run_air_m0b_safety_injection
run_air_m0c_trials
run_air_m1_robustness
```

对有返回值的入口另外执行 `assert(result.pass)` 或等价断言，避免仅凭终端文本判定。

## 4. 复验结果

| 项目 | 结果 | 关键数据 |
|---|---|---|
| M0-C ESC 单元测试 | PASS | 4 类内核行为全通过，标定增益 `6.0e-03` |
| M0-C 安装器脏模型保护 | PASS | 未保存模型被正确拒绝，磁盘文件未变 |
| M0-A 旁路比较 | 4/4 PASS | `pwm_cmd [2501×8]`、`Ve [10001×3]`、`quat [10001×4]`、35 维总线最大差均为 0 |
| M0-B 故障注入 | 4/4 PASS | 位 1/4/7/6 全部触发，`frozen=0.000 s`，`fallback=0.500 s`，功率故障恢复成功 |
| M0-C 配对试验 | 9/9 PASS | T1/T2/T3 收敛 4/4/8 s；复现差 0；最大 `|delta_E|=0.00012930%` |
| M1 普通场景 | 23/23 PASS | R0/WN/DL/WD/CM 全部脚本判据通过 |
| M1 故障场景 | 4/4 PASS | 全部 `preQuiet=1`、`preActive=1`、`recoveryOK=1` |
| M1 配对 | 11/11 PASS | 最大 `|regret|=0.0001326297%`，远低于 3% 门槛 |
| M1 确定性 | PASS | `DL1_esc` 与 `DL2_esc` 的 `max|dv_ref|=0` |

本次本地归档（不入 Git，可由脚本重建）：

- `results/air_m0a_baseline_compare/20260901_165308/`
- `results/air_m0b_safety_injection/20260901_165331/`
- `results/air_m0c_trials/20260901_165418/`
- `results/air_m1_robustness/20260901_165545/`

## 5. 需要 ZCode 修改的问题

### F1：M1 证据对“时延与名义轨迹一致”的措辞过强（证据准确性，必修）

`docs/evidence/M1_ROBUSTNESS_20260901.md` 第 3 行和第 35 行声称 `DL1_esc` 与 `R0_esc` “参考轨迹逐样本一致”。对本次 MATLAB 归档的两个 `Mb(:,1)` 离线比较得到：

```text
max|v_ref(R0_esc) - v_ref(DL1_esc)| = 3.2757004952088664e-05 m/s
max|v_ref(DL1_esc) - v_ref(DL2_esc)| = 0
```

因此建议改为：

> 0.5 s 时延与名义轨迹最大差约 `3.28e-05 m/s`，对当前判据无实质影响；`DL1_esc` 与其确定性重复 `DL2_esc` 逐样本差为 0。

这项修改不推翻 M1 PASS，因为路线规定的确定性门槛是 `DL1_esc` 对 `DL2_esc`，对应实现在 `run_air_m1_robustness.m` 第 254–264 行。

### F2：M1 接口文档头部状态过期（必修）

`docs/interfaces/M1_ROBUSTNESS.md` 第 3 行仍为“实施中”，但同文档 §8 和主状态文档均已记录 M1 完成。应改为“已完成并通过验收（2026-09-01）”。

### F3：当前阶段在多份入口文档中仍指向 M1（必修）

当前唯一执行路线已指定下一步为 M2，但以下文件仍写“下一步 M1”：

- `README.md` 第 13 行和第 89 行；
- `AGENTS.md` 第 12 行；
- `docs/interfaces/M0A_OBSERVABILITY.md` 第 31 行；
- `docs/interfaces/M0B_SPEED_LOOP.md` 第 67 行。

统一修正为：M1 已完成并通过验收，下一步是 M2 上下桨转速比 ESC 及受约束 `X8 Control Allocator`。

### F4：历史库存文档可能被误当成当前状态（建议修）

`docs/interfaces/WORKSPACE_INVENTORY_20260831.md` 是带日期的历史快照，其中仍有“尚未接入任何能耗优化算法”。可保留原文，但建议在文档顶部增加明显的“历史快照，当前状态见 `DEVELOPMENT_STATUS.md`”提示，避免误引。

### F5：本地分支跟踪目标不利于判读（本地配置，非仓库缺陷）

本地 `main` 跟踪 `fork/main`，而不是 `origin/main`，因此 `git status` 显示 `ahead 2`；实际 `HEAD` 与 `origin/main` 均为 `028aad8`。如团队后续以 Zhoucmd6 主库为主，建议单独调整本地 upstream，不必为此修改仓库文件。

## 6. ZCode 修改后的最小复核清单

1. 用 `rg` 确认当前入口文档不再将 M1 写为“下一步”或“实施中”。
2. 确认 M1 证据只将 `DL1_esc`/`DL2_esc` 表述为逐样本差 0；R0/DL1 使用实测差值。
3. 若只修改 Markdown，无需重跑 27 场景；检查链接和数值后提交即可。
4. 若同时改动 `run_air_m1_robustness.m` 或 `.slx`，须重跑 `AGENTS.md` 平台线全清单。

## 7. 结论边界

本次验收仅证明：在当前未校准 `P_est` 与既定噪声/时延/扰动注入口径下，M0-C/M1 的接口、闭环、安全回退和复现机制符合当前路线门槛。它不支持“真实 X8 节能百分比”、“已解决偏航安全”、“RL 优于 ESC”或“已部署飞控”等结论。
