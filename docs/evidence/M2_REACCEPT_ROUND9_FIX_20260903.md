# M2 第九轮发现修复与关闭验证（2026-09-03）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线）

验收需求与判定责任：叶安

主要撰写：ZCode（AI 协助，修复执行与本文档代拟）

审核：待项目组审核、待指导教师确认

AI协助：ZCode（R9-F1/R9-F2 修复实现、探针与正式批次执行、本文档代拟）

## 1. 结论

**R9-F1 与 R9-F2 已修复并验证关闭。** 当前提交 `3d3fa51` 在入库驱动下整批复跑 **52/52 PASS**（矩阵 48→52 行：新增 4 行 manifest 合同负向证明），staged manifest 与验证器源码中的单一固定合同 `expectedManifestContract()` 做等值硬断言；第九轮两枚协同篡改探针（提上限含自洽 stamps、删 c5 与声明行）以及增阶段（配齐文件）/改声明行数两类扩展探针全部被 `air:M2Verify:ManifestContract` 拒绝且零归档写入。批次日志编码修复后中文无损（真实 MATLAB 端到端 `cn=True fffd=False`，新批次日志扫描零 U+FFFD）。R8-F1 随之完全关闭（attempt 记账断言 + manifest 合同等值断言）。

- M2 功能与代理数值结论：继续放行（门槛值与本轮登记值逐位一致，见 §4）；
- R9-F1：**CLOSED**（源码固定合同 + 等值断言 + 四类负向 case 进矩阵 + 独立拒绝探针）；
- R9-F2：**CLOSED**（显式 ANSI 页解码 + UTF-8 写档 + 驱动层往返测试 S8 + 真实 MATLAB 端到端 + 新批次日志复验）；
- 验收自动化整体：规则文档同步升 **v1.6**（规则 8/规则 9）；
- 边界不变：环境级 R2022b 堆损坏与启动器退出码不可靠未消灭；全量 9 场景同会话双链仍为环境限制未覆盖组合；不宣称"完全闭环"；
- 批次内意外收获：c2clean 第 1 次尝试**自然**堆损坏崩溃（`0xC0000374`）→ 驱动完整重执行 → 第 2 次成功、`done.attempts=2` 如实记账——R8 登记的遗留项"正式批次内自然崩溃—重试—成功组合"关闭（此前仅有受控击杀代理证据）。

本报告只支持 `air_spare.slx` 代理平台，不支持真实八旋翼节能、偏航安全、SITL/HITL、实机或飞控部署结论。

## 2. 修复内容与提交

| 提交 | 内容 | 对应发现 |
|---|---|---|
| `951d7a3` | 验证器：新增 `expectedManifestContract()` 单一合同源（stages/declaredRows/maxAttempts=3，总数 52），init 从它写入 manifest；段入口、`validateStaged`、`writeAggregate` 三处硬断言 staged manifest 与合同等值（`air:M2Verify:ManifestContract`：上限等值而非 ≥1、阶段名单/数量/顺序/唯一全等、声明行数逐字段全等）；`runContract` 新增 manbound/manstagecut/manstageadd/manrows 四行负向 case（man* 必须在合同检查本身报错）；`cloneStaged` 改为合成完整五段一致 toy（含合成 contract.csv/done/marker），防止既有 11 个篡改负向证明被新合同断言短路而空转；顺带修正文件头陈旧的 42/27 计数（R8 时漏更新） | R9-F1 |
| `2c3c6c3` | 驱动：新增 `Invoke-LoggedNative`——按系统 ANSI 代码页（`[System.Text.Encoding]::Default`）显式解码原生命令输出、写 UTF-8 日志、事后恢复控制台编码；段调用改走该函数；驱动测试新增 S8（ANSI 页 CJK 字节经 `cmd /c type` 走同一捕获路径，断言日志含原文且零 U+FFFD），8→9 场景 | R9-F2 |
| `3d3fa51` | 规则文档 v1.6：规则 8（staged manifest 是证据不是权威：单一源码合同 + 等值断言 + 四类协同篡改负向证明且错误落在合同检查本身）、规则 9（日志编码无损：按实际输出编码显式解码、非 ASCII 往返断言、跨机器以原始字节探针复核）；§6 清单同步两条 | R9-F1/R9-F2 |

验证器 SHA-256 @ `3d3fa51`：`a6f82dace72b3f8adca20ddffcff364f5cf4e5ad4027ee576abec6d062be0efd`。

设计取舍（对照第九轮报告 §7 修复要求逐条）：

1. 单一 `expectedManifestContract()` 由 init 与 report（及每个段入口）共用——已实现；
2. report 硬断言 `maxAttempts` 为有限正整数**且等于源码合同值 3**——已实现（等值断言，非 ≥1）；
3. `stages` 名称、数量、顺序、唯一性与源码合同全等——已实现（`iscellstr` + 去重校验 + `isequal` 全等）；
4. `declaredRows` 字段集合与每段行数完全一致、总行数等于合同的 52——已实现（结构体 `isequal` 逐字段全等；聚合器另有 declared==aggregated 断言，本轮实测 52）；
5. 四类负向 case（改上限/删阶段/增阶段/改行数）由 report 拒绝——已实现进矩阵（52 行），且错误 ID 必须是 `ManifestContract`（防止被旁因失败覆盖的空转证明）；"增阶段"case 配齐 csv/done/marker，证明拒绝来自合同检查而非缺文件；
6. 第 6 条（done stamp 内嵌合同摘要）**未采用**：摘要复算同样依赖 staged manifest 字段，等值断言才是根，嵌套摘要反而引入第二权威；此取舍为实施方判断，待验收方复核。

## 3. 测试与探针（提交后、正式批次前）

| 项 | 结果 |
|---|
| checkcode（验证器 @951d7a3） | 9 条全部为既有接受的 global 变量警告，零新增（初版曾引入 2 条跨行字符串拼接解析错误，已修复） |
| 驱动层测试（WinPS 5.1，@2c3c6c3） | **9/9 场景 PASS**（原 8 + S8 编码往返） |
| 拒绝探针（独立 MATLAB 进程，真实 staged 目录，双备份恢复） | 四臂全部 **REJECTED id=air:M2Verify:ManifestContract 且归档目录零变化**；正向对照（一致性基线重绑到当前提交 + 52 行合同）**PASS 52 checks**，其产生的归档即时删除；探针后 Codex 第九轮原始 staged 证据完整恢复（runId `1edb644d`、maxAttempts=3、五段、contract=33） |
| 编码探针 1（会话默认/UTF-8/936 三臂，脚本字面量路径） | 暴露 PS 5.1 无 BOM 脚本按 ANSI 误读中文路径（探针自身入坑，实证留档）；arm 结论不可靠，作废重测 |
| 编码探针 3（纯 ASCII 源 + MATLAB 内部 `char()` 造中文，raw 字节取证） | **MATLAB -batch 管道原始字节为 GBK**（`d6d0 cec4 b5da…`）；cp936 臂完美往返（含本地化 `警告` 标签），UTF-8 臂 U+FFFD——真实批次乱码根因是会话控制台编码与 MATLAB ANSI 输出页不一致 |
| 编码端到端（驱动 `Invoke-LoggedNative` + 真实 MATLAB） | `rc=0 cn=True fffd=False`：fprintf 与 warning 两路径中文均无损（首跑对照串码点笔误 27969≠0x6D4B，修正后复跑干净） |
| 治理检查（提交前） | PASS（12 模块 / 24 Markdown，见 §7） |

## 4. 正式批次（当前 HEAD `3d3fa51`，入库驱动）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_m2_batch.ps1 `
  -Matlab D:\matlab2022b\bin\matlab.exe -MaxAttempts 3
```

| 阶段 | 行数 | attempt | 结果 |
|---|---:|---:|---|
| `init` | manifest | 1 | PASS |
| `c1c2stale` | 6 | 1 | PASS |
| `c2clean` | 3 | **2** | PASS（第 1 次尝试自然堆崩溃，见下） |
| `c3` | 2 | 1 | PASS |
| `c5` | 4 | 1 | PASS |
| `contract` | 37 | 1 | PASS |
| `report` | **52/52** | 1 | PASS |

| 聚合项 | 值 |
|---|
| runId | `78281368-0a5f-449f-82ce-26827f44924f` |
| 批次日志 | `results/batch_runs/20260903_004644/` |
| 正式归档 | `results/round4_closure/20260903_011133/`（result.mat 含 stageAttempts 与 maxAttempts=3） |
| 矩阵 | 52 行、52 PASS、0 non-PASS、单一 runId |
| report 控制台 | `manifest contract: EQUALS source contract (52 declared rows, bound 3)`；`stage attempts: c1c2stale=1, c2clean=2, c3=1, c5=1, contract=1` |
| C5 链 1 / 链 2 | `results/air_m2_trials/20260903_010503/` / `20260903_010727/` |
| 两链 `summary.csv` SHA-256 | 均为 `D5FC25BF9C067DAC1620D62416EDB6235D7725B720C6E5C4B8BC2A764ED6F197`（第 7 次跨批复现） |

**自然崩溃—重试—成功组合（本批次的意外收获）**：c2clean 第 1 次尝试以 `rc=-1073740940`（`0xC0000374` 堆损坏，attempt1 日志尾部留有 MATLAB "Heap corruption" 错误记录）死亡、未产出任何新鲜证据；驱动按规则 v1.5(a) 判为可重试崩溃、从段入口完整重执行，第 2 次尝试干净完成，`done.attempts=2` 如实入档并由 report 逐段打印。此前该组合只有第八轮的受控击杀代理证据，R8 登记的遗留项"正式批次内自然发生的崩溃—重试—成功"由此关闭。

门槛与裕量（对 `+0.5%` 门槛，登记抖动 ±0.015 pp）：

| 场景 | `delta_E_pct`（12 位小数） | 裕量 |
|---|---:|---:|
| S1 | `-0.262619229375%` | `0.762619 pp` |
| S2 | `-0.293803703864%` | `0.793804 pp` |
| S3 | `-0.214653662030%` | `0.714654 pp` |

与第八/九轮登记值逐位一致；最小裕量 0.714654 pp ≈ 47.6× 抖动，不属于骑线。

**日志编码复验（R9-F2 批次级证据）**：`20260903_004644` 全部 8 份阶段日志（含 c2clean 两份尝试日志）U+FFFD 计数均为 **0**；第九轮批次同口径为 6/7 份日志各含 244–760 个替换符。

## 5. 覆盖边界

- 本轮完整执行 52 行针对性矩阵（48 行原矩阵 + 4 行 manifest 合同负向），不宣称全部入口状态 × 全部出口路径的笛卡尔积。
- 拒绝探针的"正向对照"通过**重绑基线**（把第九轮 48 行证据的 manifest/done 身份字段改写为当前提交并补造 52 行合同的 contract 段）证明无过度阻断——这是对验证逻辑的探针手段，该基线已销毁，正式判定只认 §4 的完整批次。
- 全量 9 场景同会话双链仍为 R2022b 环境限制下的未覆盖组合；全量场景由 `c3` 单进程覆盖一次。
- 自然发生的崩溃—重试—成功组合本轮在 c2clean 上自然发生并关闭 R8 遗留登记；report 段（归档写入路径）的崩溃注入仍未执行，维持未覆盖。
- 环境级 R2022b 堆损坏与 matlab 启动器退出码不可靠没有被消灭（规则 v1.5 7a/v1.6 语义照旧）。
- MATLAB 输出编码属机器/区域设置：规则 v1.6 第 9 条要求跨机器复跑时以原始字节探针复核；本轮全部证据来自本机（ANSI=cp936）。

## 6. 诚实记录

- 探针 1 的三臂结论曾被脚本自身编码问题污染（无 BOM 中文路径按 ANSI 误读），产生过一次误导性"UTF-8 臂干净"的假象；以探针 3 的原始字节取证为准。此坑与 R9-F2 同根（PS 5.1 对无 BOM 文件的 ANSI 解读），已作为教训写入规则 v1.6 第 9 条的跨机器复核要求。
- 拒绝探针曾在首版设计中把"重绑基线"覆盖写回唯一备份（会把伪造绑定证据留在 staged）；实现前自查发现并改为双备份（原始/基线分离），最终恢复的是 Codex 原始证据。
- 编码端到端探针首跑 `cn=False` 为对照字符串码点笔误（MATLAB 侧 27969=流，期望串误写 0x6D4B=测），捕获本身无损；已修正复跑。
- 修复提交 `951d7a3` 的初版 checkcode 曾报 2 条字符串拼接解析错误（跨行拼接漏方括号），提交前已修复，提交内为净版。
- 验证器文件头的声明矩阵计数在 R8 扩行时漏更新（仍写 42/27），本轮顺带修正为 52/37；属文档性陈旧，不影响历轮矩阵数据本身。

## 7. 状态同步与治理

四处状态文档（`docs/DEVELOPMENT_STATUS.md`、`models/px4_x8/README.md`、`docs/interfaces/M2_ETA_ALLOCATOR.md`、`docs/evidence/README.md`）与 worklog 已同步为"第九轮发现已修复、当前提交 52/52"口径；治理脚本提交前执行 PASS（12 模块 / 24 Markdown）。

## 8. 判定

- **R9-F1 CLOSED / R9-F2 CLOSED**；R8-F1 随合同等值断言完全关闭；
- M2 核心实现、ESC 接线与修订数值协议继续放行；M3 可继续并行推进；
- 验收自动化按规则 v1.6 语义运行；下一轮独立复验建议按第九轮报告 §8 清单 + v1.6 新增两条自检项执行。
