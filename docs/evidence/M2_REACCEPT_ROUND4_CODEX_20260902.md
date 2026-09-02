# M2 第四轮独立验收报告（Codex，2026-09-02）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线，延续现有责任记录）

主要撰写：待项目组确认

技术贡献：Codex（主库版本核对、MATLAB/Simulink 实际复跑、真实失败注入、persistent 直接探测、验收规则审计与判定）

审核：待项目组审核、待指导教师确认

AI 协助：Codex（第四轮独立验收执行与文档代拟）

## 1. 结论

**第四轮独立验收结论：部分通过。第三轮发现的 M2 三个核心入口缺陷已经关闭；M2 数值协议、模型快照与正常/异常入口行为通过。但新增的总验收器 `verify_m2_round4_closure` 自身违反全局量恢复契约，且其 10 行矩阵不能等同于规则要求的完整笛卡尔覆盖。**

- `test_m2_eta_esc_unit`、`run_air_m2_trials`、`run_m2_session_chain` 已函数化；真实注入 `unit/compare/injection/trials` 失败后，受测入口均恢复调用者状态。
- 独立动态探针证明：单元测试受控失败后，`m2_eta_esc` 第一次输出与显式 `clear m2_eta_esc` 后的 fresh 输出最大差为 0；第三轮 R3-F1/R3-F2 可以关闭。
- 仓库总验证器实际跑完并打印 10/10 PASS；同会话两次完整链均通过，`pairs.csv` SHA-256 完全相同。
- 但是，从非空调用者状态进入总验证器后，验证器返回时将 `M2_ETA_PARAMS`、`M2_ETA_APPLIED` 都清空，而不是恢复入口值。这违反 `docs/ACCEPTANCE_AUTOMATION_RULES.md` §3.1，并可能改变同会话后续测试的前置状态。
- 验证器对 persistent fresh 的原实现只从“全局量恢复”间接推断 `clear` 已执行，没有直接比较运行行为；本轮独立探针补足了事实证据，但仓库自动验收器本身仍未实现规则 §4.1 的直接检测。
- 当前 10 行矩阵覆盖了各错误出口和两个成功序列，但没有执行入口状态 `{干净 / 旧残留 / 上次错误后}` 与所有退出路径的完整组合，不能称为“全入口状态 × 退出路径矩阵”。

因此，M2 核心实现及其既有数值结论继续保持 PASS；“第四轮自动化完全闭环、验收基础设施规则全部满足”的结论修订为 PARTIAL。M3 的方案与实现可以继续，但在把该验证器用作后续里程碑放行门之前，应先修复其调用者状态恢复和覆盖口径。

## 2. 版本、环境与范围

| 项目 | 值 |
|---|---|
| 主库提交 | `2471917`（`Add environment wind-field research modules (tasks 3-5)...`） |
| M2 修复提交 | `239c19b`（`Close round-3 M2 findings; codify acceptance-automation rules`） |
| 本地与远端 | 验收开始时 `main` 与 `origin/main` 一致；受跟踪工作树干净 |
| MATLAB | R2022b，Windows GUI 实际运行 |
| Simulink 对象 | `models/px4_x8/air_spare.slx`；本轮未修改任何 `.slx` |
| 核心入口 | `verify_m2_round4_closure`、`test_m2_eta_esc_unit`、`run_m2_session_chain`、`run_air_m2_trials` |
| 证据归档 | `results/round4_closure/20260902_104606/` 及两次九场景归档 `20260902_104000`、`20260902_104321`（均由 `.gitignore` 排除） |
| 源码/模型改动 | 无；本轮仅新增验收报告、工作日志并同步当前状态文档 |

本轮只验收叶安负责的 `models/px4_x8` M2 平台线。主库最新提交还并入了任务 3--5 风场算法模块；这些模块不属于本轮验收范围，其已有结果仅作为项目进度背景读取，不在本报告中重新判定。

## 3. 第三轮六项关闭条件复验

| 条件 | 第四轮独立结果 | 判定 |
|---|---|---|
| 1. 单元测试错误后恢复 global 且 persistent fresh | 捕获 `air:M2Test:InjectedFailure`；global 精确恢复；直接比较错误后首次输出与 fresh 输出，`maxDiffFresh=0` | **通过** |
| 2. 链 compare/injection/trials 三类错误均恢复入口状态 | 仓库验证器逐类真实注入，三类错误均被捕获并逐域检查恢复 | **通过** |
| 3. 九场景入口独立成功/失败均恢复入口状态 | 受控失败和 120 s 完整成功均执行并通过验证器检查 | **通过** |
| 4. trials 失败硬退出并携带归档路径 | 捕获 `air:M2Session:TrialsFailed`，验证器检查消息含归档路径 | **通过** |
| 5. 脏会话背靠背双链与数值复现 | 两链 2/2 PASS；两份 `pairs.csv` 哈希完全相同；门槛值在已登记抖动范围内 | **通过** |
| 6. 文档状态一致 | 修复提交把六处文档统一为完全关闭；本轮发现总验证器违规后需再次勘误 | **部分通过** |

第三轮报告中的核心缺陷 R3-F1/R3-F2/R3-F3 已按其原始关闭条件得到动态证据。第四轮新发现属于修复时新增验收基础设施的自身契约问题，不回退三入口函数化的有效性。

## 4. MATLAB/Simulink 实测证据

### 4.1 仓库总验证器

从非空调用者状态进入：

```matlab
global M2_ETA_PARAMS M2_ETA_APPLIED
M2_ETA_PARAMS = struct('mode','esc','center0',0.8123,'tag','round4caller');
M2_ETA_APPLIED = 0.8123456789;
ok4 = verify_m2_round4_closure();
```

验证器完成后打印 `ROUND-4 CLOSURE VERIFICATION PASS (10 checks)`，归档为：

```text
results/round4_closure/20260902_104606/
```

归档 `matrix.csv` 的 10 行全部为 PASS，覆盖单元测试失败、链三类失败、九场景入口成功/失败、脏会话双链、同会话确定性和门槛抖动。

### 4.2 同会话背靠背完整链

两次九场景归档：

- `results/air_m2_trials/20260902_104000/`
- `results/air_m2_trials/20260902_104321/`

两份 `pairs.csv` 的 SHA-256 均为：

```text
1B1845668E68877C35D6F337E84344E26284300BE7B1480EAC8D49F281D8CB3E
```

两次 `summary.csv` 数值逐位一致。S1/S2/S3 对应的 `[90,120] s` 门槛结果保持在修订协议允许范围内；无证据支持把这些未校准模型估算值外推为真实节能率。

### 4.3 persistent 直接动态探针

本轮额外执行了仓库验证器未直接实现的 fresh 对照：先让 `m2_eta_esc` 产生非初始 persistent 状态，再设置非恒等哨兵 global，注入单元测试失败，比较错误退出后的首次控制器输出与显式 `clear m2_eta_esc` 后的首次输出。

```text
error id      = air:M2Test:InjectedFailure
globalRestore = 1
maxDiffFresh  = 0
```

这直接证明 `test_m2_eta_esc_unit('unit')` 的 cleanup 同时完成了 global 恢复和 persistent 清理。

### 4.4 总验证器调用者状态探针

总验证器正常返回后实测：

```text
ok=1, paramsEmpty=1, appliedEmpty=1
```

入口的 `center0=0.8123`、`M2_ETA_APPLIED=0.8123456789` 没有恢复。对应源码末尾直接执行：

```matlab
M2_ETA_PARAMS = [];
M2_ETA_APPLIED = [];
clear('m2_eta_esc');
```

注释“leave the session as found”与实际行为不一致；空值是安全恒等缺省，但不是“恢复调用者状态”。

## 5. 问题清单

### R4-F1（高）：总验证器不恢复调用者全局状态

- 位置：`models/px4_x8/verify_m2_round4_closure.m` 的 global 初始化与末尾清空逻辑；
- 规则：违反 `ACCEPTANCE_AUTOMATION_RULES.md` §3.1；
- 影响：运行验收会改变同一 MATLAB 会话后续任务的入口状态，且验证器自己的成功路径没有通过它要求其他入口遵守的契约；
- 建议：函数入口立即快照两个 global，并用函数帧内 `onCleanup` 在正常/异常路径恢复；persistent 可以清理，但不能用“清空 global”替代恢复。

### R4-F2（中）：persistent fresh 在自动验证器中只被间接推断

- 位置：`verify_m2_round4_closure.m` C1 注释与判断；
- 规则：`ACCEPTANCE_AUTOMATION_RULES.md` §4.1 要求运行时声明由真实行为直接测试；
- 影响：cleanup 中未来若只恢复 global 而漏掉 `clear`，当前验证器仍可能假绿；
- 建议：把本轮的“预热 persistent → 注入失败 → 错误后首次输出与 fresh 输出比较”固化进验证器，并把差值写入归档。

### R4-F3（中）：10 行抽样矩阵被表述为完整笛卡尔覆盖

- 位置：`results/round4_closure/.../matrix.csv` 与修复报告的“全入口状态 × 退出路径”结论；
- 规则：`ACCEPTANCE_AUTOMATION_RULES.md` §4.3、§5.2；
- 影响：当前每个错误出口只用 stale sentinel，成功双链只用旧残留；没有对每个出口分别覆盖 clean、旧残留、上次错误后状态；
- 建议：要么扩展为完整组合并记录 case ID，要么把文档改称“针对性错误出口与脏会话回归矩阵”，停止使用“全矩阵”措辞。

## 6. 修复后关闭条件

1. 从非空调用者状态运行 `verify_m2_round4_closure`，正常返回和至少一个内部受控异常后两个 global 均逐域恢复；
2. 验证器内置 persistent fresh 直接输出比较，差值写入机器可查结果与归档；
3. 扩展完整入口状态 × 退出路径组合，或同步收窄规则/报告措辞，矩阵声明与实际行数一致；
4. 重跑第四轮验证器，保留两链 2/2 PASS、同会话哈希一致及 ±0.015pp 抖动口径；
5. `DEVELOPMENT_STATUS`、路线、README、AGENTS、接口文档和模型 README 对“核心 M2 PASS / 自动化部分通过”的边界一致。

## 7. 当前阶段判定

- M2 模型与 120 s 数值协议：**通过**；
- M2 三个核心入口的成功/错误恢复：**通过**；
- M2 总验收器自身状态契约：**未通过**；
- 验收基础设施对 v1.0 规则的总体符合性：**部分通过**；
- M2 当前既有技术成果：**保持放行**，但不得再写“自动化完全闭环/全规则满足”；
- M3 方案与实现：**可以继续**；在下一里程碑把总验证器作为放行门前须关闭 R4-F1--F3；
- 真实功率、真实节能、SITL/HITL/实机结论：**不支持**。
