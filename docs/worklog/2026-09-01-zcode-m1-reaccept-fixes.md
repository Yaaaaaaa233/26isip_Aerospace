# 2026-09-01 ZCode 按 M1 独立复验报告修正文档

## 本次做了什么

- 将本地 `53ad877`（前飞速度寻优模块 V1-V3）与 `d8619fe`（M1 独立复验报告）推送至 Zhoucmd6 主库；fork 上曾出现同内容异历史的 `d8b5d66`（docs/ 零差异、缺模块提交），已按备份对齐惯例 `--force-with-lease` 覆盖，三边同步到 `d8619fe`。
- 落实复验报告 §5 五项（F1–F4 仓库文件、F5 本地配置）：
  - **F1**：`docs/evidence/M1_ROBUSTNESS_20260901.md` 撤回"DL1_esc 与 R0_esc 参考轨迹逐样本一致"的过强表述。修正前先从本地归档 `20260901_160420` 独立复算：`max|v_ref(R0)-v_ref(DL1)|=3.275700495e-05 m/s`、`DL1/DL2=0`，与复验报告数值一致。现口径：时延 vs 名义最大差 3.28e-05 m/s（对判据无实质影响），严格为 0 的是 DL1/DL2 确定性复现。
  - **F2**：`docs/interfaces/M1_ROBUSTNESS.md` 头部状态由"实施中"改为"已完成并通过验收（2026-09-01）"，并补复验报告链接。
  - **F3**：`README.md`（分层表 + 成果节）、`AGENTS.md`（模块总览）、`M0A_OBSERVABILITY.md`、`M0B_SPEED_LOOP.md` 的"下一步 M1"统一改为"M1 已完成，下一步 M2 上下桨转速比 ESC"。
  - **F4**：`docs/interfaces/WORKSPACE_INVENTORY_20260831.md` 顶部加历史快照横幅，指向 `DEVELOPMENT_STATUS.md`。
  - **F5**：本地 `main` 改为跟踪 `origin/main`（原跟踪 `fork/main` 导致 `git status` 显示 ahead，纯本地配置）。
- `DEVELOPMENT_STATUS.md` 复验 bullet 的"待后续修正"更新为"已于同日修正"。

## 关键决策与理由

- F1 的教训记录：M1 首轮验收时从四舍五入相同的汇总指标（act/err/convT/vref(end) 三位小数一致）推断"逐样本一致"，未做逐样本离线比对。时延链使 ESC 解调梯度的相位不同，平坦面上也产生 3.28e-05 m/s 量级的中心轨迹差。今后"逐样本一致"表述必须以逐样本比对为据，不得以汇总指标代证。
- 只改 Markdown 与本地配置，未触碰 `run_air_m1_robustness.m` 与任何 `.slx`，按复验 §6 无需重跑 27 场景；提交前以 `grep` 复核入口文档不再含"下一步 M1/实施中"。

## 遗留问题 / 风险

- 无新增。原 M1 worklog（追加式不回改）中未含该过强表述，无需修订声明。

## 下一步

- 进入 M2 方案文档：八电机上下桨配对与 `eta` 定义、受约束 `X8 Control Allocator`、`ratio_esc` 代价换接平台 `P_est`、eta 0.8/1.0/1.2 配对基线；在此之前不动 `.slx`。

## 验收状态

- 本轮纯文档/配置修正，无代码与模型变更；M1 矩阵与平台线回归沿用复验结论（全绿）。
