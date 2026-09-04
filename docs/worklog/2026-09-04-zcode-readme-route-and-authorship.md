# 2026-09-04 ZCode：README 算法路线现状与按提交分工概览

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：周航正
本次贡献：周航正（提出"算法已不是 ESC、需在 README 明示"与"按 commit 概括分工"需求）
整理与实施：ZCode（提交历史梳理、README/AUTHORSHIP 更新）
审核：待项目组审核
AI协助：ZCode（提交统计、文档更新；未改任何源码/模型/证据）

## 本次做了什么

- 本地 main 同步远程至 `b61bd01`（此前本地落后 7 个提交：x8phys PR、M3 B–E、M3 独立验收）。
- `README.md`：
  - 新增"算法路线现状（2026-09-04）"节：ESC 不再是推荐路线（harness esc 0.9819<multistart 0.9912、风场任务 tracker/qnewton 占优、任务6 起 qnewton 为新推荐、路线§3-5 转向名义功率图+解析调度+在线风估计、任务7 负结果），ESC 保留为 WPC 四模式之一与开发基线；
  - 快速开始与目录补登记任务7/8/9 三模块；"当前成果"新增任务7-9 小节（含有效性警示）；
  - 平台节更新：M2 第十轮口径、`+x8phys`/Plane 契约并入、M3 B–E 已实现但第一轮独立验收 PARTIAL 未放行。
- `docs/AUTHORSHIP.md`：新增"分工概览（按 Git 提交统计，截至 2026-09-04，main@b61bd01）"：叶安 67 次（平台线 M0–M3+验收治理）、周航正 zhoucmd6 20 次（治理/架构/总装，映射待确认）、王健祺 7 次（算法线任务1–9）、霍奕茗 2 次（x8phys/Plane 契约）、于跃暂无提交。
- 治理检查 `tools/check_repo_governance.ps1` 修改前后均 PASS。

## 关键决策与理由

- 只改 README/AUTHORSHIP，不改 `DEVELOPMENT_STATUS.md`：本次未改变阶段放行或可引用结论，AGENTS.md 规定状态页只在状态变化时回写；M3/x8phys 的放行记录属平台线负责人。
- 所有对比数字直接取自仓库既有证据（README 各模块小节与 docs/evidence），未引入新结论；ESC 定位表述与 ADR-001（开发基线）和 WPC 路线（四模式）一致。

## 遗留问题 / 风险

- `modules/realistic_constraints_search`（任务7）的 `START_HERE.m`、`run_task7_acceptance.m` 在模块 README 与登记表中列为入口，但文件未入库（仓库内仅有 `+w7` 包）——需王健祺补提交入口脚本或更正登记。
- `zhoucmd6`/`Zhoucmd6` 与周航正的账号-姓名映射为推断，待项目组确认。
- 分工表提交数含 AI 协助提交（各成员大量实际贡献以模块署名区与 worklog 为准），建议项目组复核后按需修订。
