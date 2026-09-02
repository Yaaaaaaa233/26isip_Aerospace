# 2026-09-03 M2 第九轮独立验收

项目组：周航正、霍奕茗、于跃、叶安、王健祺

文件负责人：叶安（平台线）

本次贡献：叶安（提出第九轮验收需求、承担平台线判定责任）；Codex（独立审计、MATLAB/PowerShell 实跑、负向探针与报告代拟，AI 协助）

审核：待项目组审核、待指导教师确认

## 本次做了什么

- 在干净 `2be9857` 上运行入库驱动，MATLAB R2022b 分阶段整批 48/48 PASS；runId `1edb644d`，五段 attempt 均为 1。
- WinPS 5.1 驱动层测试 8/8 PASS；治理检查 PASS（12 模块 / 24 Markdown）；差异检查 PASS。
- 独立复跑 attempt marker 的 pre/mid/post 三窗口与超预算探针，确认旧值/新值原子语义及写前预算拒绝，R8-F3 关闭。
- 执行两个 manifest 协同篡改探针：提高 maxAttempts 并同步 done/marker 后 48 PASS；删除 c5 与声明行后 44 PASS。R8-F1 因此仅部分关闭，新增 R9-F1（P1）。
- 发现 WinPS 5.1 批次日志中文输出编码损坏，记录为 R9-F2（P2）。
- 恢复全部 staged 原件，删除两份伪归档，保留正式归档 `20260902_234826`，Git 工作树保持干净后再撰写文档。

## 关键决策与理由

- 不把“done 相对 manifest 合法”视为 manifest 自身可信：批次阶段、行数和尝试上限必须同时与提交内固定合同等值。
- M2 功能/数值和验收基础设施分开判定：数值链 48/48 通过不掩盖聚合器防篡改缺口。
- R8-F2 与 R8-F3 有直接动态证据，关闭；R8-F1 的六类局部篡改虽已修复，但协同篡改仍可放行，判为 PARTIAL。

## 遗留问题 / 风险

- R9-F1（P1）：manifest 可提高 attempt 上限或删阶段/行数，report 仍 PASS。
- R9-F2（P2）：WinPS 5.1 日志中文路径/警告含 replacement character。
- 全量九场景同会话双链仍未覆盖；R2022b 堆损坏与退出码不可靠仍为环境限制。

## 下一步

- 增加源码固定 manifest 合同，并对 maxAttempts、stages、declaredRows、总行数做完全等值断言和负向测试。
- 修复 WinPS 5.1 MATLAB 输出解码，增加中文 sentinel 日志测试。
- 在新干净 HEAD 上由入库驱动重跑 48 行批次及原子 marker 探针。

## 验收状态

- M2 功能与代理数值：PASS，继续放行。
- R8-F2 / R8-F3：CLOSED。
- R8-F1：PARTIAL；验收自动化整体 PARTIAL（R9-F1）。
