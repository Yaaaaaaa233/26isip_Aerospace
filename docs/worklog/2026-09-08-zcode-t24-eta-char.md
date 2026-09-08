# 2026-09-08 ZCode：T2.4 eta 特性展示实施（模型 v1.1 + 正式批 E1–E6）

负责人：叶安（Control / Simulink 平台线）；执行：ZCode。

## 做了什么

按 `docs/T24_ETA_CHAR_PLAN.md` v1.0 §5 五步全部完成：

1. `models/plane/+plane/config.m`：`coaxial_decay_kappa=0.5`、映射斜率 0.3→0.55、删除 `coaxial_delta_split_gain`（v1.0 回中项，废弃注明）；
2. `models/plane/+plane/step.m`：δ_lo=δ₀·(vi/ vi₀)^κ（复用 H3 vi 形状，提公用 `local_vi`；v=0 严格=δ₀）；
3. `models/plane/run_p2_chain_check.m`：G-ETA 第三门重锚为悬停三点序 P(0.90)<P(1.00)<P(1.10)（E5）；
4. `models/plane/run_eta_characteristics.m`（新增）：η∈[0.75,1.1] × 三工况 × κ/δ₀ 敏感带 + η\*(v) 漂移 0..12 m/s → 图 1/图 2 + 指标表（E1–E4）；
5. 附带：`harness/+harness/make_plane_adapter.m` 真值图同步 v1.1 同式（否则 G1 门 1% 容差会被 δ 衰减打破，约 2–3% 系统差）；T2 两个正式运行器按版本绑定声明**不动**（其 E_pred 解析图维持冻结口径）。

## 结果（两次正式批逐位一致，确定性）

- E1 悬停谷底 **0.899**；E2 v\* 谷底 **0.941**（≥悬停）；E3 单谷 3/3；E4 谷深 1.89/0.56/0.36 W（0.39%/0.16%/0.09%，随速度变浅，符合 δ 衰减方向）；
- η\*(v)：0.899→0.956（12 m/s），12/12 段非降；κ 带悬停恒 0（max|ΔP|=0.0 W，形式自检）；
- E5 悬停三点序 485.41/487.30/492.86 W；E6 链检查 **24/24** 门 PASS（悬停 P(η=1)=487.30 W 与 T2 逐位一致、U 形 v\*=5 降幅 27.3%），适配器 5 门 PASS（G1 最大 0.48%）；
- 图表呈现质检（视觉模型逐项）后两处打磨：图 2 文献锚 0.90 虚线改灰色+入图例、指标表 LaTeX 字面量改 Unicode 希腊字母；重跑后数值不变。

## 产物

- 正式批（gitignored）：`results/eta_characteristics/20260908_142954_eta_char/`（图 1/图 2/指标表/result.mat）；日志 `results/t24_20260908/`；
- 人工验收包（仓库外）：`第二阶段\T24人工验收包_20260908\`（H1–H9 核对单，5–10 分钟）；
- 证据：`docs/evidence/T24_ETA_CHAR_20260908/README.md`；状态页第 14 次更新。

## 边界遵守

M3/px4_x8 与全部 `.slx` 零改动（寻优平台 D2 冻结）；T2 证据不重开（版本绑定）；样张/批产物不入库不充当验收证据（本目录 README 只登记数值与路径）；η\* 结论为未标定模型预测，不构成实测节能宣称。
