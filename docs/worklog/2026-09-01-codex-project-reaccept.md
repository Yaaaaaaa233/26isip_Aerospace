# Worklog：项目新进展独立复验（Codex，2026-09-01）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线，延续现有责任记录）

记录性质：Codex 独立复跑与交接，待项目组审核

AI 协助：Codex（Git 核对、MATLAB GUI 复跑、结果分析与成文）

## 本次工作

- 获取主库至 `490711c`，确认本地原为 `c354eaf`，主库新增 `modules/unified_search`。
- MATLAB R2022b GUI 实际运行 `test_m2_eta_esc_unit`：PASS。
- 复现“单元测试后直接跑旁路回归”失败：`pwm_cmd` 差 2；清理 M2 全局/持久状态后重跑差 0，确认为测试隔离问题。
- 实际运行 `run_air_m0b_safety_injection`：4/4 PASS，归档 `20260901_220104`。
- 实际运行 `run_air_m2_trials`：S1 +0.353364%、S2 -0.293022%、S3 +0.506190%；S3 超过 +0.5% 门槛，总结果 FAIL，归档 `20260901_220344`。
- 静态核对 `unified_search` 证据：ea/multistart 平均 MOE 为 0.99268710 / 0.99242180，与文档一致；发现验收不硬失败、署名/worklog/AGENTS 入口未补齐。

## 交接结论

- M2 暂不放行，M3 暂不启动。
- ZCode 先按 `docs/evidence/PROJECT_REACCEPT_CODEX_20260901.md` 的 Z1–Z7 修复。
- M2 关闭条件：验收入口覆盖全部文档门槛，且在至少 3 个新 MATLAB 会话中 3/3 总 PASS。
- 本次没有修改 MATLAB 源码或 `.slx`；新增 `results/` 为本地忽略件，不入 Git。
