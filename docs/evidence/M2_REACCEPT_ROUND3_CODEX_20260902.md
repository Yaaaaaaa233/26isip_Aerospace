# M2 第三轮独立复验报告（Codex，2026-09-02）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线，延续现有责任记录）

主要撰写：待项目组确认

技术贡献：Codex（主库版本核对、MATLAB/Simulink 实际复跑、受控失败注入、状态恢复审查与验收判定）

审核：待项目组审核、待指导教师确认

AI 协助：Codex（复验执行与文档代拟）

## 1. 结论

**第三轮复验结论：部分通过。M2 数值协议和完整链正常成功路径通过；异常退出时的会话状态恢复仍未通过。**

- 主库提交 `bbc5990` 的链入口规范化有效：在第二轮报告使用的原样脏状态下，同一 MATLAB 会话连续两次运行完整链均通过，无需在两次之间人工清理。
- 两次九场景结果逐位一致，`summary.csv` 和 `pairs.csv` 的 SHA256 分别完全相同；S1/S2/S3 的 `[90,120] s` 门槛窗结果为 −0.25985% / −0.29211% / −0.22617%，数值结论继续有效。
- 链尾 `assert(result.pass, 'air:M2Session:TrialsFailed', ...)` 已存在；用 `pass=false` 的非破坏性构造结果复验，正确抛出 `air:M2Session:TrialsFailed`，R2-F2 可以关闭。
- 但真实受控断言失败证明：`test_m2_eta_esc_unit` 和 `run_m2_session_chain` 均不能在错误退出时恢复调用者入口状态。它们仍是脚本，`onCleanup` 对象留在脚本/调用者工作区；错误发生在显式清理或正常结束之前时，回调没有在该错误边界执行。
- 因此 R2-F1 只能判定为“正常成功路径通过、错误路径未通过”，R2-F3 重新打开。第二轮修复报告关于“成功或异常均恢复”和“错误路径统一 cleanup”的强结论被本报告修订。

M3 的接口、仲裁与场景方案设计可以继续；在异常清理修复并完成第四轮针对性复验前，建议继续暂缓 `air_m2.slx` 之后的 M3 结构集成。该限制是验收自动化可靠性限制，不推翻当前 M2 算法、模型快照或 120 s 数值结果。

## 2. 版本、环境与范围

| 项目 | 值 |
|---|---|
| 主库提交 | `bbc599095406befad072ba54301f873a01a8e315`（`Close round-2 M2 reacceptance findings: chain normalization, trials assert`） |
| 本地与远端 | 复验开始时 `main` 与 `origin/main` 一致，跟踪工作树干净 |
| MATLAB | R2022b，Windows GUI 实际运行 |
| Simulink 对象 | `models/px4_x8/air_spare.slx`，未修改 `.slx` |
| 复验入口 | `run_m2_session_chain`、`test_m2_eta_esc_unit` |
| 源码/模型改动 | 无；仅产生 `.gitignore` 排除的本地 `results/` 证据，并新增本报告/工作日志及状态文档勘误 |

本轮只验收叶安负责的 `models/px4_x8` M2 平台线修复，不重新验收算法线其他模块。

## 3. 第二轮关闭条件逐项复验

| 第二轮条件 | 第三轮独立结果 | 判定 |
|---|---|---|
| 链入口自动规范化，不要求手工清理 | 原样脏入口直接运行完整链，旁路差 0、安全注入 4/4、九场景 PASS | 正常路径通过 |
| 同一会话背靠背完整链 2/2 | 两次归档 `20260902_000152`、`20260902_000537`，中间零人工清理 | 通过 |
| 链结束或异常时恢复调用者状态 | 正常结束恢复；受控 `CompareFailed` 后入口 `esc/0.87、0.87654321` 被留成 `fixed/1.0、1.0` | **未通过** |
| 九场景失败必须硬退出 | 同一断言表达式用 `pass=false` 验证，抛出 `air:M2Session:TrialsFailed` | 通过 |
| 单元测试错误路径恢复 global 且清 persistent | 受控 U1 断言失败后 `M2_ETA_APPLIED` 从入口 `0.913456789` 留成 `1.0`，cleanup 未执行 | **未通过** |
| 勘误与状态文档一致 | `DEVELOPMENT_STATUS` / 路线一度写“全部关闭”，而 README、AGENTS、接口与模型 README 仍写“部分通过/待修” | 本轮同步修正 |

## 4. 正常成功路径的 MATLAB 实测证据

### 4.1 脏入口

在同一个已有历史变量的 MATLAB 会话中，先建立与第二轮报告同型的脏入口：

```matlab
global M2_ETA_PARAMS M2_ETA_APPLIED
M2_ETA_PARAMS = struct('mode', 'esc', 'center0', 1.0);
M2_ETA_APPLIED = 0.99914776890319873;
clear m2_eta_esc
```

随后直接运行 `run_m2_session_chain`，不在链内部阶段之间人工清理。

### 4.2 链 1

- 单元测试：PASS；
- 旁路比较：最大差 0，归档 `results/air_m0a_baseline_compare/20260902_000125/`；
- M0-B 安全注入：4/4 PASS，归档 `results/air_m0b_safety_injection/20260902_000126/`；
- M2 九场景：PASS，归档 `results/air_m2_trials/20260902_000152/`；
- 链结束后入口状态恢复为 `mode=esc`、`center0=1`、`M2_ETA_APPLIED=0.99914776890319873`。

### 4.3 链 2（同会话、零清理承接）

链 1 结束后立即再次执行 `run_m2_session_chain`：

- 单元测试：PASS；
- 旁路比较：最大差 0，归档 `results/air_m0a_baseline_compare/20260902_000512/`；
- M0-B 安全注入：4/4 PASS，归档 `results/air_m0b_safety_injection/20260902_000513/`；
- M2 九场景：PASS，归档 `results/air_m2_trials/20260902_000537/`；
- 链结束后仍恢复同一脏入口状态。

### 4.4 两次九场景一致性

| 配对 | `P_fixed_W` | `P_esc_W` | `delta_E_pct` `[90,120] s` | 连续性值 `[20,30] s` | 收敛时间 |
|---|---:|---:|---:|---:|---:|
| S1 | 251.000857487803 | 250.348640019029 | −0.259847588795229% | +0.353363514349392% | 100 s |
| S2 | 251.000857487803 | 250.267646794366 | −0.292114553384851% | −0.293021613955402% | 0 s |
| S3 | 251.000857487803 | 250.433152473864 | −0.226174104003906% | +0.506190353442646% | 104 s |

两次归档文件哈希：

- `summary.csv`：`B293F0A1E926DC7927DFD823117B0CF1AA25BF3BC76CEED503C5FE377E36990B`（两次相同）；
- `pairs.csv`：`1B1845668E68877C35D6F337E84344E26284300BE7B1480EAC8D49F281D8CB3E`（两次相同）。

这证明 `bbc5990` 的入口规范化对正常链有效，并且没有改变 M2 既有数值结果。

## 5. 受控失败复验

所有失败均通过 MATLAB 调试断点在内存中修改局部结果制造；未修改任何 `.m` / `.slx` 文件，也未破坏归档。

### 5.1 单元测试错误路径

测试入口状态：

```text
M2_ETA_PARAMS.mode    = esc
M2_ETA_PARAMS.center0 = 0.91
M2_ETA_APPLIED        = 0.913456789
```

在 `test_m2_eta_esc_unit.m:56` 的 U1 identity 断言前暂停，将 `pwm1(1)` 改为 0 后继续，使仓库原有断言真实失败。错误返回命令行后观测：

```text
mode=esc, center0=0.91, M2_ETA_APPLIED=1, restoreGlobals exists=1
```

`M2_ETA_APPLIED` 已在测试第 53 行改为 1.0，却没有恢复为入口值 `0.913456789`。由于 `clear('m2_eta_esc')` 与 global 恢复位于同一个未执行的回调中，代码声称的错误路径 persistent 清理同样没有发生；本次早期失败发生在适配器运行前，因此未另外量化残留 persistent 数值。

### 5.2 完整链错误路径

链入口状态：

```text
M2_ETA_PARAMS.mode    = esc
M2_ETA_PARAMS.center0 = 0.87
M2_ETA_APPLIED        = 0.87654321
```

链先正常完成单元测试和旁路比较。在 `run_m2_session_chain.m:34` 的已有 `assert(r1.pass, ...)` 前暂停，将 `r1.pass=false` 后继续，真实触发 `air:M2Session:CompareFailed`。错误返回命令行后观测：

```text
mode=fixed, center0=1, M2_ETA_APPLIED=1, chainCleanup exists=1
```

链没有恢复调用者入口的 `esc/0.87、0.87654321`，而是留下链内规范化状态。这直接否定了代码注释与第二轮修复报告中的“成功或异常均恢复”。

### 5.3 九场景硬断言

使用与链尾相同的断言表达式，将非破坏性构造结果设为 `pass=false`，实际捕获：

```text
air:M2Session:TrialsFailed: M2 trials failed, archive proof/round3
```

R2-F2 的硬失败逻辑成立。这里验证的是断言表达式及错误标识；正常两链则验证了真实 `result.pass=true` 的成功路径。

## 6. 根因判断

`run_m2_session_chain.m`、`run_air_m2_trials.m` 和 `test_m2_eta_esc_unit.m` 当前都是脚本，不是函数。脚本变量进入调用者工作区。正常路径上，单元测试用 `restoreGlobals=[]` 显式触发 cleanup；完整链成功结束也表现为正确恢复。但发生断言/错误时，脚本没有函数栈帧可供可靠析构，`restoreGlobals` / `chainCleanup` 对象仍留在工作区，回调没有在错误返回边界执行。

因此问题不是数值算法、Simulink 模型或入口规范化本身，而是“用脚本工作区中的 `onCleanup` 承诺错误恢复”的生命周期设计不可靠。

## 7. 问题清单

### R3-F1（高）：完整链异常退出不恢复调用者状态

- 位置：`models/px4_x8/run_m2_session_chain.m:25-29`；
- 影响：任何 compare / injection / trials 断言失败后，MATLAB 会话可能保留 `fixed/1.0` 或阶段中间状态，后续诊断不再拥有可预测入口；
- 状态：R2-F1 的成功路径关闭，错误路径重新打开。

### R3-F2（高）：单元测试错误路径 cleanup 未执行

- 位置：`models/px4_x8/test_m2_eta_esc_unit.m:47-48`、`:159`；
- 影响：断言失败发生在第 159 行显式清理之前时，global 和 persistent 不按入口快照恢复；
- 状态：R2-F3 重新打开。

### R3-F3（中）：第二轮关闭报告缺少真实错误路径执行

- 第二轮报告对单元测试错误路径采用“代码审查 + 正常重跑”，未制造实际内部错误；
- 非破坏性 `pass=false` 只证明链尾断言表达式，并不证明外围 `onCleanup` 在错误后执行；
- 本轮真实断言失败揭示了该验证空档。

## 8. 修复建议

优先采用函数边界，不再依赖脚本工作区析构：

1. 将 `run_m2_session_chain` 改为函数入口，并让 `result` 作为输出返回；函数局部 `onCleanup` 可在正常返回和异常栈展开时可靠执行。
2. 将 `run_air_m2_trials` 改为 `function result = run_air_m2_trials()`；链改为 `result = run_air_m2_trials(); assert(result.pass, ...)`，避免脚本通过共享变量交接结果。
3. 将 `test_m2_eta_esc_unit` 改为函数，或至少用显式 `try/catch` 在 catch 中调用恢复函数后 `rethrow`；函数化更简洁。
4. 添加可控、非破坏性的错误注入测试钩子或专用测试函数，分别在单元测试、baseline compare 后和 trials 结果检查前触发错误，自动断言入口 global 与 persistent 均恢复。
5. 保留现有脏入口背靠背双链测试，防止修复错误路径时回归正常路径。

## 9. 第四轮关闭条件

只有以下条件全部满足，才可再次写“M2 自动化完全闭环”：

1. 单元测试受控内部断言失败后，`M2_ETA_PARAMS`、`M2_ETA_APPLIED` 精确恢复入口值，并证明 `m2_eta_esc` persistent 等价于 fresh 状态；
2. 完整链在 compare、injection、trials 三类错误出口后都恢复调用者入口状态；
3. `run_air_m2_trials` 单独运行成功和受控失败均不改变调用者入口状态；
4. 链尾 trials 失败继续抛出 `air:M2Session:TrialsFailed` 并携带归档路径；
5. 同一脏会话背靠背完整链仍 2/2 PASS，九场景 CSV 与本报告哈希一致；
6. `DEVELOPMENT_STATUS`、路线、README、AGENTS、接口文档和模型 README 对 M2/M3 放行状态一致。

## 10. 当前阶段判定

- M2 模型/算法数值：**通过**；
- M2 正常成功路径自动化：**通过**；
- M2 异常恢复与工程自动化：**未通过**；
- M2 总体：**部分通过**；
- M3 接口、仲裁、场景与验收方案：**可以继续**；
- M3 `.slx` 结构集成：**第四轮关闭 R3-F1/F2 前暂缓**；
- 真实节能、真实功率、SITL/HITL/实机结论：**不支持**。
