# M2 第二轮独立复验报告（Codex，2026-09-01）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线，延续现有责任记录）

主要撰写：待项目组确认

技术贡献：Codex（主库版本核对、MATLAB/Simulink 实际复跑、状态隔离诊断与验收逻辑审查）

审核：待项目组审核、待指导教师确认

AI 协助：Codex（复验执行与文档代拟）

## 1. 结论

**第二轮复验结论：部分通过。M2 修订后的数值协议通过，但自动化与会话隔离闭环尚未通过。**

- 在显式建立干净 M2 状态后，单元测试、旁路零差异、M0-B 安全注入和 M2 九场景完整链实际通过；门槛窗 S1/S2/S3 与修复报告逐位一致。
- 在一个由仓库自身旧 M2 试验留下状态的 MATLAB 会话中直接执行新增的 `run_m2_session_chain`，单元测试虽 PASS，紧随其后的旁路比较仍因 `pwm_cmd` 最大差 2 而 FAIL。此结果推翻了“任意普通会话中无需清理即可运行完整链”的强表述。
- `run_m2_session_chain` 在执行 `run_air_m2_trials` 后没有断言 `result.pass`；九场景若返回 FAIL，链仍可能打印 `M2 SESSION CHAIN END` 并以成功状态结束，存在自动化假绿风险。
- `unified_search` 的加固入口已在 MATLAB 中独立复跑：13/13 单元测试、8/8 门槛、`passed=1`，Z6 正常成功路径确认通过。

因此，M2 算法与 120 s 协议的数值结论可保留；Z1 重新打开，并新增完整链退出状态问题。在两项自动化缺陷关闭前，不应把 M2 表述为“任意会话下一键验收完全闭环”。M3 可继续接口/方案设计，但建议暂缓修改 `air_m2.slx` 的结构集成。

## 2. 版本、环境与范围

| 项目 | 值 |
|---|---|
| 主库提交 | `0625f74`（`Close M2 reacceptance findings: isolation, hard gates, pre-registered protocol`） |
| 本地与远端 | `main` 与 `origin/main` 一致，复验前跟踪工作树干净 |
| MATLAB | R2022b，Windows GUI 实际运行 |
| Simulink 对象 | `models/px4_x8/air_spare.slx` |
| 复验入口 | `run_m2_session_chain`、`run_unified_acceptance` |
| 源码/模型改动 | 无；本轮只生成 `.gitignore` 已排除的本地结果 |

## 3. 修复差异静态核对

相对上一轮报告提交 `5f6c026`，修复提交 `0625f74` 改动 12 个文件，覆盖原 Z1--Z7：

1. `test_m2_eta_esc_unit.m` 增加全局量快照/恢复，并把 U1 改为模型一致的 uint16 量化后检查；
2. `run_air_m2_trials.m` 将名义场景延长至 120 s，门槛窗改为 `[90,120] s`，保留 `[20,30] s` 连续性值，并把文档指标纳入 `result.pass`；
3. 新增 `run_m2_session_chain.m`，串联单元测试、旁路比较、安全注入与九场景；
4. `run_unified_acceptance.m` 增加 `summary.passed` 和失败 `error`；
5. 补充接口、证据、worklog、AGENTS 入口及 unified_search 署名占位。

Z2、Z3、Z4、Z6、Z7 的代码与文档改动方向符合上一轮清单。Z1 的实现只恢复入口状态，不会把入口处已有的陈旧 M2 状态规范化为恒等状态，详见 §4。

## 4. 未清理会话复现：完整链失败

在 MATLAB 当前目录 `models/px4_x8` 直接运行：

```matlab
run_m2_session_chain
```

执行结果：

1. `test_m2_eta_esc_unit` 输出 PASS；
2. `run_air_m0a_baseline_compare` 输出 FAIL；
3. `pwm_cmd` 最大差 `2`（容差 `1e-6`），`Ve` 与 `quat` 差为 0；
4. 完整链在 `assert(r1.pass, ...)` 处停止；
5. 失败归档：`results/air_m0a_baseline_compare/20260901_231718/`。

失败后读取全局状态：

```text
M2_ETA_PARAMS.mode    = 'esc'
M2_ETA_PARAMS.center0 = 1
M2_ETA_APPLIED        = 0.99914776890319873
```

该值来自先前 M2 试验末尾的 `R_esc`，不是恒等值 1。单元测试在入口快照该状态，并在成功退出时原样恢复，因此单元测试自身没有进一步污染状态，但也没有为后续旁路回归建立安全前置条件。

这不是外部任意污染：`run_air_m2_trials` 本身在开头设置全局量、每场景更新它们，结束时没有恢复入口状态；所以“运行一次 M2 试验 → 再运行完整链”是仓库内可自然出现的复现序列。

## 5. 干净状态隔离复验：数值链通过

为把 Z1 与其余修复隔离，显式清理一次后运行完整链：

```matlab
clear global M2_ETA_PARAMS M2_ETA_APPLIED
clear m2_eta_esc
run_m2_session_chain
```

### 5.1 单元、旁路与安全注入

| 检查 | 结果 | 归档 |
|---|---|---|
| M2 单元测试 | PASS，gain = 0.0032 | 命令窗口输出 |
| M0-A 旁路比较 | PASS，四项最大差均为 0 | `results/air_m0a_baseline_compare/20260901_231913/` |
| M0-B 安全注入 | 4/4 PASS | `results/air_m0b_safety_injection/20260901_231913/` |

### 5.2 M2 九场景

归档：`results/air_m2_trials/20260901_231938/`。

| 配对 | `[90,120] s` 门槛窗 ΔE% | `[20,30] s` 连续性 ΔE% | 收敛时间 | 结果 |
|---|---:|---:|---:|---|
| S1 vs E2 | -0.2598475888% | +0.3533635143% | 100 s | PASS |
| S2 vs E2 | -0.2921145534% | -0.2930216140% | 0 s | PASS |
| S3 vs E2 | -0.2261741040% | +0.5061903534% | 104 s | PASS |

所有 9 个场景的 `ok=1`；无 allocator 饱和、无 fallback、无 hard flag，eta 跟踪误差约 0--0.00133，S2 与 R 的 `eta_ref` 逐样本最大差 0。脚本输出 `M2 TRIALS PASS`。

本轮门槛窗数据与 `docs/evidence/M2_REACCEPT_FIX_20260901.md` 的 3 会话结果逐位一致，因此 120 s 修订协议的数值可复现性得到一次额外独立确认。连续性窗 S3 仍为 +0.50619%，只作接近阶段记录，不参与修订后的门槛判定。

## 6. `unified_search` 独立复跑

在 `modules/unified_search` 运行：

```matlab
us = run_unified_acceptance;
```

结果：

| 指标 | 结果 |
|---|---:|
| 单元测试 | 13/13 |
| 性能门槛 | 8/8 |
| `MOE(1h)` ea | 0.9927 |
| `MOE(1h)` multistart | 0.9924 |
| `summary.passed` | 1 |

正常成功路径确认成立；代码静态核对确认任一单元或门槛未全过时会抛出 `usearch:AcceptanceFailed`。本轮没有故意篡改门槛制造失败，因此未独立执行失败路径注入。

## 7. 第二轮问题清单

### R2-F1（高，重新打开 Z1）完整链依赖入口全局状态

`test_m2_eta_esc_unit` 的快照/恢复实现符合“测试不改变调用者状态”的一般语义，但 `run_m2_session_chain` 又声明“不需要人工状态清理”。两者组合缺少链级前置状态规范化：入口若已有 `M2_ETA_APPLIED != 1`，旁路回归仍会失败。

建议在完整链入口使用 `onCleanup` 保存调用者状态，随后自动设置：

```matlab
M2_ETA_PARAMS = struct('mode','fixed','center0',1.0);
M2_ETA_APPLIED = 1.0;
clear m2_eta_esc
```

链结束或异常时恢复调用者状态。`run_air_m2_trials` 也应自带同类清理，避免成为陈旧状态来源。修复后必须验证连续运行两次 `run_m2_session_chain` 均通过，不允许两次之间人工 `clear`。

### R2-F2（高）完整链没有硬断言九场景结果

`run_m2_session_chain.m` 对 `r1.pass` 和 `r2.pass` 有断言，但末尾只执行 `run_air_m2_trials`。该脚本失败时只设置 `result.pass=false` 并打印 FAIL，不主动抛错，所以链可能假绿。

修复要求：执行后增加 `assert(result.pass, ...)`，错误信息带 `result.archiveDir`；更理想的长期形式是把 `run_air_m2_trials` 改为返回 result 的函数入口。

### R2-F3（中）单元测试错误路径未清持久态

当前 `onCleanup` 回调只恢复两个 global；`clear m2_eta_esc` 位于成功路径。如果 U1--U4 中途 assert，global 会恢复，但适配器 persistent 可能保留失败前状态。应把 persistent 清理纳入无论成功/异常都会执行的统一 cleanup。

## 8. 原 Z1--Z7 关闭复核

| 原项 | 第二轮判定 | 依据 |
|---|---|---|
| Z1 测试隔离 | **未关闭，重新打开** | 未清理普通会话实际复现旁路 `pwm_cmd` 差 2 |
| Z2 门槛覆盖 | 通过 | 所有文档硬指标已进入单场景 `ok` 与总 `result.pass` |
| Z3 量化口径 | 通过 | U1 先执行模型一致 uint16 量化 |
| Z4 S3 裕量 | 数值通过 | 预注册 120 s / `[90,120] s`，门槛不变，本轮结果一致 |
| Z5 跨会话复验 | 通过但不覆盖陈旧入口 | 已报告 3 个新会话 3/3，本轮干净状态额外 1 次通过 |
| Z6 unified 硬失败 | 通过 | 实跑 13/13、8/8、`passed=1`；失败分支为 `error` |
| Z7 流程文档 | 通过 | AGENTS 入口、worklog、README 署名占位已补；真实负责人仍待确认 |

## 9. 下一轮关闭条件

1. `run_m2_session_chain` 在内部自动建立安全恒等状态并用 `onCleanup` 恢复，不要求用户手动清理；
2. 同一 MATLAB 会话连续执行完整链两次，2/2 全部通过；第二次必须直接承接第一次 `run_air_m2_trials` 留下的会话历史；
3. 在完整链末尾断言 `result.pass`，并通过可控的非破坏性测试证明 `result.pass=false` 时入口确实返回错误；
4. 单元测试异常路径同时恢复 global 并清除 `m2_eta_esc` persistent；
5. 修订 `M2_REACCEPT_FIX_20260901.md` 和开发状态中“问题全部关闭”“无需清理”的过强表述，不删除历史，使用新增勘误或后续报告链接修正。

## 10. 阶段边界

- M2 受约束 eta 分配器、ESC 接线和修订后的数值门槛结果继续有效；不需要回退 `.slx` 或修改 +0.5% 门槛。
- 当前缺陷属于验收编排和会话状态管理，仍可能影响旁路模型，因此不是纯文档问题。
- M3 可以继续接口、仲裁与场景设计；在 R2-F1/R2-F2 关闭前，不建议修改 `air_m2.slx` 开始 M3 结构集成。
- 所有能量百分比仍是未校准模型估算，不构成真实 X8 节能或飞行安全结论。
