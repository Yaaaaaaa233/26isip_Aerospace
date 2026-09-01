# 2026-09-01 Codex M1 独立复验

## 本次做了什么

- 核对 Zhoucmd6 主库 `main` 与本地 `HEAD`，二者均为 `028aad8`。
- 在 MATLAB/Simulink R2022b GUI 独立会话中实际复跑平台线 6 个验收入口。
- 新增 `docs/evidence/M1_REACCEPT_CODEX_20260901.md`，记录通过项、原始数值、证据边界与 ZCode 修改清单。

## 关键决策与理由

- 验收判定使用脚本返回的 `pass` 断言和归档 CSV，不仅依赖终端中的 PASS 文本。
- 将“功能回归通过”与“文档可对外引用”分开判定：功能无阻塞，但证据表述和阶段状态需先统一。

## 遗留问题 / 风险

- M1 证据把 R0/DL1 写成逐样本一致，实际 `max|dv_ref|=3.2757e-05 m/s`；严格为 0 的是 DL1/DL2 复现。
- README、AGENTS 和 M0A/M0B/M1 部分接口文档仍保留“下一步 M1/实施中”。
- MATLAB 冷启动约 3 分钟；已启动 GUI 后验收脚本正常。

## 下一步

- ZCode 按独立复验报告 §5 修正证据表述和阶段状态。
- 纯 Markdown 修改完成后做文本/链接复核；不需重跑 M1 矩阵。
- 修正后再进入 M2 方案文档，尚不应直接修改 `.slx`。

## 验收状态

- M0-C unit：PASS。
- M0-C dirty guard：PASS。
- M0-A baseline compare：4/4 PASS，最大差 0。
- M0-B safety injection：4/4 PASS。
- M0-C trials：9/9 PASS，复现差 0。
- M1 robustness：27/27 PASS，11/11 配对通过，4/4 故障通过。
