# 2026-09-04 ZCode 第三轮修复（M3 第二轮独立验收 F2/F3/F4/F6）

- 作者：ZCode（AI 辅助工程）
- 审阅：叶安（文件负责人）
- 关联：`docs/evidence/M3_REACCEPT_ROUND2_CODEX_20260904.md`（第二轮独立验收）、`docs/evidence/M3_REACCEPT_ROUND3_FIX_20260904.md`（本轮修复报告）
- 提交：代码链 55bc7bc..__LAST__（冒烟期增量修复提交），文档 __DOC__

## 摘要

第二轮独立验收判定验收基础设施 NOT VALIDATED（F2 评价器用候选参考且窗口错一拍；F3 扰动臂无姿态硬判；F4 分段证据治理六类漏判；F6 修复报告计数/runId/checker 表述失实）。本轮全部关闭：

1. **F2** 收敛评价输入改为**离线重放冻结内核重建的搜索中心**（`m3_replay_eta_center`），重放必须逐样本复现归档候选（保真门 `air:M3EvalArm:ReplayMismatch`）——候选=中心+抖动，其周期末样本被抖动相位污染，且抖动在内核内部生成，只有内核自己能剥掉。M3/B2 统一显式 [192,240)。真实七臂重放 diff=0；内核驱动的远离/趋近/恒中心相位例按真中心正确判定；Codex 相位反例与死搜索例被保真门拒收。
2. **F3** 位 3 姿态越限对所有臂硬判（真实 14 臂零硬标志，不改判历史）。
3. **F4** 批次治理按规则 v1.7 §2.4–2.9 全量落地：批次 manifest（batchId 与段 runId 分离、源码合同权威、布局参数化）、入口+结束双现场取证、sha 现场重算核对、段+行双层 verdict、attempt 六类拒收+持久原子计数、入库有界重试驱动+驱动测试、R1 时间轴纳入复现比对；合成批次 25/25 篡改负向+备选三段布局正控。
4. **F6** 第二轮修复报告追加勘误块（原文不改）。

## 主要改动

`models/px4_x8`：新增 m3_replay_eta_center / m3_batch_{contract,init,validate,locate,stage,aggregate} / m3_stage_{attempt,done} / verify_m3_round3_closure；改 m3_eval_arm（重放中心+保真门+统窗+attLimitMax）、run_air_m3_trials（stagedDir 批次化、bindingExit、失败段不盖章）、m3_aggregate_batch（硬化重写）、run_air_m3_boundary（结束取证）、test_m3_coordination_unit（B8）。`tools`：run_m3_batch.ps1、test_m3_batch_driver.ps1。

## 缺陷与教训（本轮新增）

- struct() name/value 对 cell 值的复制陷阱再次出现（altLayout/SegDuplicate 两处，冒烟暴露）；rmfield 型 lambda 返回值层级错误；方向敏感 isequal（行/列 cell）；空 cell 索引；.mat 扩展名遗漏。全部在合成批次冒烟阶段（正式链之前）暴露修复。
- 篡改期望层校准：改 manifest 名单会先撞**合同层**（exact-once/同段规则）而非聚合层——分层本就如此，负向期望按实际拒绝层如实断言（ReproSplit→ContractMismatch、换臂夹具才能命中 ManifestMismatch）。
- 正式链 init 曾因驱动控制台日志写入仓库根触发干净树门并按预算中止三连——治理按设计工作；日志移出仓库后重跑。教训：驱动的一切输出必须落在 gitignored/仓库外。
- 管道缓冲陷阱：长任务经 `| tail` 后台运行，进程错误退出时缓冲输出丢失且管道挂起（一次误判为堆崩溃后被误杀）——长任务一律直接重定向日志文件。
- R2022b 堆损坏（OPEN LIMITATION）冒烟期两次（错误打印后的退出阶段 0xc0000374）。

## 下一步

项目组追认两轮独立验收与本轮修复；Plane 接入（霍奕茗 P4 适配器验收后）→ R4 同 Plane 复跑。
