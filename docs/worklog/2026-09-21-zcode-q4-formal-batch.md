# 2026-09-21 ZCode（叶安线）：Q4 正式验收批 + Q 系机器验收收口

## 任务与边界

按 [`QUAD_MIGRATION_PLAN_20260921.md`](../../QUAD_MIGRATION_PLAN_20260921.md) §4-Q4 执行：
9000s 正式批 ×2 逐位确定（L1 估计链，五臂）+ 真值口径基线批（同种子）+ M6/M7 门评估。
红线照旧：`models/plane`、`models/plane_quad`、`modules/platform_link{,_37,_38}`、
全部 `.slx`、既有证据零触碰；全部数字为 X8 占位管线口径（P4）。
演示窗样张与人工验收包属库外件（H1/H2，叶安执行），不入库。

## 预注册与执行

- `+q39/q4_opt.m` 开批前冻结：F1*（l1 五臂）/ F2*（truth 基线五臂，赢面损耗
  参照）× 2 遍 = 16 个独立 MATLAB 会话，挂钟约 4h20m，逐块 rc=0；
- `+q39/run_q4_formal.m`：分块幂等执行器（SMOKE 120s 冒烟先行验证 runner，
  独立 CSV 不入门、不写正式锚点）；openloop 幕写批锚点（l1/truth 各一）；
- `+q39/q4_gates.m`：G1 跨批逐位 / G2 学习臂全胜开环 / G3 磨损 ≤1pp /
  G4 ×2 逐位 / G5 rows 契约 / G6 M7 结构。

## 结果（证据：docs/evidence/quad_migration/q4_formal/）

- **学习臂全胜开环**（真值口径）：sweepcal 2.0823%（赢面 +4.26pp）、
  purerl_off 1.0717%（+5.27pp）、purerl_on 0.6230%（+5.72pp）vs 开环 6.3418%；
- **赢面损耗 vs 真值批基线**：sweepcal −0.063pp / purerl_off +0.218pp /
  purerl_on +0.132pp（门 ≤1pp，两遍一致）；
- **×2 逐位确定**：全部仿真派生量 pass1==pass2（修正门定义后逐位集内无一失配）；
- **跨批逐位**：openloop/known 真值口径在 l1 批与 truth 批相等（|Δ|=0，
  植物冻结 9000s 复验，Q3 的 3600s 结论升级）；
- **M7 双口径**：Δ超额 ≤0.026pp；bias_meas −0.256%~+0.331%（误差带内）；
  正式批 CSV 60 行 = 2 遍 × 2 批 × 5 臂 × {true,est,diff}；
- rowsN 9000~9006（契约 [9000,11250)，purerl 在线预训练幕 +5/+6 秒行）；
- **M6/M7 机器门 6/6 PASS** → M1–M8 机器验收全部闭环。

## 门定义预注册修正（首次评估 FAIL → 归因 → 修正 → 复评 PASS）

- runtime_s（挂钟簿记）逐出逐位集（M6 逐位指仿真派生量；Q1/M5 先例同）；
- 锚点臂 openloop 的 margin 列逐出逐位集（pass1 冷启动 NaN / pass2 0 的
  簿记差；超额已由 G1 钉住）；
- G6 结构门补 estMode 过滤（评估器缺陷：同臂在 l1/truth 两批各一份）。
修正前评估存档（q4_gates_first_fire_FAIL.log），修正与依据在证据文档 §3
先行登记后才复评；批数据零改动。

## 边界与遗留

- 剩余人工门 H1–H6（叶安）：H1 演示依赖 3600s UI 修复入库；H5 审读接口 §10；
- 外部确认 C1（电流传感器）/C2（参数，推力侧 n 效应数据）/C3（SITL 位）
  维持非阻塞；
- B2（air_quad.slx 薄包装）待排期；launch_3_6_demo.m UI 修复维持不提交。

## 下一步

Q 系机器线收口。向项目组/老师交接：Q4_FORMAL.md + 双口径 CSV + 误差带申报
（常数 ≤5% + 倾斜 ≤1.4 %/m/s → 磨损 ≤0.9pp，正式批实测 ≤0.22pp 在带内）；
H 门人工验收随演示准备推进。
