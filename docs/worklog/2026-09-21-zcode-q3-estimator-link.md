# 2026-09-21 ZCode（叶安线）：Q3 估计链接入与联调（platform_link_39，L1 档）

## 任务与边界

按 [`QUAD_MIGRATION_PLAN_20260921.md`](../../QUAD_MIGRATION_PLAN_20260921.md) §4-Q3 执行：
L1 估计器（D1 决策：L0 + 气速修正）接入 `platform_link_39` 测量链、M7 双口径记账层、
接口文档驻留/P̂/双口径增补（H5 待审）、X8 冻结回归（P5/M8）。
红线照旧：`models/plane`、`modules/platform_link{,_37,_38}`、全部 `.slx`、既有证据
零触碰；全部结论为 X8 占位管线口径（P4）。

## 交付

- `+q39/est_l1.m`：L1 = L0 + 声明系数气速修正（dH3/dH5/dDrag/aux，与 trim_curve
  离线分解逐项同型）；`decl` 覆盖参数（Q4 降档敏感性用，未知字段拒绝）；
- `+q39/make_platform_plant_l0.m`：`estMode='l1'` 分支；û̂ = |(测量地速 − 风测量)·切向|
  只用测量面字段（因果红线，结构门 + 文本门双保险）；真值列零改动；
- `+q39/m7_metrics.m` / `m7_rows.m` / `run_q3_smoke.m`：M7 双口径记账
  （true/est/diff 三行展开，幂等断点续跑，openloop 双口径锚点 `q3_anchor.csv`）；
- `tests_q3.m` + `run_q3_checks.m`：单元门 8/8；
- `docs/interfaces/SIM_ALGO_INTERFACE.md` §10 增补（10.1 t_dwell ≥2s 驻留语义与
  "对外合同=驻留"；10.2 P̂ 估计口径语义；10.3 双口径记账），标记 Proposed 待 H5。

## 关键数字（证据：docs/evidence/quad_migration/q3_integration/）

- 单元门 8/8：L1 自洽 1e-12；悬停域 L1=L0+aux 精确；配平域闭合 ≤1e-9
  （vStar=5.150/Pmin=355.2W/k=9.56 与 Q1 归档一致）；植物级 l1 尾偏差 ≤2%（门）
  vs l0 ≈7.0%；M7 恒等式；l1 两遍逐位；因果结构门。
- 冒烟 3600s×4 臂（seed 11 复合风，l1 口径）全 rc=0：
  sweepcal 3.9243%（赢面 +2.34pp）、purerl_off 0.8476%（+5.42pp）、
  purerl_on 0.5956%（+5.67pp）、openloop 6.2643%（参照）；
  **双口径漂移 |Δ超额| ≤0.029pp、|Δ赢面| ≤0.041pp**；
- 恢复性（vs Q1 归档）：sweepcal 赢面 l0 −11.65pp（崩溃）→ **l1 +2.34pp**
  （真值链锚点 +2.24pp，同水平）；purerl 两臂磨损 ≤0.39pp（< M6 1pp）；
  openloop 真值超额与 Q1 ANCHOR 逐位一致（植物零改动直接证据）；
- X8 回归：52/52 + 20/20 不动（详见证据 §4）。

## 调试勘误（全部被门拦住，无一静默）

1. **v_air 符号错**：û̂ 合成初版写成 `地速 + 风测量`，违反接口 §6 全仓减号约定
   （v_air = v_ground − wind）；L1 过修正、植物级偏差 10.9% 反超 l0 的 7.0%，
   被新加的接线门/对照门当场拦截。修正 + 因果结构门改为钉住测量赋值行
   （初版 regex 命中的是 `lastUhat = 0` 初始化行）。
2. **m7_rows struct 陷阱**：`struct()` 数值数组字段整体复制进每个元素
   （与已知的空 cell→0×0 陷阱同族），每元素标量必须 cell 包装。
3. 小项：R2022b 无 `verifyNumel`（改 `verifyEqual(numel(...))`）；
   est_l1 注释含 `air_velocity` 字面量触发自家文本因果门（改措辞）。

## 边界与遗留

- 声明系数 = 配置自身（声明上界档）；decl 降档扫描留 Q4 前决定；
- ŵ 反馈闭环稳定性论证不在本链（平台链风测量全量可见），实机传感器集另列；
- 推力侧 n 效应待 C2（沿用 Q2 轨 B 声明）；B2（air_quad.slx 薄包装）仍未启动；
- launch_3_6_demo.m 3600s UI 修复维持不提交（叶安指示）。

## 下一步

Q4 正式验收批（9000s ×2 逐位确定、五臂、全学习臂优于开环、赢面磨损 ≤1pp，
**必须跑在 L1 口径**——本批 M7 层与 `m7_rows` 直接复用）+ H1–H6 人工门 + 收口；
B2 薄包装可并行排期。
