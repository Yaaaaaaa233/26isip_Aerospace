# M3 第四轮独立复验报告（F4 有界审计）

日期：2026-09-08
项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：叶安（Control / Simulink 平台线）
主要撰写：待叶安确认（Codex 辅助整理初稿）
技术贡献：叶安（委托按简报执行有界独立复验）
审核：待叶安与项目组审核；本报告为独立技术复验，不代替项目组最终签批
AI 协助：Codex（静态审计、MATLAB/Simulink 实跑、独立副本篡改探针、数值与记账复核、报告整理）

## 1. 结论与冻结对象

**C1–C7 全部 PASS；第三轮报告 §3.1–§3.4 的 F4 四个 P1 缺陷已按 §7 清单关闭，且关闭证据可信。M3 在本轮冻结范围内放行。**

放行边界是 models/px4_x8 链上的 **V1 桌面代理仿真 M3 阶段**：不外推统一 Plane、PX4 SITL/HIL、台架或实飞；Percent 不与 T1/T2 跨模型混比。

- 冻结提交：3eedfa88573a4d72e93b04c3d5f81afd0c757fd6，起跑前与实跑后工作树均干净。
- 验收合同：[本轮复验简报](M3_INDEPENDENT_REACCEPT_BRIEF_20260908.md)、[第三轮独立报告](M3_REACCEPT_ROUND3_CODEX_20260905.md) §7、[验收自动化规则](../ACCEPTANCE_AUTOMATION_RULES.md) v1.8。
- 新鲜正式批次：batchId 8502460f-b92f-4506-b398-44b678c744c9；日志 results/batch_runs/20260908_113715/；staged results/air_m3_batch_staged/20260908_113715/。
- 独立探针有效轮：results/m3_codex_round4_20260908/probe_20260908_122205/，30/30 PASS。所有篡改只发生在该 results 副本；正式 staged、原臂归档和 Git 跟踪文件未被改动。

| 判定层 | 本轮判定 | 边界 |
|---|---|---|
| 功能实现层 | PASS | 正式 14 臂全部 ok=1，配对门、中心、回放、姿态/约束原冻结判据通过 |
| 验收基础设施层 | VALIDATED | C1–C4 原复现、独立负向和既有回归三件套齐备 |
| 环境限制层 | PASS with registered limitation | 正式链无堆崩溃、无重试；受限沙箱内 MATLAB -batch 启动阻塞，非沙箱运行正常 |
| 文档证据层 | PASS within brief | 本报告保留批次身份、attempts、错误 ID、数值、未覆盖项与原始路径 |

## 2. 正式批次与诚实记账

入库驱动命令为：

    powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_m3_batch.ps1 -Matlab "D:/matlab2022b/bin/matlab.exe" -MaxAttempts 3

| 顺序 | 阶段 | attempt | 新鲜证据 | 结果 |
|---:|---|---:|---|---|
| 1 | init | 1 | manifest.mat | PASS |
| 2–6 | s1–s5 | 各 1 | s*.done.mat + s*.attempts=1 | PASS |
| 7 | aggregate | 1 | 20260908_115144_aggregate/ | PASS |
| 8 | vunit | 1 | vunit.done.mat + marker 1 | PASS |
| 9 | vnegative | 1 | vnegative.done.mat + marker 1 | PASS |
| 10 | vaggregate | 1 | vaggregate.done.mat + marker 1 | PASS |
| 11 | vreport | 1 | vreport.done.mat + marker 1 | PASS |

11/11 阶段均为 attempt 1；未出现原生堆崩溃，未触发驱动重试，未重置任何持久计数。tools/test_m3_batch_driver.ps1 独立运行 9 场景全部 PASS，覆盖无 done 重试、新鲜 done 后崩溃不重试、rc=0 但无证据仍不放行、满额中止、新归档目录与 GBK→UTF-8 往返。

审计期间还有两次**未进入 init** 的受限沙箱启动尝试（20260908_111348、20260908_112828）：日志 0 字节，无 manifest、无 attempt marker、无 done，经人工中止。不计为批次 attempt，也不冒充 R2022b 堆崩溃。不加载仓库的最小 disp 在沙箱内同样阻塞，在非沙箱环境约 15 s 正常返回，故归类为工具运行权限边界，不归类为 M3 产品失败。

## 3. C1–C7 逐项判定

| 声明 | 判定 | 独立证据 |
|---|---|---|
| C1 现场 HEAD + 7 指纹 | PASS | 当前 HEAD 副本正控聚合 PASS；manifest commit 改为 40 零精确 air:M3Agg:CrossCommit；aggregate/trials/contract/evalArm/model/m0c/m2 7 字段分别单独置零，7/7 精确 air:M3Agg:ContractMismatch |
| C2 done.attempts 与身份三方绑定 | PASS | 缺字段/0/NaN/1.5/4/与 marker 不一致，6/6 精确 air:M3BatchAgg:StampAttempts；done.runId 与 done.commit 精确 StampIdentity；result.archiveDir 精确 StampArchive；done.cfgSha 精确 StampConfig |
| C3 配置哈希链 + 14 臂生产复核 | PASS | M3-N1 gain 2e-4→1 浅篡改精确 air:M3Agg:ConfigMismatch；深篡改并重写 result/done cfgSha 精确 air:M3EvalArm:ReplayMismatch；只改归档摘要 etaCenter 精确 air:M3Agg:ArmRecheck；副本正控逐臂重跑 14/14 与摘要一致 |
| C4 验证器先合同后预算 + vreport 审计 | PASS | maxAttempts 3→4 精确 air:M3Batch:ContractMismatch，且副本中无 vreport.attempts、无 vreport.done.mat；删除副本 vnegative.done.mat 后 vreport 精确 air:M3Verify:Bookkeeping 且不盖 done |
| C5 当前干净提交正式批次 | PASS | 3eedfa8 @ 8502460f…，init→s5→aggregate→vunit→vnegative→vaggregate→vreport 完整通过；数值、14 臂复核、28 行恢复矩阵见 §4 |
| C6 可复现性 | PASS | 新批次 14 臂的 ok/etaCenter/etaConv/attLimitMax/vTrk/etaReplayDiff 与登记批次 20260908_010351 逐字段 sample-exact；新批 N5/R1 时间网格全等，max abs dEta=max abs dV=0 |
| C7 诚实计数/旧批次 | PASS | 新批次所有持久 marker 为 1，只存在 attempt1 日志；独立调用历史 ec171b5 批次在当前规则下精确 air:M3Agg:CrossCommit |

## 4. 数值、恢复矩阵与裕量

正式聚合器现场重算所有配对门；简报指定的对照值全部重现：

- M3-N1 vs B0-N：掩码 Percent **−0.29102%**，门为上界 +0.5%，裕量 **0.79102 pp**；full-window −0.29140%。
- common：**65601/96001 = 68.3%**；B1 对照依旧是 4800/96001 = 5.0%。
- 9 个非复现 eta 臂（N1–N5、D1–D2、B2-N1/N2）replayDiff=0；另一个复现臂 R1 也为 0；4 个 fixed 基线无 eta 回放，为 N/A（日志打印 Inf）。
- N5/R1 在同一 runId 9641cd75-1b0a-4326-97ea-aaf623b4bfe4 内运行，eta 和 v 样本差均为 0。
- vnegative 日志机械计数为 **28 行**：trials 4×5=20 + boundary 4×2=8。有限/空/NaN/Inf 四态在已声明成功和错误出口上全部 restored。

本机同版本两个正式批次的 14 臂判据字段 sample-exact，本轮观察差为 0。这不等于已测量跨机器抖动；本报告不把“同机为 0”扩张为跨平台确定性承诺。指定 Percent 裕量远大于本轮观察差，不属于骑线通过。

## 5. 独立探针覆盖与事故留痕

有效独立探针为 30 项：1 个副本正控、8 个 C1、10 个 C2、3 个 C3、5 个 C4（含无 marker/done 后置断言）、2 个 C6、1 个 C7；30/30 PASS。probe_results.csv SHA-256 为 3F73E7F68619B632832AA9D97CFAA53449FF83097B85661790B637E352540CEA。

第一次独立探针位于 probe_20260908_122035/：C1–C4 已全部命中，但 Codex 临时夹具错误地假设 fixed 臂的 etaConv 也是结构体，在 C6 比较前退出。仅修改 results 中夹具为“保留原生类型逐字段比较”，然后从副本正控开始完整重跑；第二次 30/30 PASS。该事故是审计夹具缺陷，未修改产品或验收基础设施，不归类为 M3 回归。

## 6. 发现分级、未覆盖项与停止条件

### 6.1 发现

本轮限定范围内**无新 P0/P1/P2/P3 产品或验收基础设施缺陷**。第三轮 F4 四项均具备：

1. 原始复现：当前干净提交上按正式入口全部转绿；
2. 针对性负向：独立副本单因素探针精确落到指定错误 ID；
3. 既有回归：正式 14 臂、28 行恢复矩阵、vaggregate、vreport 和 9 场景驱动回归通过。

故满足规则 §9.4 的目标层停止条件，不增加新门、新矩阵行、新指纹或规则版本。

### 6.2 未覆盖项

- 未重开 M2、F2/F3、T1/T2 或算法线；未运行 M0/M1 独立长链。
- 未做跨机器、跨 MATLAB 版本或非 Windows 确定性比较。
- 未验证 Plane、SITL/HIL、台架与实飞。
- 本轮按简报“唯一产出为报告、不扩展验收门”的硬边界，未新增 A–D 标准图集。本轮是对已冻结 M3 的 F4 证据治理关闭；根据规则 v1.8 §10.3，不用新可视化要求重开原 M0–M3 数值合同。后续新平台阶段开工前仍须单独履行 §10 样张和图集前置。
- Simulink 运行中仍打印既有“输出端口未连接”警告；本轮无对应断言、数值或证据绑定失败，不在 F4 有界审计中扩展为新缺陷。

## 7. 指纹与交付完整性

manifest 的 7 个 SHA-256 指纹：

| 字段 | SHA-256 |
|---|---|
| aggregate | c6d82d3f0de0fa03fe594c3e3fc775fe785310dd35cb48ac51882a9f58322173 |
| trials | 70c58ae0cfee120221817e4339526b2582b48b0fb7b2a0f4ecb5b4de0e3fde9b |
| contract | 4816056c3ce9b8735558a87ff60dcec49c759d1a594f0e3dee59f5dcf5f248e0 |
| evalArm | 8522461ad265bbeb09fbc74440a811ff8ec01c25ad661af9bb9dc84ae769b64c |
| model (air_spare.slx) | d2bd8d11ab276e5c68310b73ca52796ed32c60f1b832c1477c54f4d02103a2ef |
| m0c | 379404215574b3f847f5d4ddacba4485ac1e9390fd72702c9acd84ec16f5b79e |
| m2 | 5a89fa7793621cd5d34ca27a126abfbe2d7725264cdbcd8714f511051f462f8b |

模型只读校验：

- air.slx：0ED0101C77191516FF5FFFB3891DD41BC502C4372707A698D1015419D55A8962
- air_spare.slx：D2BD8D11AB276E5C68310B73CA52796ED32C60F1B832C1477C54F4D02103A2EF

关键日志 SHA-256：

| 日志 | SHA-256 |
|---|---|
| aggregate.attempt1.log | 074F090643F04A8AD5077AAB119A2C39F32823173D8C839D628E9E1491AC2F8F |
| vnegative.attempt1.log | 1A9256202106336F9031A9642C5560295D7D72621709EA3FA7BAFEE248FCEB0E |
| vaggregate.attempt1.log | D3A3AE317DF1731E78510C2291337516B252E5552917077F903F3E1C8CF24DA3 |
| vreport.attempt1.log | D5E64C1D989C68E70ABB4C91111AB91C1D5213A0AD945C974FFB2A2042C4147C |

11 份正式日志均可按 UTF-8 读取，全部 U+FFFD 计数为 0。本轮不提交 results 中的原始日志、MAT 档案或探针代码；Git 交付只包含本报告。

## 8. 最终放行口径

**M3 放行（V1 px4_x8 代理阶段，限冻结提交 3eedfa8 及本报告 C1–C7 范围）。**

F4 证据治理不再作为 M3 代理阶段的开放 P1。后续若改动指纹集、批次合同、M3 评价路径、air_spare.slx、m0c_vref_esc.m 或 m2_eta_esc.m，新证据须按现行 ADR/规则重新绑定；本报告不承诺未来修改自动继承本次放行。
