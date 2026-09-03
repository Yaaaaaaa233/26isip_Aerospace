# 2026-09-03 ZCode：M3 实施（B–E 组）与配对批次

日期：2026-09-03
执行：ZCode（叶安代理，平台线）
审核：待项目组审核
AI协助：ZCode（实现、执行与本文档代拟）

## 本次做了什么

- 叶安授权开工 M3（"按照之前的方案，开始做M3吧"），按设计评审 §4 顺序 A→E 执行（A 组文档层已于 v0.2 完成）。
- **B 组**：实现 `m3_schedule.m`（纯函数 + 10 类配置负向 + fail loud）、`m3_arb_config.m`、`m3_validate_channels.m`（单侧 m3 拒收）、两个适配器 `case 'm3'`（fixed/esc 分支逐字不动；hold 同步 `lastReference=center` 并显式置 warmup）；`test_m3_coordination_unit.m` B1–B6 全 PASS（F1 核心用例、66 s 相位续跑、门控矩阵 20/20、二维玩具收敛、会话隔离含错误路径、叛徒适配器拒收、并发串扰对照、五类评价 fixture）。
- **C 组**：`run_air_m3_boundary.m` BN/BD 双运行 PASS——eta 候选 hold 段精确恒定、v 施加值逐段恒定、起飞判据构成真实 invalid 恢复、19 个出带窗口逐窗列原因。
- **D 组**：m0a 旁路四信号差 0、m0b 注入 4/4、m0c trials 9 场景（复现差 0）、m2 trials nominal（数值与 M2 放行一致，±0.015 pp 内）。
- **E 组**：`run_air_m3_trials.m` 13 场景配对矩阵，三段执行全 PASS；M3-R1 复现逐位差 0；各名义臂对 B1 −0.28~−0.31%、对 B2 |Δ|≤0.003%（平坦 v 面上 M3≈eta 单变量贡献的预测精确吻合）、v 跟踪 0.0097 vs B1 0.198。
- 证据 `docs/evidence/M3_COORDINATION_20260903.md`、本文档、状态页/README 回填。

## 关键决策

- **增益标定（§2.5 预授权）**：段 2 初跑发现 1e-4 下槽化收敛差 0.5–0.9 pp（各槽 warmup 重启使 M3 比连续慢 3–4%，连续 B2 同期 0.992/1.009 恰好压线）。按 §2.5"槽化占空比复核后冻结"把 M3 模型集 eta gain 冻结 2e-4（标定三门槛全过有余量）；标定运行与失败运行为标定证据，正式批次全新执行；门槛未动。M2 既有集 1e-4 不变（B2 基线臂即 M2 语义）。
- **warmup 语义精确化（M3-I1）**：v0.2 假设 `reinitialize` 标志足以表达 hold 的滤波冻结，但首个 hold 段可能在内核取得有效步之前到达（启动 invalid 消费 warmup）——hold 步显式置 `warmup=80`，文档 §2.1 已改写。
- **hold 恒定判据按段不按槽对**：v 中心可在两个 hold 段之间合法变化（交替搜索的意义），逐段断言恒定。
- 正式批次三段执行规避 R2022b 堆限制，跨段配对经归档基线加载（R1/N5 复现对按设计同段）。

## 遗留问题 / 风险

- M3-I3 试验脚本三处基础设施 bug（cell 列迭代、连字符字段名、numel 作用矩阵）在段 2/3 初跑暴露后修复；正式数据全部为修复后全新执行。
- 全量 13 场景同会话单进程链未执行；跨会话 ulp 抖动未新增数据（M2 先例沿用，裕量两个数量级）。
- V1 限制沿用（sat 不送达 v 在线门、位 5 离线、v 候选经施加通道间接验证）。
- 统一 Plane 复跑（R4）未开始；本批次不构成 R4 放行。§9 五项的项目组追认仍待补（实施按默认执行已记录于 v0.2）。

## 下一步

- 项目组追认 §9 五项（按已执行默认）→ M3 代理阶段收口；
- Plane P4 适配器通过后：Plane API 接入 `air_spare.slx` → M0/M2 基线回归 → M3 同 Plane 复跑（R4 终验）。

## 验收状态

- B/C/D/E 全 PASS（证据 `docs/evidence/M3_COORDINATION_20260903.md`，含四层判定与归档索引）；
- 零 `.slx` 结构变更；四个配置全局量快照/恢复含错误路径；`M3_ARB_PARAMS` 已于 rules §7 登记。

## 追加（同日）：与霍奕茗 x8phys PR 的并发合并

- 提交 93b1b68 推送时发现远端已被 `570c846`（GitHub PR #1，霍奕茗 `codex/x8phys-physics-audit`）占据：该分支自 `e5d5745`（B 组之后）拉出，早于我 C–E 提交，合并时其树不含 M3 C–E 成果（试验脚本、证据、worklog、文档修正段）。Yaaaaaaa233 远端已收 93b1b68，Zhoucmd6 拒收。
- 核实 x8phys 分支对 `m2_eta_esc`/`m0c_vref_esc`/调度与 M3 代码零 diff（真交叠仅文档），执行内容级合并 `1c5462a`：双方成果全部保留（M3 warmup 修正/2e-4 冻结/证据 + x8phys `+x8phys`、`models/plane`、P0–P4 契约、X8PHYS 证据）。
- 合并树重验：`test_m3_coordination_unit`、`test_m0c_esc_unit`、`test_m2_eta_esc_unit`、`run_air_m0a_baseline_compare`（旁路差 0）全 PASS。
- 影响：Plane 线进度超预期——`models/plane` P0 静推拟合与 P1–P4 契约已通过，`+x8phys` 提供 PX4 PWM 兼容对象；M3 的 R4 终验前置（Plane 接入 `air_spare.slx`）比计划更近。
- 教训登记：两人同日并行大提交且远端走 PR 合并时，推送前必须 fetch 检查；本次为无损恢复，未 force-push。
