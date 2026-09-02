# M2 第九轮独立验收报告（2026-09-03）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线）

验收需求与判定责任：叶安

独立执行与主要撰写：Codex（AI 协助）

审核：待项目组审核、待指导教师确认

## 1. 结论

**第八轮修复后的当前 `2be9857` 在仓库内驱动下独立整批复跑 48/48 PASS，M2 核心实现、ESC 接线与修订数值协议继续放行。R8-F2（入库有界重试驱动）和 R8-F3（attempt marker 原子替换）可关闭。**

**R8-F1 只能部分关闭。** 六类直接 attempt 篡改已被拒绝，但 `manifest.mat` 本身仍被聚合器当作可变权威，未与验证器中的固定批次合同做等值校验：

1. 将 `manifest.maxAttempts` 从 3 改为 4，同时将 `c5.done.attempts` 与 `c5.attempts` 改为 4，`report` 仍输出 48 checks PASS；
2. 从 `manifest.stages` 与 `manifest.declaredRows` 同时删除整个 `c5` 阶段，`report` 仍输出 44 checks PASS。

因此第九轮判定为：

- M2 功能与代理数值结论：**PASS，继续放行**；
- R8-F2、R8-F3：**CLOSED**；
- R8-F1：**PARTIAL**；
- 验收自动化整体：**PARTIAL（R9-F1，P1）**；
- M3 可继续并行开发，但在 R9-F1 修复前不得宣称“manifest 绑定已闭环”或“验收自动化完全闭环”。

本报告只支持 `air_spare.slx` 代理平台，不支持真实八旋翼节能、偏航安全、SITL/HITL、实机或飞控部署结论。

## 2. 验收对象与来源绑定

| 项目 | 值 |
|---|---|
| 分支 | `main` |
| 验收 HEAD | `2be985792363ec5f0e32b5f9c3221f3a6cbfb3aa` |
| 同步状态 | 验收开始时本地 `main` = `origin/main` = `fork/main` |
| 第八轮后代码提交 | `fea8a33`（attempt 断言/原子 marker）、`bda0309`（入库驱动）、`6f6672c`（新鲜证据判据） |
| 第八轮修复证据提交 | `2be9857` |
| 验证器 SHA-256 | `BA40A134FCB782BDE6E6D71059DD7118B096922CC1E5B8F33A794D76C214A40E` |
| MATLAB / Shell | MATLAB R2022b；Windows PowerShell 5.1；独立 `-batch` 阶段进程 |
| 证据等级 | `proxy`，未标定估算功率 |

验收开始与结束时 Git 工作树均干净。动态结果写入 `.gitignore` 覆盖的 `results/`。

## 3. 独立执行结果

### 3.1 静态、驱动与治理检查

| 检查 | 结果 |
|---|---|
| `git diff --check 2bac6b3..2be9857` | PASS |
| `tools/test_m2_batch_driver.ps1`（WinPS 5.1） | 8/8 场景 PASS |
| `tools/check_repo_governance.ps1`（WinPS 5.1） | PASS（12 模块 / 24 Markdown） |
| 代码审计 | `validateStaged` 已校验 done attempt；`bumpAttempts` 已采用 temp + replace；发现 manifest 合同未固定 |

驱动 8 场景覆盖：无 done 的非零退出重试、新鲜 done 后非零退出不重试、确定性失败满额中止、rc-only、陈旧 done、rc=0 但无 done、report 新归档证据及归档后退出。

### 3.2 当前 HEAD 完整 MATLAB 批次

运行入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_m2_batch.ps1 `
  -Matlab D:\matlab2022b\bin\matlab.exe -MaxAttempts 3
```

| 阶段 | 行数 | attempt | 结果 |
|---|---:|---:|---|
| `init` | manifest | 1 | PASS |
| `c1c2stale` | 6 | 1 | PASS |
| `c2clean` | 3 | 1 | PASS |
| `c3` | 2 | 1 | PASS |
| `c5` | 4 | 1 | PASS |
| `contract` | 33 | 1 | PASS |
| `report` | **48/48** | 1 | PASS |

| 聚合项 | 值 |
|---|---|
| runId | `1edb644d-153f-49a2-832a-6d11f97ac507` |
| 批次日志 | `results/batch_runs/20260902_233222/` |
| 正式归档 | `results/round4_closure/20260902_234826/` |
| 矩阵 | 48 行、48 PASS、0 non-PASS、单一 runId |
| C5 链 1 / 链 2 | `results/air_m2_trials/20260902_234239/` / `20260902_234445/` |
| 两链 `summary.csv` SHA-256 | 均为 `D5FC25BF9C067DAC1620D62416EDB6235D7725B720C6E5C4B8BC2A764ED6F197` |

本次正式批次未发生自然堆崩溃，五段均为 attempt 1；这不替代第八轮修复报告中受控击杀后 attempt 2 成功的证据。

## 4. 数值门槛与裕量

| 场景 | `delta_E_pct` | 对 `+0.5%` 门槛裕量 |
|---|---:|---:|
| S1 | `-0.262619229374685%` | `0.762619 pp` |
| S2 | `-0.293803703864441%` | `0.793804 pp` |
| S3 | `-0.214653662029612%` | `0.714654 pp` |

最小裕量 `0.714654 pp`，约为登记抖动 `±0.015 pp` 的 47.6 倍，不属于骑线 PASS；与此前登记值一致。

## 5. R8-F3 原子 marker 独立探针

在正式归档后，以已有 `c1c2stale.attempts=1` 为起点执行短进程受控钩子：

| 探针 | MATLAB 退出 | 正式 marker | 临时文件 | 判定 |
|---|---:|---:|---|---|
| `pre` | 1 | 1 | 无 | 写前退出保留旧值 |
| `mid` | 1 | 1 | 值为 2 | 临时文件完成、正式值未截断 |
| `post` | 1 | 2 | 无 | 替换后退出保留新值 |
| 再次 `post` | 1 | 3 | 无 | 连续替换成立 |
| 无钩子第 4 次入口 | 1，`air:M2Verify:AttemptBudget` | 3 | 无 | 超预算在写前拒绝 |

探针结束后已恢复五段 marker 均为 1，无 `.tmp` 或备份残留。因此 R8-F3 关闭。

## 6. manifest 协同篡改负向探针

两个探针均在正式 48/48 归档后执行；原 staged 文件先备份，探针后恢复，伪归档精确删除，正式归档 `20260902_234826` 保留。

### 6.1 上限协同篡改

- `manifest.maxAttempts: 3 -> 4`；
- `c5.done.attempts: 1 -> 4`；
- `c5.attempts: 1 -> 4`；
- `report` 输出 `manifest.maxAttempts=4`、`c5=4`，仍返回 `ROUND9_MANIFEST_TAMPER_ACCEPTED=1` 与 48 checks PASS；
- 伪归档 `results/round4_closure/20260902_235631/` 已删除。

### 6.2 阶段覆盖缩减

- 从 `manifest.stages` 删除 `c5`；
- 从 `manifest.declaredRows` 删除 `c5` 字段；
- `report` 不再校验 `c5.csv`、`c5.done.mat` 与 marker，仍返回 `ROUND9_COVERAGE_TAMPER_ACCEPTED=1` 与 44 checks PASS；
- 伪归档 `results/round4_closure/20260902_235859/` 已删除。

这说明当前验证的是“stage 证据是否符合当前 manifest”，却没有验证“当前 manifest 是否仍等于提交中定义的批次合同”。

## 7. 发现与修复要求

### R9-F1（P1）：manifest 操作合同可被协同篡改并缩减验收范围

**影响：** staged 目录被修改时，可提高 attempt 上限，或删除整个阶段与声明行，最终 report 仍给出 PASS。因而 `manifest.maxAttempts=3`、五阶段集合和 48 行覆盖尚不是硬断言的版本化事实。

**必须修复：**

1. 在验证器源码中提供单一 `expectedManifestContract()`（或等价固定合同），由 init 与 report 共用；
2. report 硬断言 `maxAttempts` 为有限正整数且**等于源码合同值 3**，不能只断言 `>=1`；
3. 硬断言 `stages` 的名称、数量、顺序、唯一性与源码合同完全一致；
4. 硬断言 `declaredRows` 字段集合与每阶段行数完全一致，并断言总行数为当前合同的 48；
5. 增加至少“改上限”“删阶段/声明行”“增阶段/重复阶段”“改声明行数”负向 case，必须由 report 拒绝；
6. 可额外把规范化 manifest 合同摘要写入每个 done stamp 并在 report 复算，但摘要不能代替上述源码合同等值断言。

### R9-F2（P2）：WinPS 5.1 批次日志中的中文输出发生编码损坏

本轮 7 份阶段日志中除 init 外均出现 Unicode replacement character；例如中文路径 `第二阶段` 被记录为乱码。PASS/FAIL 英文与数值仍可审计，因此不影响本轮判定，但不符合“完整控制台输出留档”的可读性目标。

建议驱动在 WinPS 5.1 下显式按 MATLAB 实际输出代码页解码后再写 UTF-8，并加入包含中文路径/中文警告的驱动测试，断言日志不含 `U+FFFD`。

## 8. 覆盖边界与下一轮最小清单

- 本轮完整执行当前验证器声明的 48 行针对性矩阵，不宣称全部入口状态 × 全部退出路径的笛卡尔积。
- 全量 9 场景同会话双链仍为 R2022b 环境限制下的未覆盖组合；全量场景由 `c3` 单进程覆盖一次。
- 自然发生的崩溃—重试—成功组合本轮未出现；第八轮修复报告的正式批次使用受控击杀代理。
- 环境级 R2022b 堆损坏与启动器退出码不可靠没有被消灭。

下一轮至少应：修复 R9-F1 的固定 manifest 合同断言；执行上述四类 manifest 负向 case；复跑驱动层测试、原子 marker 探针与当前 48 行整批；报告真实 attempts、数值裕量和日志编码复验。
