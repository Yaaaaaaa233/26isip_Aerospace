# 2026-09-02 M2 第六轮发现修复（R6-F1/F2/F3）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线）

本次贡献：ZCode（R6-F1/F2/F3 修复实现、42 行针对性矩阵执行、治理脚本兼容性收口、规则 v1.3）

审核：待项目组审核

AI协助：ZCode（修复实现、分段批次执行与状态回填代拟）

## 本次做了什么

- 读取第六轮独立验收报告（`docs/evidence/M2_REACCEPT_ROUND6_CODEX_20260902.md`，Codex，46fe96b）并按 §8 关闭条件修复三项发现：
  - **R6-F1** `verify_m2_round4_closure` 源码指纹改为每个取证点独立现场重取（`srcFingerprint()` + `assertSourceBound()`）：HEAD / 验证器 SHA-256 / 脏树状态在 init、段开始、段盖章、report 四处独立取证；删除 `'unknown'` 占位；脏树（含未跟踪文件）硬拒绝；git 命令 `git -C <repoRoot>`，与进程工作目录解耦；每段 `done.mat` 盖自身指纹。
  - **R6-F2** `validateStaged` 对每行 verdict 硬断言 PASS；新增 `failrow` 篡改负向；聚合总数由 manifest `declaredRows` 动态求和，删除硬编码 39。
  - **R6-F3（最小双链路径）** `run_air_m2_trials(injectError, scenarioSet)` 新增 `'nominal'`（E2+S1/S2/S3，4 仿真/链），`run_m2_session_chain(injectError, trialsMode)` 透传，C5 双链改用最小集；门槛与数值协议不变；全量双链登记为环境限制未覆盖组合。
- contract 段新增 3 行负向（`failrow`/`shamix` 玩具副本 + 脏树现场负向），矩阵 39→42 行。
- `tools/check_repo_governance.ps1` 加 UTF-8 BOM（第六轮 worklog 登记的 PS 5.1 解析问题收口），5.1 实跑 PASS（12 模块/24 文档）。
- 规则文档升版 v1.3（§2.5/§2.6/§4.4 + 自检清单）。

## 关键决策与理由

- C5 选最小双链而非重试全量：两次在同位置复现崩溃，重试证据脆弱；最小集完整保留 C5 的目的证明（脏会话复用/同会话哈希一致/门槛对照），全量场景由 c2clean/c3 单进程覆盖。
- report 强绑定批次提交（HEAD 前进即拒绝）：R6-F1 的语义就是"证据绑定生成它的提交"；后续提交复跑需整批重跑是预期行为。
- 修复自检先行：5 项无仿真探针在提交前抓出两个真缺陷（git 取证目录依赖、短路返回缺 `scenarioSet`），另由 checkcode 抓出 `writeAggregate` 返回值未赋值。

## 执行记录（诚实口径）

- 第一次正式批次在 c1c2stale 盖章处被自身脏树门拒绝——批次运行中编辑了规则文档（`M docs/ACCEPTANCE_AUTOMATION_RULES.md`）。这是 R6-F1 修复按设计工作的现场证明，同时也是流程错误：批次前所有仓库文件必须已提交。证据文档草稿随即移至仓库外，规则 v1.3 先行提交（deed6e4）后批次重启。
- 第二次批次六个 stage 全部 PASS（42 行证据齐备），report 段抓出本修复自身的实现缺陷：声明行数求和误用 `structfun(@nnz, ...)`（数的是非零字段数=段数 5，不是行数 42）。修正为 `sum(cell2mat(struct2cell(...)))` 并提交（2d36288）；按 R6-F1 单提交绑定语义，验证器变更使旧批次证据失效，整批在 2d36288 重跑——绑定语义的代价由修复方自担。
- 脏树负向探针初版用 `.tmp` 后缀，被 `.gitignore` 的 `*.tmp` 吞掉（porcelain 不可见），改用 `.txt`。

## 遗留问题 / 风险

- 全量 9 场景同会话双链仍未覆盖（R2022b 堆损坏环境限制），待 MATLAB 升级/换机后补跑。
- report 为批次提交专用；HEAD 前进后需整批重跑（同批次绑定的预期语义）。

## 验收状态

- 正式分段批次（init→c1c2stale→c2clean→c3→c5→contract→report，每段独立进程、单提交 `2d36288`、干净树）：**42/42 PASS**，runId `ff8636ec-e2c4-4181-9e71-7334a6d7130e`，归档 `results/round4_closure/20260902_175314/`（gitignored）；双链哈希一致 `d5fc25bf…197`；S1/S2/S3 = −0.262619%/−0.293804%/−0.214654%（最小裕量 0.714654 pp，≥47×抖动）。证据：`docs/evidence/M2_REACCEPT_ROUND6_FIX_20260902.md`。
- checkcode：真实问题 0；无仿真快速探针 5/5。
- 仓库治理检查：PASS（12 模块/24 文档，PS 5.1）。
