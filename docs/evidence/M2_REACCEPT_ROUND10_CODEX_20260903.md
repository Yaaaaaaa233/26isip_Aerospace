# M2 第十轮独立验收报告（2026-09-03）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线）

验收需求与判定责任：叶安

独立验收与主要撰写：Codex（AI 协助）

审核：待项目组审核、待指导教师确认

## 1. 结论：按 v1.7 四层分开判定

本轮冻结对象为干净提交 `71acd56d084a0ee028a6d34257c1dd45341a70c0`，相对第九轮修复证据提交 `e531497` 只新增验收治理规则 v1.7、Proposed ADR-003 与交接简报，没有修改 `.slx`、eta 分配器、ESC、验证器或批次驱动。

| 判定层 | 结果 | 依据 |
|---|---|---|
| 功能实现层 | **VALIDATED / PASS** | 当前提交入库驱动整批 52/52 PASS；S1/S2/S3 数值与第六至第九轮逐位一致；C5 两链 `summary.csv` SHA-256 相同 |
| 验收基础设施层 | **VALIDATED / CLOSED（当前冻结合同）** | 驱动测试 9/9；R9-F1 两个原始协同篡改由独立探针以 `air:M2Verify:ManifestContract` 精确拒绝；52 行矩阵含四类合同负向；全部 8 份批次日志零 U+FFFD；盖章前/后两类真实堆崩溃均按规则正确处理 |
| 环境限制层 | **LIMITED / OPEN** | R2022b 本批自然发生两次 `0xC0000374`：c3 盖章后退出、c5 第 1 次盖章前退出；全量 9 场景同会话双链、report 归档路径崩溃注入和跨机器编码探针仍未覆盖 |
| 文档证据层 | **PASS；ADR-003 仍为 Proposed** | 规则 v1.7、当前状态、证据索引、接口与模型 README 采用同一分层边界；跨项目采用须项目组/架构归口确认 |

R9-F1、R9-F2 按 v1.7 §9.3 的“原始复现 + 针对性负向 + 既有回归”三件套独立关闭；本轮没有发现新的 P0/P1/P2 代码缺陷，也没有发现 M2 核心真实回归。M3 可以继续；不得把本报告外推为真实八旋翼节能、偏航安全、SITL/HITL、实机或飞控部署结论。

## 2. 冻结范围与来源绑定

| 项目 | 值 |
|---|---|
| 分支 / 提交 | `main` / `71acd56d084a0ee028a6d34257c1dd45341a70c0` |
| 相对 `e531497` 的改动 | 仅 3 个治理 Markdown；验证器、驱动、模型与算法未改 |
| 验证器 SHA-256 | `A6F82DACE72B3F8ADCA20DDFFCFF364F5CF4E5AD4027EE576ABEC6D062BE0EFD` |
| 批次驱动 SHA-256 | `079C9135582C69513C4543A2D2DC76078D851E0DA9DC837B5689EBE3B81A8D5A` |
| 规则 | `docs/ACCEPTANCE_AUTOMATION_RULES.md` v1.7 |
| MATLAB / 系统 | R2022b / Windows / WinPS 5.1 |
| Simulink 对象 | `models/px4_x8/air_spare.slx`（proxy，estimated power） |
| 本轮 runId | `88e0204a-4718-4135-b7ab-a0eb321275db` |
| 批次日志 | `results/batch_runs/20260903_013002/`（gitignored） |
| 正式归档 | `results/round4_closure/20260903_015158/`（gitignored） |

本轮开始前工作树干净，`HEAD` 比 `origin/main` 超前 1 个本地治理提交；没有 fetch/pull/push。源码绑定、验证器哈希与 dirty 门均以本地冻结提交为准。

## 3. 静态、治理与驱动层检查

| 检查 | 结果 |
|---|---|
| `tools/check_repo_governance.ps1` | PASS（12 模块 / 25 活动 Markdown） |
| `tools/test_m2_batch_driver.ps1`（WinPS 5.1） | 9/9 场景 PASS |
| 驱动 S6：rc=0 且无 fresh done | 重试至上限并中止，未假绿 |
| 驱动 S7：新归档 / 盖章后非零退出 | 正确接受新鲜证据且不重试 |
| 驱动 S8：ANSI 页 CJK 往返 | 原文保留，零 U+FFFD |
| `git diff --check e531497..71acd56` | PASS |
| 治理提交改动范围 | 仅规则、Proposed ADR 和 worklog |

## 4. 正式 MATLAB 批次

执行入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_m2_batch.ps1 `
  -Matlab D:\matlab2022b\bin\matlab.exe -MaxAttempts 3
```

| 阶段 | 行数 | attempt | 结果 |
|---|---:|---:|---|
| `init` | manifest | 1 | PASS |
| `c1c2stale` | 6 | 1 | PASS |
| `c2clean` | 3 | 1 | PASS |
| `c3` | 2 | 1 | PASS；盖章后堆崩溃，fresh done 已存在，按规则无害 |
| `c5` | 4 | 2 | PASS；第 1 次盖章前堆崩溃，无 fresh done，完整重执行后第 2 次成功 |
| `contract` | 37 | 1 | PASS |
| `report` | **52/52** | 1 | PASS |

聚合矩阵实测为 52 行、52 PASS、0 non-PASS、单一 runId；report 明确打印：

```text
manifest contract: EQUALS source contract (52 declared rows, bound 3)
stage attempts: c1c2stale=1, c2clean=1, c3=1, c5=2, contract=1
commit=71acd56d084a0ee028a6d34257c1dd45341a70c0
ROUND-4/5/6 CLOSURE VERIFICATION PASS (52 checks)
```

## 5. R9-F1 / R9-F2 关闭证据三件套

### 5.1 R9-F1：manifest 固定合同

| v1.7 关闭条件 | 本轮证据 | 判定 |
|---|---|---|
| 原始复现 1：上限 3→4 且 done/marker 同步为 4 | 独立修改正式 staged 副本后调用 report，拒绝 ID 精确为 `air:M2Verify:ManifestContract` | PASS |
| 原始复现 2：删除 c5 与 `declaredRows.c5` | 独立修改正式 staged 副本后调用 report，同一错误 ID 拒绝 | PASS |
| 针对性负向 | contract 37 行中 `manbound/manstagecut/manstageadd/manrows` 四行全部 PASS，错误必须落在合同检查 | PASS |
| 既有回归 | 52 行矩阵全部 PASS；旧批次/缺段/混提交/FAIL 行/哈希/attempt 六类负向仍通过 | PASS |

两个独立探针执行前备份 `manifest.mat`、`c5.done.mat` 与 `c5.attempts`。探针后按 SHA-256 逐文件确认恢复，c5 marker 恢复为 2；归档目录数量探针前后均为 17，没有伪造归档；临时备份已删除。

### 5.2 R9-F2：日志编码

| v1.7 关闭条件 | 本轮证据 | 判定 |
|---|---|---|
| 原始症状复验 | 同一中文路径、MATLAB 本地化警告和批次捕获路径重新执行 | PASS |
| 针对性负向 / 独立已知字节 | 驱动测试 S8 以 ANSI 页 CJK 字节通过实际捕获函数，断言原文存在且零 U+FFFD | PASS |
| 既有回归 | `20260903_013002` 的 8 份日志逐码点扫描均为 U+FFFD=0；除纯 ASCII init 外均能读到 `第二阶段` | PASS |

因此 R9-F1/R9-F2 与随之部分开放的 R8-F1 均可独立关闭。

## 6. 数值、确定性与裕量

C5 第 2 次尝试成功链：

- 链 1：`results/air_m2_trials/20260903_014448/`；
- 链 2：`results/air_m2_trials/20260903_014736/`；
- 两份 `summary.csv` SHA-256 均为 `D5FC25BF9C067DAC1620D62416EDB6235D7725B720C6E5C4B8BC2A764ED6F197`。

| 场景 | `delta_E_pct` | 对 `+0.5%` 门槛裕量 |
|---|---:|---:|
| S1 | `-0.262619229374685%` | `0.762619 pp` |
| S2 | `-0.293803703864441%` | `0.793804 pp` |
| S3 | `-0.214653662029612%` | `0.714654 pp` |

最小裕量 0.714654 pp，约为登记抖动 ±0.015 pp 的 47.6 倍，不属于骑线 PASS。c3 全量九场景单链得到相同 S1/S2/S3 数值；其 `summary.csv` 因包含额外场景，文件哈希与 nominal C5 不应直接比较。

## 7. 环境事件与问题分类

本轮出现两次自然 `0xC0000374` Heap corruption：

1. `c3` 已写出 2 行 CSV 与 done 后进程退出。类型：**环境限制 / 盖章后无害退出**；驱动以 fresh done 放行且不增加 attempt。
2. `c5` 第 1 次在链中、盖章前退出。类型：**环境限制 / 盖章前有害退出**；驱动因无 fresh done 从段入口完整重执行，第 2 次成功并记 `done.attempts=2`。

二者都不是功能层真实回归：当前冻结算法与模型未改，完整成功链数值与哈希一致；驱动没有把崩溃误报为成功，也没有混用第一次的部分结果。本轮未发现“修复一个旧问题导致既有正常功能出错”的新证据。

## 8. 覆盖边界与停止条件

- 52 行是当前源码合同定义的针对性矩阵，不是全部入口状态 × 全部退出路径的无限笛卡尔积。
- 全量 9 场景同会话双链仍未覆盖；全量九场景由 c3 单进程覆盖一次，C5 使用 nominal S1–S3 最小双链。
- report 归档写入路径的真实崩溃注入未执行。
- WinPS 5.1 已验证；本机无 pwsh 7。MATLAB 输出编码随机器/区域设置变化，换机仍需原始字节探针。
- ADR-003 为 Proposed，只约束本轮报告结构的试行，不代表项目组已经接受为全项目治理决策。
- 当前功能层与验收基础设施层无开放 P0/P1，冻结合同整批通过，R9-F1/R9-F2 三件套齐备，满足 v1.7 的本轮停止条件；剩余项目均登记为环境/覆盖限制，不继续以“发现任意新威胁”为由无限追加本轮。

## 9. 最终判定与下一步

- M2 核心实现、ESC 接线、修订数值协议：**VALIDATED，继续放行**；
- R9-F1 / R9-F2 / R8-F1：**CLOSED**；
- 当前冻结验收基础设施合同：**VALIDATED**；
- R2022b 环境稳定性：**OPEN LIMITATION**；
- Proposed ADR-003：等待项目组/架构归口复核；
- 后续平台工作：按路线继续 M3 和 Plane 汇合；换 MATLAB 版本或机器后补全量同会话双链与编码原始字节复核。
