# M2 第八轮独立验收报告（2026-09-02）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线）

独立验收与主要撰写：Codex（AI 协助）

审核：待项目组审核、待指导教师确认

## 1. 结论

**第八轮在当前 `798f60e` 上独立复跑得到 42/42 PASS，C5 最小同会话双链本轮第 1 次尝试完成，两链哈希一致，M2 核心实现、ESC 接线和修订数值协议继续放行。**

**但第七轮新增的“有界重试 + attempt 诚实记账”尚未完全闭环：聚合器未校验 `done.attempts` 的存在性、取值范围及与 `<stage>.attempts` 持久标记的一致性。负向探针将 `c5.done.attempts` 从 1 改为超过规则上限的 4 后，`report` 仍输出 42/42 PASS。同时，实际执行“非零退出且无 done 才重试、最多 3 次”的批次驱动仅存于仓库外临时脚本，当前仓库不能独立复现该语义。**

因此本轮判定为：

- M2 功能与代理数值结论：**PASS，继续放行**；
- C5 链后 `bdclose('all')` 与正常路径 attempt 落盘：**本轮实跑 PASS**；
- 有界重试与诚实记账的验收自证：**PARTIAL，R8-F1/R8-F2 未关闭**；
- M3 可继续推进，但在修复前不得对外宣称“重试语义已硬闭环”或“验收自动化完全闭环”。

本报告仅支持 `air_spare.slx` 代理平台上的仿真结论，不支持真实八旋翼节能、偏航安全、SITL/HITL、实机或飞控部署结论。

## 2. 验收对象与来源绑定

| 项目 | 值 |
|---|---|
| 分支 | `main` |
| 开始验收时 HEAD | `798f60e77804e51ad7210a91ed5e9ed389cb4f79` |
| 同步状态 | 本地 `main` = `origin/main` = `fork/main` |
| 相对第七轮报告 | `35436ec` 验证器修复 + `fd4ce7c` 规则 v1.4 + `798f60e` 修复证据/状态文档 |
| 主要代码变更 | `models/px4_x8/verify_m2_round4_closure.m` |
| 验证器 SHA-256 | `d7191c16aa7a2f8e6e5e409202c8a3dbb4afdcfce3bb451de8377e6a6224185e` |
| MATLAB | R2022b，Windows，`-batch`，每段独立进程 |
| 模型/证据等级 | `air_spare.slx` / proxy（未标定估算功率） |

本轮开始时工作树干净；验收运行仅在 `.gitignore` 覆盖的 `results/` 中生成运行证据。

## 3. 实际执行结果

### 3.1 治理与静态检查

| 检查 | 结果 |
|---|---|
| PowerShell 7 `tools/check_repo_governance.ps1` | PASS（12 模块 / 24 Markdown） |
| Windows PowerShell 5.1 同一治理脚本 | PASS（12 模块 / 24 Markdown） |
| `git diff --check bb3097a..798f60e` | PASS |
| 仓库内可执行重试批次驱动 | **未找到**；修复报告仅引用仓库外 `Temp/run_r7_batch.sh` |

### 3.2 MATLAB 当前提交整批复跑

| 阶段 | 实际行数 | attempt | 结果 |
|---|---:|---:|---|
| `init` | manifest | — | PASS |
| `c1c2stale` | 6 | 1 | PASS |
| `c2clean` | 3 | 1 | PASS |
| `c3` | 2 | 1 | PASS |
| `c5` | 4 | 1 | PASS |
| `contract` | 27 | 1 | PASS |
| `report` | **42/42** | 五段均为 1 | PASS |

| 聚合项 | 值 |
|---|---|
| runId | `6ade3744-ef6b-449c-9c78-afe81c42fd67` |
| 绑定提交 | `798f60e77804e51ad7210a91ed5e9ed389cb4f79` |
| 正式归档 | `results/round4_closure/20260902_210055/` |
| 矩阵 | 42 行，42 PASS，0 non-PASS，1 个 runId |
| C5 链 1 | `results/air_m2_trials/20260902_205503/` |
| C5 链 2 | `results/air_m2_trials/20260902_205658/` |
| 两链 `summary.csv` SHA-256 | `D5FC25BF9C067DAC1620D62416EDB6235D7725B720C6E5C4B8BC2A764ED6F197`（一致） |

本轮未出现原生堆崩溃，因此当前正式批次只直接证明“首次尝试完成”，不能替代真实崩溃后驱动层自动重试的正向证据。

## 4. 数值门槛与裕量

| 名义场景 | `delta_E_pct` | 对 `+0.5%` 门槛裕量 |
|---|---:|---:|
| S1 | `-0.262619%` | `0.762619 pp` |
| S2 | `-0.293804%` | `0.793804 pp` |
| S3 | `-0.214654%` | `0.714654 pp` |

最小裕量为 `0.714654 pp`，约为登记复现抖动 `±0.015 pp` 的 47.6 倍，不属于骑线 PASS。本轮数值与第六/七轮登记值及 C5 双链哈希一致。

## 5. attempt 诚实记账负向探针

探针在 42/42 正式归档完成后执行，仅临时修改 `.gitignore` 下的 `c5.done.mat`：

1. 备份原始 `c5.done.mat`（原始 `done.attempts=1`）；
2. 将 `done.attempts` 改为 4，超过规则 v1.4 声明的最多 3 次，同时 `<stage>.attempts` 文本标记仍为 1；
3. 运行 `verify_m2_round4_closure('report')`；
4. 聚合器打印 `c5=4`，但仍输出 `ROUND-4/5/6 CLOSURE VERIFICATION PASS (42 checks)` 和 `ROUND8_ATTEMPT_TAMPER_ACCEPTED=1`；
5. 探针结束后恢复原始 `c5.done.mat`，删除伪造聚合归档 `results/round4_closure/20260902_210229/`；正式归档 `20260902_210055/` 未受影响。

这一探针证明：当前 `validateStaged` 只校验 runId/提交/验证器哈希和 CSV verdict，`writeAggregate` 仅读取/打印 attempt，未将 attempt 合法性纳入最终 PASS 条件。

## 6. 发现与修复要求

### R8-F1（P1）：聚合器接受不合法/不一致的 attempt 证据

**证据：** 上述负向探针将 `c5.done.attempts=4`、`c5.attempts=1`，仍聚合 PASS。代码中 `validateStaged` 未检查 `done.attempts`；`writeAggregate` 对缺少该字段的 done 还会默认为 1。

**影响：** `result.mat` 中的 `stageAttempts` 不是经硬断言的证据，“有界”与“诚实记账”不能由当前 report 自证。

**必须修复：**

- `validateStaged` 必须要求 `done.attempts` 存在，且为有限正整数；
- 必须硬断言 `1 <= done.attempts <= manifest.maxAttempts`，上限由 manifest/版本化驱动生成，不可只写在文档或临时脚本中；
- 必须独立读取 `<stage>.attempts` 并硬断言与 `done.attempts` 一致；
- 新增“缺字段 / 0 / NaN / 非整数 / 超上限 / marker 不一致”负向矩阵，所有 case 必须被 report 拒绝。

### R8-F2（P1）：有界重试驱动不在仓库中，无法独立复现规则 v1.4 语义

**证据：** 仓库内只有分段验证器与计数器，没有实现“进程非零退出 + 无 done 才重试 + 最多 3 次 + 保留每次日志”的可版本化入口。修复报告指向的 `Temp/run_r7_batch.sh` 不在仓库中。

**影响：** 普通协作者从仓库只能手动调用各 stage，无法复现或审计驱动层的有界重试判断；当前修复并未形成完整的仓库级自动化交付。

**必须修复：** 提交一个 Windows/MATLAB R2022b 可直接运行的批次入口（例如 PowerShell 驱动），把阶段列表、最大尝试数、done 判断、退出码处理和日志归档纳入版本控制；增加“无 done 崩溃会重试”、“已有 done 的退出崩溃不重试”、“确定性失败到上限必须失败”三类驱动层测试。

### R8-F3（P2）：attempt 计数器写入不是原子替换

**证据：** `bumpAttempts` 直接以 `fopen(f, 'w')` 截断正式标记，再 `fprintf`/`fclose`。

**影响：** 若原生崩溃恰好发生在截断后、完整写入前，下一次完整重执行会因 `BadAttempts` 中止，与该修复专门处理的“任意窗口原生崩溃”存在缝隙。

**建议修复：** 写入同目录临时文件、`fclose` 成功后以原子替换更新正式标记，并用可控钩子覆盖“写前/写中/替换后”三个退出窗口。

### R8-D1（文档，本报告同步修订）：唯一状态文档内部冲突

`docs/DEVELOPMENT_STATUS.md` 前部仍保留“第六轮、聚合缺口、PARTIAL”的旧总述，后文又写第七轮修复后 42/42。本次以第八轮实测口径同步状态文档，消除该内部冲突。

## 7. 覆盖边界与未覆盖项

- 本轮完整执行了验证器声明的 42 行针对性矩阵，不宣称全部入口状态 × 全部退出路径的笛卡尔积。
- 全量 9 场景同会话双链仍是 R2022b 环境限制下的未覆盖组合；全量场景由 `c3` 单进程覆盖一次。
- 本轮正式批次未发生原生崩溃，所以没有形成“真实崩溃后自动重试并最终成功”的当批正向证据。
- R8-F3 为代码路径审计发现，本轮未在微小写窗口内做非确定性强杀；关闭该项需增加可控写入钩子后实跑。
- 仿真期间持续出现既有未连接端口警告，但旁路基线差异为 0，本轮未将其升级为新功能缺陷。

## 8. 下一轮最小验收清单

1. 修复 R8-F1：将 attempt 字段、范围、marker 一致性纳入 `validateStaged` 硬断言，并增加六类负向 case。
2. 修复 R8-F2：把有界批次驱动纳入仓库，运行驱动层三类退出/重试测试。
3. 修复 R8-F3：attempt 标记原子替换，对三个写入窗口做可控失败注入。
4. 在干净的新 HEAD 上由仓库内驱动重跑整个 42 行批次，报告每段真实 attempt 数、全部尝试日志与数值裕量。
