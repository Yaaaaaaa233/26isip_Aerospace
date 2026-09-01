# 项目新进展独立复验报告（Codex，2026-09-01）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线，延续现有责任记录）

主要撰写：待项目组确认

技术贡献：Codex（MATLAB/Simulink 独立复跑、Git 版本核对、验收逻辑审查与报告代拟）

审核：待项目组审核、待指导教师确认

AI 协助：Codex（实际复跑与文档整理）

## 1. 结论

**本次验收结论：部分通过，M2 暂不放行，M3 暂不启动。**

- M2 单元测试本身通过；清理 M2 全局状态后，旁路基线回归差为 0，M0-B 安全注入 4/4 通过。
- 重新运行 M2 九场景时，S3 能量差为 **+0.506190%**，超过预先声明的 **+0.5%** 门槛，脚本输出 `M2 TRIALS FAIL`。原证据中 S3 为 +0.492518%，说明该工况缺乏跨会话复现裕量。
- 主库新增 `modules/unified_search` 的已提交 CSV 与报告数值一致，但验收入口对失败只发出 `warning`，且署名、worklog 和 `AGENTS.md` 入口尚未补齐。本次未对该新模块做 MATLAB 独立复跑，因此只给出静态验收结论。

## 2. 版本与范围

| 项目 | 值 |
|---|---|
| 复验时本地 M2 版本 | `c354eaf` |
| 已获取主库新版本 | `490711c` |
| MATLAB | R2022b，Windows GUI |
| M2 对象 | `models/px4_x8/air_spare.slx` |
| 审查范围 | M2 单元测试、旁路回归、安全注入、九场景配对；`unified_search` 提交与验收逻辑 |
| 未改动 | MATLAB 源码、`.slx` 模型与已提交证据数据 |

## 3. 实际复跑结果

### 3.1 M2 单元测试

在 `models/px4_x8` 运行 `test_m2_eta_esc_unit`，结果为 `M2 UNIT TESTS PASS (gain = 0.0032)`。U1–U4 均通过，解析碗双起点最终中心为 1.0010 / 0.9997，invalid 窗保持与恢复通过。

### 3.2 测试隔离与旁路回归

在同一 MATLAB 会话中紧接单元测试运行 `run_air_m0a_baseline_compare`：FAIL，`pwm_cmd` 最大差 2，其余检查差为 0。清理后重跑：

```matlab
clear global M2_ETA_APPLIED M2_ETA_PARAMS
clear m2_eta_esc
r0b = run_air_m0a_baseline_compare
```

结果 PASS，四项最大差全为 0。因此 eta=1 恒等旁路仍成立，首次失败由单元测试残留的 M2 全局/持久状态触发。

- 失败归档：`results/air_m0a_baseline_compare/20260901_215908/`
- 清理后通过归档：`results/air_m0a_baseline_compare/20260901_220006/`

### 3.3 M0-B 安全注入

清理 M2 状态后运行 `run_air_m0b_safety_injection`：`pwm_edge` / `yaw_rate` / `nan_power` / `power_rec` 全部通过，即 4/4 PASS。归档：`results/air_m0b_safety_injection/20260901_220104/`。

### 3.4 M2 九场景

清理 M2 状态后运行 `run_air_m2_trials`，归档 `results/air_m2_trials/20260901_220344/`。

| 配对 | 本次 ΔE% | 门槛 | 结果 | 原证据 ΔE% |
|---|---:|---:|---|---:|
| S1 vs E2 | +0.353364% | ≤ +0.5% | PASS | +0.370101% |
| S2 vs E2 | -0.293022% | ≤ +0.5% | PASS | -0.285273% |
| S3 vs E2 | **+0.506190%** | ≤ +0.5% | **FAIL** | +0.492518% |

附加结果：S2 与 R 的 `eta_ref` 逐样本差为 0；fixed 功率面 E1/E3 对 E2 为 +1.585009% / +0.979360%；扰动配对 DS2 vs DE2 为 -0.17816%（报告项，不作门槛）。

## 4. 问题清单

### F1（阻断）M2 S3 缺少验收裕量

原证据仅比 +0.5% 门槛低 0.0075 个百分点，本次复跑比门槛高 0.0062 个百分点。在找到跨会话漂移原因并建立裕量前，不应放行 M2。不应在看到本次数据后直接放宽门槛；若修改判据，必须先给出物理/统计理由并重新预注册。

### F2（高）M2 单元测试不隔离全局状态

`test_m2_eta_esc_unit.m` 改写 `M2_ETA_PARAMS` / `M2_ETA_APPLIED` 和 `m2_eta_esc` 持久状态，退出时没有恢复，使后续基线验收依赖执行顺序。

### F3（中）量化单元测试与证据描述不匹配

`m2_eta_allocator` 返回未取整的 double 平方根结果，uint16 量化发生在 Simulink `M2 Pwm Uint16` 块。U1 直接用纯函数输出检查 `Σc`，未经过 1 us 量化，因此“U1 验证了量化后误差”的证据描述过强。

### F4（中）M2 总 PASS 未覆盖文档全部门槛

`run_air_m2_trials.m` 计算了 `etaTrk`、`yawMax`、`nFrozen`、PWM 边界与 `dmzMax`，但名义场景 `runOK` 只强制硬标志、fallback、eta 带内、gate engaged 和 allocator sat；扰动场景只检查 eta 带内。部分文档门槛退化时仍可能得到总 PASS。

### F5（中）`unified_search` 验收入口不硬失败

`run_unified_acceptance.m` 在性能门槛未全过时只调用 `warning`，没有 `assert`/`error`；单元测试通过数也没有进入最终硬失败条件。自动化可在验收未通过时仍正常返回。

### F6（流程）`unified_search` 缺必需署名和交接

根据 `docs/AUTHORSHIP.md` 和 `AGENTS.md`，当前还缺模块 README 贡献表、对应 worklog，以及 `AGENTS.md` 中的模块概要和验收命令。

## 5. `unified_search` 静态数据核对

| 算法 | n | 平均 MOE | 最小 | 最大 |
|---|---:|---:|---:|---:|
| ea_multistart | 3 | 0.99268710 | 0.99049467 | 0.99378389 |
| multistart | 3 | 0.99242180 | 0.99172958 | 0.99291255 |
| fixed | 3 | 1.00000000 | 1.00000000 | 1.00000000 |

因此“ea 平均 MOE 0.9927 > multistart 0.9924”与 CSV 一致。该核对只证明已提交数据与文档自洽，不等价于 MATLAB 独立复现。

## 6. ZCode 修复清单与关闭条件

1. **Z1：修复测试隔离。** 在 `test_m2_eta_esc_unit.m` 中用 `onCleanup` 保存/恢复全局变量，并清理 `m2_eta_esc` 持久状态；按 `AGENTS.md` 顺序连续运行时不再需要手动 `clear global`。
2. **Z2：补齐 M2 硬门槛。** 将 eta 跟踪、yaw 上界、frozen/fallback、PWM 边界/持续饱和、扰动安全条件纳入 `result.pass`。
3. **Z3：修正量化测试。** U1 对分配器输出执行与 Simulink 一致的 uint16 量化后再检查 `Σc`，或抽出共享量化函数；同步修正注释与证据。
4. **Z4：处理 S3 裕量。** 先定位跨 MATLAB 会话差异，再调整参数或数值执行一致性；不得为本次数据事后直接放宽门槛。
5. **Z5：增加跨会话复现。** 在至少 3 个新 MATLAB 会话中完整运行 M2 入口，要求 3/3 总 PASS，并报告 S1–S3 跨次最差值。
6. **Z6：加固 `unified_search`。** 任一单元测试或性能门槛失败时应 `error` 或返回明确 `passed=false`，并使自动化获得非成功结果。
7. **Z7：补流程文档。** 补充 `modules/unified_search/README.md` 贡献表、本次 worklog，并在 `AGENTS.md` 加入模块概要与验收命令。

## 7. 阶段边界

- M0-B 安全链与清理状态后的 eta=1 旁路回归可继续引用。
- M2 应表述为“已实现受约束 eta 分配器与转速比 ESC，原始验收曾通过，但独立复验发现 S3 轻微超门槛，当前待修复”。
- Z1–Z5 关闭前，不开始修改 `air_m2.slx` 的 M3 结构工作。
- `unified_search` 结论仅限代理对象与已提交数据，不外推真实 X8 节能。
