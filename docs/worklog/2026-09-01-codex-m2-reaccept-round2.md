# 2026-09-01 M2 第二轮独立复验（Codex）

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线，延续现有责任记录）

主要撰写：待项目组确认

技术贡献：Codex（MATLAB 实际复跑、会话残留诊断、验收逻辑审查与记录）

审核：待项目组审核、待指导教师确认

AI 协助：Codex（复验执行与文档代拟）

## 本次做了什么

- 同步并核对主库 `0625f74`，审查上一轮 Z1--Z7 修复差异。
- 在未人工清理的当前 MATLAB 会话直接运行 `run_m2_session_chain`：单元测试 PASS，随后旁路比较因 `pwm_cmd` 最大差 2 而 FAIL。
- 读取到残留 `M2_ETA_APPLIED=0.99914776890319873`；确认单元测试原样恢复入口的陈旧 M2 状态，完整链没有自动建立恒等前置状态。
- 显式清理后重新运行完整链：单元、旁路零差异、安全注入 4/4、M2 九场景全部 PASS；归档分别为 `20260901_231913`、`20260901_231913`、`20260901_231938`。
- 实际运行 `modules/unified_search/run_unified_acceptance`：13/13 单元、8/8 门槛、`passed=1`。
- 静态发现 `run_m2_session_chain` 未断言九场景的 `result.pass`，存在自动化假绿风险；单元测试错误路径也未清 persistent。

## 关键决策与理由

- 保留 M2 120 s / `[90,120] s` 数值协议 PASS：本轮清理后结果与修复报告逐位一致。
- 将工程验收降为“部分通过”：陈旧会话可由仓库自身 `run_air_m2_trials` 产生，不能把失败归因于无关外部环境。
- M3 仅继续方案和接口设计，暂缓 `.slx` 结构集成，直到完整链能连续运行两次并可靠硬失败。

## 遗留问题 / 风险

- R2-F1：完整链依赖入口 global，Z1 重新打开。
- R2-F2：九场景 `result.pass=false` 不会自动令完整链失败。
- R2-F3：单元测试异常路径未清 `m2_eta_esc` persistent。

## 下一步

- 为 `run_m2_session_chain` 与 `run_air_m2_trials` 增加链级状态规范化及 `onCleanup` 恢复。
- 在完整链末尾断言 `result.pass`。
- 同一 MATLAB 会话无人工清理连续运行完整链两次；增加可控失败路径测试。

## 验收状态

- 未清理 `run_m2_session_chain`：FAIL（旁路 `pwm_cmd` 最大差 2）。
- 清理后 `run_m2_session_chain`：PASS。
- M2 门槛窗 S1/S2/S3：-0.25985% / -0.29211% / -0.22617%，PASS。
- `run_unified_acceptance`：13/13 单元、8/8 门槛、`passed=1`。
- 详细报告：`docs/evidence/M2_REACCEPT_ROUND2_CODEX_20260901.md`。
