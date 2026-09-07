# worklog 2026-09-08 — M3 §7.3 正式批次复验 PASS（ZCode / 平台线）

## 做了什么

按 [M3 第三轮独立复验报告](../evidence/M3_REACCEPT_ROUND3_CODEX_20260905.md) §7.3 与 [M3 F4 修复证据](../evidence/M3_F4_FIX_20260908.md) 的收尾清单，在冻结提交 `d552a14`（干净树）用入库驱动 `tools/run_m3_batch.ps1` 一体完成正式复验：

- **正式 14 臂批次**：init → s1..s5（14 臂 × 240 s Simulink 仿真，5 段）→ aggregate，**11 阶段全部 attempt 1 PASS，零重试零崩溃**；聚合在 F4 新规则下全绿（live HEAD 严格绑定、7 指纹现场重算、三方记账、归档配置哈希链、14 臂生产复核 replayDiff 全 0）；
- **配对数值与第三轮独立口径一致**（零新数值）：M3-N1 vs B0-N 掩码 −0.29102%，common 68.33%；
- **vnegative 四态恢复矩阵**：边界试验 PASS + 恢复矩阵 **28 行（trials 4×5 + boundary 4×2）全过**；
- **vreport 记账审计 PASS**：三验证器阶段盖章 attempt 1/3、指纹 = 现场 `d552a14`；
- **受影响回归**：`test_m3_batch_driver.ps1` 9 场景 PASS、`test_m3_coordination_unit` PASS。

## 如实记账

- 本轮批次一次通过，无失败尝试、无手动清计数（attempt 标记全为 1）；
- 启动过程两次流程性失败（与代码无关）：Git Bash 反斜杠转义导致 `-File` 路径损坏、PowerShell 执行策略拦截——均以修正命令重启，未触及批次语义；
- 批次运行期间工作树冻结，无并行写入（前一轮 DirtyTree 教训执行到位）；
- 证据目录 `results/`（batch_runs + air_m3_batch_staged + air_m3_trials + air_m3_boundary）按惯例不入库，关键数字回填至证据文档。

## 边界

- M3 修复方侧证据链齐备（F4 修复 + 自验 + §7.3 正式复验）；**M3 放行仍以独立复验为准**，本 worklog 不构成放行宣告；
- 全部结论锁 V1 桌面代理仿真等级；不外推统一 Plane / 实飞。

## 下一步

1. M3 独立复验（交 Codex/独立渠道）；
2. P2 前置交付：可视化样张 + 验收标准清单（已起草于仓库外 `第二阶段\P2可视化样张_20260908\`，待叶安确认）；
3. P2 构建（确认后启动）：飞控内核、每电机功率合成、电池 v1 接入、eta 物理效果、涌现限幅一致性。
