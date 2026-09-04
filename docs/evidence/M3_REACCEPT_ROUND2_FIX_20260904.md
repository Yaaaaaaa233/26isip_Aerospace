# M3 第二轮修复与关闭验证（独立验收第一轮发现 F1–F6）

日期：2026-09-04
报告版本：1.0
项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：叶安（平台线）
主要撰写：叶安（修复范围与关闭判据授权）、ZCode（修复实施与本报告代拟）
技术贡献：叶安（要求按第一轮独立验收报告逐项关闭）；Codex（第一轮独立验收报告，本报告的输入）
审核：待叶安与项目组审核
AI协助：ZCode（全部代码改动、批次执行、负向矩阵与本报告）

## 1. 结论

按第一轮独立验收（[`M3_REACCEPT_CODEX_20260904.md`](M3_REACCEPT_CODEX_20260904.md)）§6 最小修复清单完成 F1–F6，并在**单一冻结提交 `1e3e0e4`** 上完成：五段 14 场景批次（全部 attempt=1）、`m3_aggregate_batch` 总聚合 PASS、8/8 聚合篡改负向精确拒收、生产路径负向 6 例 + 正控、恢复矩阵 11 行、边界重跑、M0-A/M0-B 回归与三套单测（含新增 B7 负向组）。

| 判定层 | 本轮结论 | 边界 |
|---|---|---|
| 功能实现 | 机制证据保留并按新合同整批复跑 PASS（数值与 2026-09-03 批次逐位一致） | 代理对象机制（R4 前置），非 Plane 终验；能耗为未校准模型估算口径 |
| 验收基础设施 | **按第二轮冻结合同重建并复验**：逐臂冻结配置断言、单一评价路径、执行检查器接入正式链、manifest 绑定总聚合、注入错误恢复矩阵 | 针对性矩阵（逐行列明，见 §4），非全笛卡尔覆盖；M3 无跨进程重试驱动（每段即一次性时间戳归档，attempt 如实记账） |
| 环境限制 | OPEN LIMITATION 维持：R2022b 堆崩溃（本轮实施期间发生 2 次段中断，见 §5）| 不宣称消除；受控重试=从段入口完整重执行 |
| 文档证据 | 接口勘误块、规则 §7 注册表、状态页、路线图同步（本报告 §6） | 历史报告原样保留，勘误以本报告与本轮文档改动为准 |

## 2. F1–F6 修复对照

| 编号 | 修复 | 位置 |
|---|---|---|
| F1 | eta 参数集按臂分列：`peM3`(2e-4)/`peM2`(1e-4) 按模式选择；`assertFrozenConfig` 字面冻结表（模式/增益/幅度/速率/仲裁逐臂断言；段运行校验在场臂，full 运行另要求 14 臂齐全）；`cfgmismatch` 钩子翻转首臂增益必须被拒（R2-M cfgmismatch 行）；第 44 行过期注释修正；边界入口显式声明 1e-4 机制探针口径并归档 `effective_config.mat` | `run_air_m3_trials.m`、`run_air_m3_boundary.m` |
| F2 | `m3_eval_convergence` 参考点修正为 `abs(pe − 1.0)`（原 `abs(pe)` 距 0，方向反转）；正式路径改为调用该唯一评价器（窗口 [192,240)，附槽起点断言）；**monotonic 进入 r.ok 硬判**（名义 m3 臂）；B2 连续搜索臂以同一判据窗为掩码、同评价器同窗口评分 | `m3_eval_convergence.m`、`m3_eval_arm.m` |
| F3 | `m3_check_execution` 新增：有限性硬检查（NaN 前置拒绝）、搜索参与度（每搜索段 dither 量程 ≥ 0.5×幅度，名义臂硬判、扰动臂记录）、`vViaApplied`（v 候选无日志的 V1 登记限制：hold 经施加值 + 限速过渡余量判恒定）、`etaAppliedIsActual`（el 第 2 列为物理实际比值：改查跟踪界 t≥10 s 内 \|实际−候选\| ≤ 0.5×幅度；实测最大步长 0.799 出现在桨叶起转，证实非限速参考）、`vHoldMask`（v 施加通道仅监督正常样本参与 hold 恒定判：status==2 ∧ 硬位静默；实测 mask+3 样本余量下偏差 0）；`m3_eval_arm` 接入 checker 为正式判定路径；全臂（名义+扰动）位 1/2 连续置位 ≤ 2 s 硬门；sat 连续时长报告 | `m3_check_execution.m`、`m3_eval_arm.m` |
| F4 | `m3_source_binding`（runId/现场 git HEAD/脏树状态/入口与模型与适配器 SHA-256；证据运行脏树硬拒，钩子模式豁免并声明）；result.mat 携带绑定与 scenarioScope；`m3_aggregate_batch` 总聚合：现场取证+段间同提交、源码级 14 臂合同（缺/重/多臂硬拒）、**段结果 verdict 行全 PASS 硬断言**（FAIL 行不得聚合）、逐臂档案在场、R1/N5 必须同段同 runId 且等网格、全部配对门从逐臂档案重算；R1 缺席=段失败（不再静默跳过）、长度不等硬断言（不再 min 截断）；vTrk 四个同 v0 对全部登记；`savefail`/`postwrite` 写入后失败钩子（受控注入 `air:*:Injected*` 直接 rethrow，逃离逐臂降级路径） | `m3_source_binding.m`（新）、`m3_aggregate_batch.m`（新）、两入口 |
| F5 | `m3_eval_energy` 双轨字段（nWin/covA/covB/maskFrac/dEPctFull/EAfull/EBfull）；入口与聚合双行打印（掩码口径为主门槛——冻结口径不变，全窗与覆盖率如实并列） | `m3_eval_energy.m`、入口、聚合 |
| F6 | 文档同步：接口 v0.2 勘误块（窗口统一/14 场景/基线 6 行/warmup 语义/边界口径/双轨能量）、规则 §7 注册表 M3 行补全、状态页与路线图（含 M2 第六轮旧状态段更新、M3 未完成清单纠正） | 本报告 §6 所列文件 |

## 3. 实施中发现并修复的次生缺陷（全部如实登记）

1. `assertFrozenConfig` 首版要求 14 臂全在场，破坏子集段运行（被 R2-M savefail 行抓到：期望 InjectedSaveFail 得到 ConfigDrift）→ 改为在场臂逐一校验 + full 才要求齐全。
2. 受控注入被逐臂 try/catch 吞掉转为 pass=false 正常返回（savefail 行第二次暴露）→ `air:*:Injected*` 标识直接 rethrow；错误出口恢复证据由此才真实成立。
3. 多臂段 result 含内嵌日志超 MAT v7 2GB 上限，**MATLAB 静默跳过保存**（归档仅 128 字节空壳，段自检 "TRIALS PASS" 但聚合无档）→ 段结果与逐臂日志分离存储。
4. `struct()` 名值对传入 cell（scenarioSet）未包裹 `{}`，多臂段 result 被复制为 **1×N struct 数组**（`whos -file` 实证 [1 6]）——该缺陷同时解释了当日早前驱动行 `~`/`assert`/`fieldnames` 系列怪错的共同根因；单臂子集因 1×1 cell 被自动解包而幸免。
5. checker 首版对真实通道语义两处误设（第一段真实数据暴露）：el 第 2 列是物理实际比值（最大步长 0.799，桨叶起转），slew/lag 检查对象错误；v 施加通道在 hold 段受监督覆盖（status≠2 样本合法移动）→ 按实测语义重构（见 F3 行），此前 B5 玩具口径（施加值=限速参考）保留为默认选项，生产显式声明两种 V1 日志限制。
6. `test_m0c_esc_unit`/`test_m2_eta_esc_unit` 为规则 §2.1 登记的遗留脚本入口，不能按函数调用 → 验证器按名执行。
7. 聚合入口三次实施缺陷：旧字段引用残留（`segs(d).result.runs`）、cell 名单用 `==` 比较、verdict 误从逐臂档案而非段结果表读取（被 ArmFailed 篡改负向抓到）+ 验证器篡改案例写死 3 段布局目录索引（5 段布局下 ReproSession 定位错段）。
8. 驱动侧（不入库）：MATLAB `-batch` 命令串对 `~`/断言消息的解析问题与 printf 转义、`run()` 临时切换工作目录、GBK 控制台目录名解析——均以仓库外驱动文件 + 文件系统真值（时间戳目录）规避；已作为操作教训记入 worklog。

## 4. 复验矩阵（逐行列明；针对性矩阵，非全笛卡尔覆盖）

**单测（提交 1e3e0e4）**：`test_m3_coordination_unit` B1–B7（B7 新增：收敛方向×2、死对参与度、NaN、vViaApplied 斜坡/漂移、能量覆盖率）、`test_m0c_esc_unit`、`test_m2_eta_esc_unit`——STAGE unit PASS。

**生产路径负向（m3_eval_arm 直驱，验证器 negative 阶段）**：
| Case | 注入 | 期望 | 结果 |
|---|---|---|---|
| R2-P0 | 合成良构臂 | ok=1 正控 | PASS |
| R2-N5 | eta 候选恒 1.0（停搜伪收敛） | searchParticipationE 拒收 | 拒收 |
| R2-N6 | 周期均值 1.000/1.009 交替（均值达标、回退 0.009 > 5e-3） | monotonic 硬判拒收 | 拒收 |
| R2-N7 | 位 1 连续置位 [210,214)（4 s > 2 s，扰动臂） | hard12OK 拒收 | 拒收 |
| R2-N4 | eta 候选 NaN 段 | nonFiniteE 拒收 | 拒收 |
| R2-N8 | v 施加值 hold 段内漂移 | holdConstancyV 拒收 | 拒收 |

**恢复矩阵（调用者全局四态 × 出口，11 行）**：finite/empty/NaN/Inf × pre-write 返回（trials 钩子）；finite/NaN × cfgmismatch（配置归档后、仿真前错误）；finite × savefail（写入后/存档前）；finite/NaN × postwrite（写入并存档后）；finite × 成功出口（单臂子集段，含 result 归档验证）；边界入口 finite × postwrite。全部逐字段 exactly-as-found（`isequaln`）。未覆盖：empty/Inf × 写入后/成功（边界入口）、聚合入口状态矩阵（不写全局）——登记为未覆盖组合。

**聚合篡改负向（8/8 精确拒收，提交 1e3e0e4）**：SourceMismatch（伪提交）/ DuplicateArm / MissingArm / ExtraArm / ArmFailed（段结果 FAIL 行）/ ArchiveMissing / ReproSession（R1 拆至异 runId 段）/ ReproGrid（R1 档案网格截断）。

**冻结批次（提交 1e3e0e4，全部 attempt=1）**：五段 `20260904_133829/134256/134501/134706/134909` + `m3_aggregate_batch` PASS。关键数值（与 2026-09-03 历史批次逐位一致，确定性复现）：
- 能量（周期公共窗 [144,240]，掩码口径为门槛、全窗并列）：对 B1 四对 −0.277~−0.306%（门槛 +0.5%，覆盖率 5.0%，全窗 −0.291~−0.294%）；对 B2 四对 +0.0032%~−0.0020%（全窗 +0.0044%~−0.0027%）；对 B0 五名义臂 −0.278~−0.294%（覆盖 68.3%）。
- v 跟踪：0.00967–0.00981 m/s vs B1 0.193–0.198（四对全部登记，容差 +0.05）。
- eta 收敛 [192,240)：五名义臂均值 0.99564–1.00860（全部 |均值−1| ≤ 0.01 且单调，最大回退 0.0015 < 5e-3）；B2 两臂 0.99195/1.00902 同窗同判据通过；扰动臂 D1/D2 收敛均值 0.99596/1.00083（如实报告）。
- 复现：M3-R1 vs M3-N5 同段同 runId（`46d8c29c…`），eta/v 逐样本最大差 **0/0**。
- 执行证据：全部 14 臂 chk.pass=1（含有限性/恒定/参与度/跟踪界），位 1/2 与 sat 连续时长全部 0.00 s。

**回归**：M0-A 基线对比（air vs air_spare）PASS；M0-B 四位注入 PASS；边界 160 s×2（1e-4 声明口径）PASS。

## 5. attempts 与环境事件（如实）

- 今日堆崩溃 2 次：段运行 20260904_112403（B2-N1 进行中）与 20260904_113928（M3-N4 进行中）——均无 result.mat（无完成证据），按受控重试从段入口完整重执行；最终批次五段全部 attempt=1。
- 中途失败尝试（各段被后续代码修复提交取代，档案保留）：105811（旧提交/完整）、110539（result 空壳前）、112953/114351（1×N result 缺陷档）、115624–125830 各轮（聚合修复前的段档，均 PASS 但绑定旧提交）。全部位于 gitignored `results/`，不构成证据，仅 attempt 记账。
- S2a 在 124128 批次中第 1 次尝试中断（残档 124620，无 result.mat），第 2 次通过；最终批次无此现象。
- 验证器/驱动问题（§3.8）造成的无效尝试不进入段 attempt 计数，已在 §3 如实登记。

## 6. 文档与登记同步（本轮提交内容）

接口 [`M3_V_ETA_COORDINATION.md`](../interfaces/M3_V_ETA_COORDINATION.md) v0.2 勘误块（窗口统一 [192,240)/14 场景与基线 6 行/warmup 语义澄清与 v 适配器不对称的良性论证/边界 1e-4 口径/能量双轨）；[`ACCEPTANCE_AUTOMATION_RULES.md`](../ACCEPTANCE_AUTOMATION_RULES.md) §7 M3 行写者/读者补全（trials/boundary/aggregate/verify）；[`DEVELOPMENT_STATUS.md`](../DEVELOPMENT_STATUS.md) 平台行改为本轮结论；[`PROJECT_EXECUTION_ROADMAP.md`](../PROJECT_EXECUTION_ROADMAP.md) §5 M3 与过期段修正；本报告与 worklog。历史报告（含第一轮验收与 2026-09-03 实现报告）原样保留，其勘误以本报告为准。

## 7. 裕量、未覆盖与边界

- 最小能量裕量（对 B1 掩码口径）≈ 0.78 pp；对 B2 ≈ 0.50 pp；收敛最小裕量 0.0014（距 0.01）与 0.0034（距 0.005 回退容差）。跨进程/跨机器抖动本轮仍未测（M2 先例 ±0.015 pp 仅作参考口径）；同批次内 R1 复现差 0。
- 未覆盖：全部入口状态 × 全部出口的笛卡尔矩阵（本报告为针对性矩阵，逐行列明）；M3 专用跨进程崩溃重试驱动（现有架构以一次性时间戳段+人工受控重试+如实记账运行，未建 ps1 驱动）；Plane 同对象复跑（R4）；V1 登记限制维持（sat 不入 v 在线门、位 5 离线口径、v 候选与 eta 施加参考不落日志，经施加值/物理实际通道取证）。
- 红线维持：零 `.slx` 结构变更；ESC 内核与适配器算法未动（本轮全部改动位于验收入口/评价器/检查器/文档）；能耗全部为未校准模型估算口径。
