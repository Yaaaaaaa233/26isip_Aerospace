# M2 第六轮发现修复报告（2026-09-02）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线，延续现有责任记录）

主要撰写：ZCode（修复方案、实现与关闭验证代拟）

技术贡献：ZCode（R6-F1/F2/F3 修复、治理脚本兼容性收口、42 行针对性矩阵执行）

审核：待项目组审核、待指导教师确认

AI协助：ZCode（修复实现、分段批次执行与本文档代拟）

## 1. 结论

本报告关闭第六轮独立验收报告（`M2_REACCEPT_ROUND6_CODEX_20260902.md`）的 R6-F1/R6-F2/R6-F3，并按其 §8 关闭条件重跑正式分段批次。

- **R6-F1（源码指纹自引用）**：已修复——`verify_m2_round4_closure` 新增 `srcFingerprint()`，在 init、每段开始、每段盖章与 report 四类取证点**独立现场重取** HEAD / 验证器 SHA-256 / 脏树状态；删除 `'unknown'` 占位（git 取证失败即硬失败）；脏树（含未跟踪文件）硬拒绝；git 命令显式 `-C <repoRoot>`，不依赖进程工作目录；每段 `done.mat` 盖自己的现场指纹，聚合器逐段比对 manifest。
- **R6-F2（聚合 verdict 未硬断言）**：已修复——`validateStaged` 对每份 stage CSV 的**每一行 verdict 硬断言为 PASS**；FAIL 行篡改负向证明（`failrow`）实际执行；聚合总数由 manifest 的 declaredRows 动态求和，删除硬编码 39。
- **R6-F3（C5 全量双链环境阻塞）**：按报告建议路径 1 收缩为**最小双链**——`run_air_m2_trials` 新增 `scenarioSet='nominal'`（E2_fixed + S1/S2/S3_esc，4 次仿真/链），`run_m2_session_chain` 透传；C5 双链改用最小集。C5 的三个目的（脏会话复用、同会话 CSV 哈希一致、S1/S2/S3 门槛值对照登记值）完整保留；全量 9 场景链由 c2clean/c3 每进程一次覆盖；**全量双链为环境限制下未覆盖组合**（见 §5 边界）。
- 关闭条件 3（R5-F3 缺路径负向重跑）随 contract 段在本批次内重跑；条件 4（同会话双链 2/2）由最小双链达成；条件 5（正式 39/39 重跑口径）按 42 行新矩阵执行；条件 6（状态口径）见 §7。
- 附带收口：`tools/check_repo_governance.ps1` 加 UTF-8 BOM，Windows PowerShell 5.1 按文档口径可运行（Codex 第六轮 worklog 登记的工具兼容性问题）。

## 2. 修复明细与位置

| 发现 | 修复 | 位置 |
|---|---|---|
| R6-F1 | `srcFingerprint()`：独立取证 + `-C repoRoot` + 拒 unknown | `verify_m2_round4_closure.m`（局部函数） |
| R6-F1 | `assertSourceBound()`：段开始/盖章/report 三处现场比对 manifest（HEAD、SHA、clean） | 同上 |
| R6-F1 | `makeManifest()`：init 即记录 clean 要求与三元指纹；每段 done.mat 盖自身指纹 | 同上 |
| R6-F2 | `validateStaged()`：`all(T.verdict == "PASS")` 硬断言 + `verifierSha` 逐段比对 | 同上 |
| R6-F2 | `writeAggregate()`：行数由 declaredRows 求和，去硬编码 | 同上 |
| R6-F3 | `run_air_m2_trials(injectError, scenarioSet)`：'nominal' 最小集，门槛不变 | `run_air_m2_trials.m` |
| R6-F3 | `run_m2_session_chain(injectError, trialsMode)` 透传 | `run_m2_session_chain.m` |
| 负向 | `failrow`（FAIL 行）/`shamix`（done SHA 篡改）玩具副本 + 脏树现场负向（未跟踪 `.txt`；`*.tmp` 被 gitignore 不可见，已改用 `.txt`） | `runContract` |

规则文档同步升版 **v1.3**（`ACCEPTANCE_AUTOMATION_RULES.md`）：§2.5 指纹独立取证、§2.6 verdict 硬断言、§4.4 最小充分集收缩的三处口径同步义务，§6 自检清单同步。

## 3. 针对性矩阵（42 行，声明 = 执行）

分段执行（每段独立 MATLAB 进程，R2022b；同批次 manifest 绑定）：

| 段 | 行数 | case 清单 |
|---|---:|---|
| c1c2stale | 6 | 单元错误出口 × {clean, stale 哨兵}（stale 含 persistent-fresh 直探行）；链 compare/injection/trials 错误出口 × stale |
| c2clean | 3 | 链 compare/injection/trials 错误出口 × clean |
| c3 | 2 | 独立试验：受控失败；全量成功（stale 入口） |
| c5 | 4 | 脏会话背靠背**最小双链** 2/2（nominal S1–S3）；同会话 summary.csv 哈希一致 h1==h2；S1/S2/S3 门槛 dE 在登记值 ±0.015 pp 内 |
| contract | 27 | 四入口（unit/trials/chain/verifier）× 四态 {finite, empty, NaNval, Infval} 的状态契约（20 行，成功与错误出口）；archive 断言负向（R5-F3 重跑）；玩具副本负向 ×5 {oldbatch, missing, mixed, failrow, shamix}；脏树现场负向（未跟踪文件阻断 stage） |

## 4. 关闭验证结果

正式分段批次（2026-09-02，R2022b，每段独立 MATLAB 进程，单提交干净树）：

| 段 | 完成 | 结果 |
|---|---:|---|
| init | 17:21:54 | runId `ff8636ec-e2c4-4181-9e71-7334a6d7130e`，HEAD `2d36288fde8d91ea14088749806a25e6d38f6cdd`，验证器 SHA-256 `cbf098aa…8683a0a`，tree=clean |
| c1c2stale | 17:24:04 | 6/6 PASS |
| c2clean | 17:26:14 | 3/3 PASS |
| c3 | 17:26:33→17:46:33 | 2/2 PASS（含一次全量 9 场景独立试验） |
| c5 | 17:51:34 | 4/4 PASS（最小双链 2/2） |
| contract | 17:53:03 | 27/27 PASS（含 failrow/shamix/脏树三类新负向） |
| report | 17:53:19 | 聚合 **42/42 PASS**，归档 `results/round4_closure/20260902_175314/`（gitignored） |

- 同会话双链（最小集）`summary.csv` SHA-256 逐字节一致：`d5fc25bf9c067dac1620d62416edb6235d7725b720c6e5c4b8bc2a764ed6f197`（h1==h2）。
- 门槛值（chain-2 `pairs.csv`，`[90,120] s`）：S1 −0.262619%、S2 −0.293804%、S3 −0.214654%；相对登记第三/四轮值最大变化 0.01152 pp（S3），在 ±0.015 pp 已知抖动内；相对 +0.5% 门槛最小裕量 0.714654 pp（≥47×抖动），非骑线。
- 第六轮关闭条件对照：1（指纹独立取证+拒 unknown/dirty/不一致）✓；2（verdict 硬断言+FAIL 行负向）✓；3（R5-F3 缺路径负向随 contract 重跑）✓；4（同会话双链 2/2，最小集口径）✓；5（正式矩阵重跑 42/42，抖动与裕量口径保持）✓；6（状态口径，见 §7 与状态文档同步）✓。

## 5. 覆盖边界与已知限制（措辞对齐 §4）

- **未覆盖组合**：全量 9 场景同会话双链（R6-F3 环境限制：R2022b 单进程长序列堆损坏，第六轮两次在第二条全量链中途退出）；登记为待环境修复（MATLAB 升级/换机）后补跑项。最小双链覆盖确定性证明所需全部要素，全量链场景由 c2clean/c3 单进程各覆盖一次。
- nominal 最小集不含 E1/E3 表面行、扰动对与 R_esc 组内复现行（属全量协议，c2clean/c3 覆盖）；矩阵行标签已注明 "nominal S1–S3"。
- report 阶段为本批次提交专用：批次提交之后 HEAD 前进时重跑 report 会按 R6-F1 语义拒绝（证据绑定生成它的提交），需整批重跑——这是同批次绑定的预期行为，不是缺陷。
- 能量百分比均为未校准 `estimated` 口径；`air.slx` 与 M2 数值协议/门槛未做任何改动。

## 6. 执行记录（诚实口径）

- 修复过程中自检抓出并在提交前修正的实现缺陷：(a) git 取证依赖进程工作目录（从仓库外驱动时报 `SourceFingerprint` 而非目标门错误）→ 改 `git -C repoRoot`；(b) trials 短路返回缺 `scenarioSet` 字段；(c) 脏树负向探针初版用 `.tmp` 后缀——被 `.gitignore` 的 `*.tmp` 规则吞掉、porcelain 不可见，改 `.txt`；(d) `writeAggregate` 声明返回值未赋值（checkcode 抓出）。
- 无仿真快速探针 5/5 通过后代码入库（`0810d6c`），正式批次在干净树、单提交 `2d36288`（含 `59bdf06`/`deed6e4`）下执行，42/42 PASS。
- 第二次批次六个 stage 全部完成、42 行证据齐备，report 段抓出声明行数求和缺陷（`structfun(@nnz)` 数的是段数 5 而非行数 42）；修正提交 `2d36288` 后按单提交绑定语义整批重跑（旧批次证据因验证器 SHA 变更而失效，属 R6-F1 绑定的既定代价）。

## 7. 状态口径

M2 核心实现与数值协议保持放行；第六轮三项发现（R6-F1/F2/F3）已关闭并经 42/42 针对性矩阵复验（runId `ff8636ec` @ `2d36288`）；C5 为最小双链口径，全量同会话双链仍为环境限制下未覆盖组合，"验收自动化完全闭环"不宣称。下一步 M3（速度与转速比交替协同优化）方案文档先行。
