# 2026-09-01 ZCode 按署名规范补签平台线文档

## 本次做了什么

- 拉取主库 `0b6a3d4`（速度直搜研究模块 speed_shift_search/speed_rugged_search + 统一 MOP/MOE harness 层）与 `44aafc8`（署名规范 [`docs/AUTHORSHIP.md`](../AUTHORSHIP.md) v1.0），本地 main 快进到 `44aafc8`。
- 按 v1.0 规范为平台线由 ZCode 会话产生/维护的文档补署名块（格式沿用同提交在 `docs/architecture/` 的先例）：
  - 接口基线 4 份：`M0A_OBSERVABILITY.md`、`M0B_SPEED_LOOP.md`、`M0C_SPEED_ESC.md`、`M1_ROBUSTNESS.md`；
  - 证据 3 份：`M0C_TRIALS_20260901.md`、`M0B_RERUN_20260901.md`、`M1_ROBUSTNESS_20260901.md`；
  - 模块 README 1 份：`models/px4_x8/README.md` 新增"署名与贡献"表（代码与 `.slx` 署名统一记录于此，符合规范"不在函数顶部堆叠"）。

## 关键决策与理由

- **署名口径**：平台线各轮的需求、技术判据、验收决策与提交均由叶安完成（Codex 架构文档"技术依据"亦标注叶安为 Control/Simulink 平台方向），故文件负责人/主要撰写署叶安；ZCode/Codex 只列 AI 协助与技术贡献，并写到具体内容（规范第 1、4 条）。路线图 §1 只定义到工作线级、未点名平台线负责人，如与项目组实际分工不符，按规范"署名错误单独修正"处理。
- **审核状态如实**：全部写"待项目组审核、待指导教师确认"；Codex 独立复验不属于项目组人工审核，只列入"技术贡献"，不冒充已审核（规范第 3 条）。
- **不越界**：Codex 署名的证据（`M0B_REACCEPT_CODEX`、`M1_REACCEPT_CODEX`、`M0B_REVIEW`）与架构/ADR 文档已有其本人补签，本轮不动（规范第 5 条：修改别人负责的文件须保留原署名并追加，留待相应负责人）。CSV 为自动生成物，按规范不加手工署名，来源已在对应证据文档说明。
- 历史工作日志按追加式约定不回改署名；本篇起 worklog 记录实际参与人：叶安（需求与决策）、ZCode（执行）。

## 遗留问题 / 风险

- `docs/evidence/M0B_REVIEW_20260901.md`、`M0B_REACCEPT_CODEX_20260901.md`、`M1_REACCEPT_CODEX_20260901.md` 及 `docs/architecture/`、`docs/decisions/` 之外若还有无署名的他人文档，由各负责人自行补签。

## 下一步

- M2 方案文档（八电机配对与 `eta` 定义、受约束 `X8 Control Allocator`、`ratio_esc` 代价换接平台 `P_est`），新文档将按 v1.0 规范在标题后直接带署名块。

## 验收状态

- 纯 Markdown 署名补签，无代码/模型变更；沿用 M1 复验结论（平台线全绿）。

## 实际参与人

- 叶安：需求与验收决策
- ZCode（AI 协助）：规范落地、文档补签与本简报
