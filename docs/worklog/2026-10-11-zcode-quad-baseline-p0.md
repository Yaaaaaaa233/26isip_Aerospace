# 2026-10-11 ZCode（叶安线）：建模调整方案 P0/P1 落地（工作簿三套 baseline）

## 任务与边界

按 [`QUAD_SIM_MODEL_PLAN_20261011.md`](../QUAD_SIM_MODEL_PLAN_20261011.md) 落地 P0/P1。
红线照旧：`models/plane`、`platform_link*`、全部 `.slx`、既有证据零触碰；`plane_quad`
既有默认配置零改动（Q2/M4' 证据可复现），新参数全部走 `quad_sim.baseline()` opt-in。
口径：workbook_baseline_20261011（非老师参数，不可外引，C9）。

## 交付

- `+quad_sim/baseline.m`：bg/b40/b42 参数包（质量按 BOM R2 裁决、臂长、惯量、
  转速上限、电池（7S4P/96Ah 与 12S31.5Ah，2.3V/芯截止按电芯报告）、电子负载 15W（R4）、
  台架映射逐表拟合：T=a·n²（R²=0.999）/P=poly3（域内 ≤2.2%），PM-L1 外推系数=0）。
- `+quad_sim/inertia_from_bom.m`：平行轴惯量（X 架 45°、质心居中、惯性积 0，C4）。
- `run_quad_baseline_checks.m`：冒烟验收（函数+result+硬断言；悬停锚 ≤3%、确定性两遍
  逐位、U 形涌现、惯量可重算审计）；输出 `results/quad_baseline_smoke.csv` +
  `quad_baseline_Pcurve.png`（样张首版）+ `baseline_smoke.log`，筛选归档
  [`docs/evidence/quad_migration/quad_baseline_p0/`](../evidence/quad_migration/quad_baseline_p0/)。
- 文档：仓内方案（含 R1–R5 裁决、C1–C9 妥协登记、v1.8 §10 样张清单**待叶安确认**）；
  库外《四旋翼 Simulink 建模调整方案 v1.1》同日成稿（第三阶段目录）。

## 冒烟结果（3/3 PASS）

| 基线 | 悬停锚偏差 | U 形 v* | 对工作簿汇总偏差（C7 报告） |
| --- | --- | --- | --- |
| bg | −0.000% | 3.99 m/s | +13.2% |
| b40 | −0.000% | 5.99 m/s | +25.2% |
| b42 | −0.000% | 6.00 m/s | +27.6% |

确定性：同会话两遍悬停逐位一致（抖动 0 记账）。

## 调试事故（已修复）

首跑 SMOKE FAIL 4 项：b40/b42 悬停功率 +48.2%/+34.6%、U 形不涌现（v*=0、速度为 0）。
`results/dbg_baseline_hover.m` 诊断定位：**参数包只覆盖了 `ceiling_kn_rpm_per_V`，
漏了 config 在 struct 合并前就固化为默认值的派生字段 `kv_rpm_per_V`**——植物满油门
转速上限停在 38.78×V≈1108 rpm（低于 b40 悬停需求 1653 rpm），飞机下坠（vz=16.8 m/s），
假功率来自下坠废阻。同族问题：`battery_resistance_ohm` 亦为合并前派生（7S 值挂到 12S
bg 上）。修复：参数包尾部显式同步两个派生字段（`kv=ceiling`、`R=n_ser·r_cell/n_par`）。
教训（与 struct() 空 cell/数组复制陷阱同族）：**config 的"合并前派生字段"不会被
struct 基底覆盖自动重算，参数包必须逐个显式同步**——已写进 baseline.m 头注释。

## 边界与剩余

- 冒烟 tier='smoke'；正式验收（标准图集+指标表）待样张清单确认（方案 §5）。
- C7 偏差 +13~28% 为测试桨台架表 vs 工作簿未溯源设计桨曲线之差，已如实入表；
  待工作簿作者确认设计桨曲线出处后收紧。
- P2（控制现实性）、P3（算法验证）、P4（air_quad.slx/SITL）待排期。
