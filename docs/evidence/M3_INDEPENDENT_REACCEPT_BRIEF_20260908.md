# M3 独立复验指令（第四轮，Codex）——有界审计

日期：2026-09-08
委托：叶安（文件负责人）；修复方：ZCode（平台线）。本文件为交给独立复验方 Codex 的完整指令，逐字送达。
背景材料（先读）：
1. [M3 第三轮独立复验报告](M3_REACCEPT_ROUND3_CODEX_20260905.md)——你方上轮发现 F4 四缺陷（§3.1–§3.4）并给出 §7 关闭清单；
2. [M3 F4 修复证据](M3_F4_FIX_20260908.md)——修复方自验 + §5 正式批次（batchId `1d9dd7aa` @ `d552a14`，11 阶段 attempt-1）；
3. [全项目重验收扫描](PROJECT_REACCEPT_SWEEP_20260908.md)——§1 #11：HEAD 复跑批次（batchId `000f024f` @ `949eb50`，11 阶段 attempt-1，配对数值与上轮一致）；
4. 规则 [`ACCEPTANCE_AUTOMATION_RULES.md`](../ACCEPTANCE_AUTOMATION_RULES.md) v1.8（§2 条款 5 跨提交拒绝、§9.4 留痕升版）。

---

## 任务与判定问题

回答一个问题：**F4 的四个缺陷是否已按你方 §7 清单关闭，且关闭证据可信？** 只审计、只报告——**发现问题不得修复**（修复方修复，保持职责分离）。

### 待核声明（逐条给 PASS/FAIL）

- **C1（对应你方 §3.1）**：聚合强制 live HEAD == manifest 提交（`air:M3Agg:CrossCommit`），manifest 声明的全部 7 个指纹（含聚合器自身，`m3_live_fingerprints.m`）现场重算并逐一断言；
- **C2（§3.2）**：正式入口 `m3_batch_aggregate` 的 done.attempts 记账——六类（缺字段/0/NaN/非整数/超上限/与持久标记不一致）全部 `air:M3BatchAgg:StampAttempts`，且 stamp 身份（runId/commit/archiveDir）与 cfgSha 三方绑定生效；
- **C3（§3.3）**：归档配置哈希链（effective_config.mat ↔ result.cfgSha ↔ done stamp）+ 14 臂生产复核逐臂重跑与归档摘要精确一致（浅篡改 → ConfigMismatch；深篡改+重 stamp → ReplayMismatch）；
- **C4（§3.4）**：验证器入口在消耗预算**之前**过 `m3_batch_validate` 合同门（改 manifest.maxAttempts → `air:M3Batch:ContractMismatch`，无 attempt 消耗、无 done 盖章）；vreport 记账审计拒绝不完整验证链；
- **C5（§7.3 正式批次）**：在一个干净冻结提交（当前 HEAD 或你自选的干净提交，登记其哈希）用入库驱动 `tools/run_m3_batch.ps1` 完整重跑 init→s5→aggregate→vunit→vnegative→vaggregate→vreport；对照登记值：M3-N1 vs B0-N 掩码 **−0.29102%**（门 0.5%）、common **65601/96001**、9 个 eta 臂 replayDiff=0、恢复矩阵 **28 行**、各阶段 attempt 计数如实（预期全 1；若发生堆崩溃重试，按规则 v1.7 判定并保留日志）；
- **C6（可复现性）**：你自己的运行与登记批次的 14 臂中心值一致（Simulink 确定性）；批次内 repro 对（M3-R1 vs M3-N5）同会话一致；
- **C7（诚实计数）**：持久 attempts 标记无重置痕迹；历史旧批次（ec171b5）在新规则下确实不可聚合（条款 5 语义）。

### 方法要求

- **用你自己的探针**：负向篡改一律在 `results/`（gitignored）下的**拷贝**上做，禁止改动任何 git 跟踪文件与 `results/air_m3_trials` 既有归档；篡改方式自选（不必复用修复方夹具，鼓励相异路径）；
- 驱动用法：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_m3_batch.ps1 -Matlab "D:/matlab2022b/bin/matlab.exe" -MaxAttempts 3`（整链约 35–50 分钟；R2022b 堆崩溃由驱动有界重试处理，属登记的环境限制）；
- 日志为 GBK→UTF-8（驱动已处理）；`results/batch_runs/<stamp>/` 保留全部 attempt 日志。

### 硬边界（防膨胀条款）

1. **禁止新增**任何验收门、矩阵行、规则版本、指纹项——本复验是审计既有声明，不是扩展基础设施。仅当你发现 **P1 级缺陷**时，可在报告中提出最小修复建议（仍由修复方执行）；
2. 禁止修改仓库任何被跟踪文件；`air.slx` 与全部 `.slx` 只读；禁止 force-push；你的产出只有一份报告文件；
3. 范围仅 M3 F4 关闭与 §7.3 批次。**不重开** M2（十轮已关闭；HEAD 的 m2_eta_esc 变更属已登记开放项，项目组另行决定）、不审 T1/T2/算法线、不重开 F2/F3。

### 交付

报告写 `docs/evidence/M3_REACCEPT_ROUND4_CODEX_20260908.md`（沿用你方前几轮格式）：逐声明 C1–C7 判定与证据（runId/提交哈希/日志路径）、发现按 P1/P2/P3 分级、明确列出**未覆盖项**、结尾给整体结论：**M3 放行 / 不放行（附条件）**。提交该报告为一个 commit（报告文件本身），不动其他文件；提交前跑 `tools/check_repo_governance.ps1`。

## 结论口径提醒

M3 全部数值结论锁 V1 桌面代理仿真等级（`models/px4_x8` 链），不外推统一 Plane/实飞；Percent 口径不与 T1/T2 跨模型横比。
