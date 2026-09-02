# M2 第八轮修复与关闭验证（2026-09-02）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线）

修复执行与主要撰写：ZCode（AI 协助）

独立验收（修复对象报告）：Codex（`M2_REACCEPT_ROUND8_CODEX_20260902.md`）

审核：待项目组审核、待指导教师确认

## 1. 结论

**第八轮发现 R8-F1/R8-F2/R8-F3 已全部修复并关闭。当前提交 `6f6672c` 上由入库驱动 `tools/run_m2_batch.ps1` 整批复跑：48/48 PASS（42 行原有矩阵 + 6 行新增 attempt 负向证明），runId `72300de6-c0d5-474d-bedb-a08ec63b8103`，五段尝试数 c1c2stale/c2clean/c3/c5/contract = 1/1/1/2/1。**

其中 **c5 的第 1 次尝试是被受控注入的 `taskkill` 进程击杀**（对 R2022b 原生崩溃的既定等价代理，见第七轮修复报告论证）：驱动自动按"无新鲜完成证据"判定并完整重执行，第 2 次尝试完成双链、哈希与登记值一致，`done.attempts=2` 如实入账。这补上了第八轮报告 §7 指出缺失的"真实崩溃后自动重试并最终成功"的**正式批次内**动态证据。

修复期间还捕获两次**真实** R2022b 堆损坏（非注入）：一次在第八轮 Codex 批次（c3 盖章后，无害）；一次在本轮第一次正式批次 `results/batch_runs/20260902_225209`——c2clean 中途死于 `0xc0000374`，而 matlab 启动器向 PowerShell 报告**退出码 0**。该活例直接推翻"非零退出才重试"的判据，驱动已改为**以新鲜完成证据为权威判据、退出码仅参考**（规则 v1.5 同日修正）。环境缺陷本身未消灭，本报告只主张受控韧性。

M2 功能与代理数值结论继续放行；本报告仅支持 `air_spare.slx` 代理平台，不支持真实八旋翼节能、偏航安全、SITL/HITL 或实机结论。

## 2. 修复内容与提交

| 发现 | 修复 | 提交 |
|---|---|---|
| R8-F1（P1）聚合器接受不合法/不一致 attempt 证据 | `validateStaged` 硬断言：`done.attempts` 必须存在、为有限正整数、`1 <= a <= manifest.maxAttempts`、与 `<stage>.attempts` 持久标记完全一致；manifest 由 init 写入版本化上限 `maxAttempts=3`；`writeAggregate` 删除"缺字段默认 1"路径改为硬断言并把 `maxAttempts` 一并入 result.mat；contract 负向矩阵新增 6 行（attmissing/attzero/attnan/attfrac/attover/attmix），矩阵 42→48 行 | `fea8a33` |
| R8-F3（P2）计数器写入非原子 | `bumpAttempts` 改为同目录临时文件 + `movefile` 原子替换；超预算入口在写入前拒绝（`air:M2Verify:AttemptBudget`，标记不被污染）；`M2_ATTEMPT_WRITE_HOOK=pre/mid/post` 三窗口受控死亡钩子（缺省休眠）；损坏（空/非数值）标记仍硬失败 `BadAttempts` 不自动重建 | `fea8a33` |
| R8-F2（P1）重试驱动不在仓库 | `tools/run_m2_batch.ps1`：逐段独立 MATLAB 进程、逐尝试日志 `results/batch_runs/<ts>/<stage>.attempt<N>.log>`、有界重试、满额中止并保留日志；`tools/test_m2_batch_driver.ps1` 驱动层测试（初版 6 场景） | `bda0309` |
| R8-F2 续（活例驱动修正） | 驱动判据改为**新鲜完成证据权威**：done 文件（或 report 的新归档目录）时间戳晚于该次尝试开始才算数；rc=0 无新鲜证据同样按可重试失败处理（225209 活例：堆崩溃子进程的启动器报 rc=0）；report 以 `results/round4_closure` 下新目录为证据标记，防假绿；测试扩至 8 场景（新增 S6 rc=0 无 done 满额中止、S7 归档目录证据） | `6f6672c` |
| 规则 | v1.5：(a) 新鲜证据判据+退出码仅参考（同日修正）；(c) 上限固化于 manifest 并与驱动缺省一致、验证器入口独立拒绝超预算；(f) attempt 硬断言+六类负向证明；(g) 原子替换+损坏不自愈；(h) 驱动入库+驱动层测试前置；§6 自检清单同步 | `19a86f5`、`6f6672c` |

checkcode：修改后 9 条提示全部为既有已接受的全局变量类提示，无新增。

## 3. 驱动层测试与无仿真探针（全部实际执行）

| 编号 | 内容 | 结果 |
|---|---|---|
| 驱动 T1–T8 | `tools/test_m2_batch_driver.ps1` 于 Windows PowerShell 5.1：S1 无 done 崩溃重试至第 2 次成功并留双日志；S2 新鲜 done 后崩溃不重试；S3 确定性失败满 3 次中止留 3 日志；S4 无 done 阶段 rc 语义；S5 陈旧 done 不掩盖崩溃（时间戳判据）；S6 **rc=0 无 done 满额中止**（225209 活例场景）；S7 report 式新归档目录证据 + 归档后崩溃无害 | 8/8 PASS（rc=0） |
| 探针 A | report 对篡改 attempt 证据的拒绝（init 后仅伪造第一阶段工件，进程内逐例调用）：缺字段 / 0 / NaN / 1.5 / 4（=max+1）/ stamp=2 vs marker=1 / 删除 marker / 正向对照（合法 stamp 通过第一阶段检查、在 c2clean 缺 csv 处失败） | 8/8 按预期拒绝，**全程未写出任何归档**（目录数前后一致）；Codex 第八轮探针场景（done.attempts=4）现被硬拒绝 |
| 探针 B1/B4 | `M2_ATTEMPT_WRITE_HOOK=pre` / `mid` 独立进程死亡模拟 ×2 轮（标记 1→2→3） | pre：标记保持旧值、无 tmp；mid：标记保持旧值、tmp 含新值——**写窗口崩溃至多留下旧值或新值** |
| 探针 B3/B5 | `post`（原子替换后死亡）×2 | 标记已为新值、tmp 已消失；后续入口读取的正是替换后值（连续性） |
| 探针 B6 | 标记=3 再入（预算拒绝） | `air:M2Verify:AttemptBudget`，**写入前拒绝**，标记保持 3、无 tmp |
| 探针 B7 | 空标记再入 | `air:M2Verify:BadAttempts` 硬失败，空标记不被自愈 |
| 探针 D1/D2 | 入库驱动 × 真实 MATLAB：D1 `-Stages init` 正跑；D2 `-Stages report` 确定性失败 3 次满额中止 | D1 rc=0；D2 rc=1，3 份日志保留（`results/batch_runs/20260902_225048`） |
| rc 捕获验证 | PowerShell 5.1 内 `matlab -batch` 成功/断言失败退出码 | 0 / 1，捕获正确 |

说明：第八轮 Codex 报告记有 "PowerShell 7 治理 PASS"，但本机当前 PATH 与常见安装位置均未找到 pwsh（已用脚本核查）；驱动与测试按 PowerShell 5.1 兼容语法编写并在 5.1 实跑通过，此差异如实登记，不宣称双壳复验。

## 4. 正式批次（入库驱动整批，`results/batch_runs/20260902_230612`）

| 项 | 值 |
|---|---|
| runId | `72300de6-c0d5-474d-bedb-a08ec63b8103` |
| 绑定提交 / 验证器 SHA-256 | `6f6672cb2be8f5b1203e91fb6f5dd86486f5f6f1` / `ba40a134fcb782bde6e6d71059dd7118b096922cc1e5b8f33a794d76c214a40e` |
| 阶段结果 | init、c1c2stale(6)、c2clean(3)、c3(2)、contract(33) 均 attempt 1；**c5(4) attempt 2**；report 一次通过 |
| 聚合 | 48 行 48 PASS 0 non-PASS 单一 runId；`attempt bound: manifest.maxAttempts=3`；`stage attempts: c1c2stale=1, c2clean=1, c3=1, c5=2, contract=1`；result.mat 含 stageAttempts 与 maxAttempts |
| 归档 | `results/round4_closure/20260902_232513/` |
| c5 击杀记录 | 第 1 次尝试入口 23:16:00；23:17:30 `taskkill //F //T` 终止 matlab.exe(15580)/MATLAB.exe(14928) 进程树；该次日志 `c5.attempt1.log` 截止于链中仿真（power_rec 打印后、无盖章），部分链归档 `air_m2_trials/20260902_231148` 按时间戳留存不可复用；驱动判定 `attempt 1 rc=0, no fresh evidence marker -> full re-execution`（启动器对被杀子进程报 rc=0，与 225209 真实堆崩溃同型）；第 2 次尝试双链 `20260902_231851`/`20260902_232108` |
| 双链 `summary.csv` SHA-256 | 两链均 `d5fc25bf9c067dac1620d62416edb6235d7725b720c6e5c4b8bc2a764ed6f197`，与第六/七/八轮登记值一致（跨批次第 5 次复现） |
| 数值门槛（nominal S1–S3） | `delta_E_pct` = −0.26262% / −0.29380% / −0.21465%（登记精确值 −0.262619/−0.293804/−0.214654），对 +0.5% 门槛裕量 0.76262 / 0.79380 / 0.71465 pp，最小裕量 ≈ 47.6× 登记抖动 ±0.015 pp，非骑线 |

第八轮报告 §8 最小验收清单逐条对照：(1) attempt 硬断言 + 六类负向 case ✓（探针 A + 矩阵 6 行）；(2) 驱动入库 + 驱动层测试 ✓（8 场景，超出要求的三类）；(3) 原子替换 + 三窗口注入 ✓（探针 B）；(4) 干净新 HEAD 由仓库内驱动重跑整批、报告每段真实 attempt 数、全部尝试日志与数值裕量 ✓（本节）。

## 5. 覆盖边界与未覆盖项

- 48 行为**针对性矩阵**口径（R8 缺陷类别相关的全部组合），不宣称全部入口状态 × 全部出口的笛卡尔积；全量 9 场景同会话双链仍为 R2022b 环境限制下的未覆盖组合（全量场景由 c3 单进程覆盖一次）。
- 正式批次内的"崩溃后重试"证据来自 `taskkill` 注入代理（R2022b 原生崩溃对计数器语义等价，第七轮已论证：标记在段入口先于任何仿真落盘）；**自然发生**的崩溃-重试-成功当批组合本轮未出现（225209 的真实崩溃发生在旧判据下，批次保守中止，未形成重试）。
- 环境缺陷（R2022b 堆损坏、启动器退出码不可靠）未消灭，本轮新增两个真实样本（第八轮 c3 盖章后崩溃；225209 c2clean 中途崩溃且启动器报 0）。
- report 的"新归档目录"证据判据由驱动测试 S7 mock 验证 + 本批实跑 rc=0 路径一致；未在 report 阶段做真实进程击杀注入。
- pwsh 7 本机不可用（见 §3 说明），驱动测试单壳（WinPS 5.1）实跑。
- 所有能量百分比仍为未校准模型的代理估算口径。

## 6. 如实记录（过程性事实）

- 第一次正式批次（`results/batch_runs/20260902_225209`，绑定 `19a86f5`）在 c2clean 真实堆崩溃 + 启动器 rc=0 下被旧判据（rc=0 无 done → 硬停）中止：该防线正确拒绝了假成功，但也暴露判据缺陷，随即修正驱动与规则（`6f6672c`）并整批重跑。中止批次的日志与该次 c2clean 崩溃日志完整保留，作为活例证据；其 staged 证据被 230612 批次 re-init 取代（单提交绑定原则）。
- 驱动测试初版 6 场景（含"rc=0 无 done → 抛错硬停"的 S6），随判据修正翻转为"rc=0 无 done → 重试满额中止"并扩至 8 场景，两版测试输出均如实留档。
- 探针 A 中"归档目录数不变"的机器核对使用 MATLAB `dir` 计数（含 `.`/`..`，15）与 bash `ls` 计数（13）口径不同，前后一致性结论不受影响。
- 第八轮 Codex 的 staged 证据在 re-init 前已备份至 `results/round8_codex_staged_backup/`。
- 击杀监视器一度误以 bash `$!`（matlab 启动器）之外的系统子进程为候选；实际按 Win32_Process 命令行过滤定位 `verify_m2_round4_closure('c5')` 的进程树后终止，一个无命令行的系统级子进程（PID 5908）拒绝访问、未受影响。

## 7. 状态措辞

M2 受约束分配器、ESC 接线与修订数值协议保持放行；第八轮发现（R8-F1/R8-F2/R8-F3）已修复并按本报告关闭。验收自动化在**针对性矩阵 + 入库有界重试驱动**口径下成立：attempt 证据为硬断言对象、驱动语义有版本化测试与正式批次内重试实绩；不宣称"验收自动化完全闭环""永不崩溃"或全量矩阵覆盖。M3 方案与实现可继续；不做平台侧 RL。
