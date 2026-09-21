# Q2 轨 A：四旋翼降阶链（models/plane_quad）——交付与机器门结果

日期：2026-09-21 ｜ 执行：叶安（ZCode 协助） ｜ 对象：[`models/plane_quad`](../../../models/plane_quad/)
方案：[`QUAD_MIGRATION_PLAN_20260921.md`](../../QUAD_MIGRATION_PLAN_20260921.md) §4-Q2 / §5-M2·M3（M4' 待轨 B）
状态：**轨 A 完成（quad_placeholder 占位口径）**。全部数字挂 P4 占位等级，老师参数到位前**不得引用为四旋翼真实节能/实飞结论**。

## 0. 交付内容

- `+plane_quad/config.m / step.m / reset.m / steady_curve.m`：`plane.step`（P2，冻结零改动）骨架复用的四旋翼降阶链。与 P2 的全部差异：
  1. **4 电机单桨**：T_i = T_need/4 各自受 T_ce(V) 封顶；无上下桨分配、无 H5 干扰项（对应参数键不存在）；
  2. **eta 恒 1**：接口字段保留（`command.eta_ref_applied` 仍必填），值强制 1，状态无 eta 动态；
  3. 台架/电池标定从冻结的 `models/plane/data/calibration/` **只读加载**（单一事实源，不复制）；
  4. `power_source='quad_placeholder'` + config 占位声明字段（P4）。
- 保留：H6 俯仰内核 / H3 前飞诱导节省 / H4 废阻 / H9 涌现转速上限 / battery_model_v1 电池链 / 全部输出字段名与因果次序（与 P2 逐位可对拍）。
- 入口：`cd models/plane_quad && run_quad_checks`（单元门 + 稳态表）。

## 1. 机器门结果

| 门 | 内容 | 结果 |
|---|---|---|
| M2 | 悬停恒等式（4×单桨台架悬停，reset dt=0 采样拍逐位口径） | ✅ ≤1e-12；且 4 电机功率严格相等 |
| M2 | 能量积分 ΣP·dt vs 累计记账 | ✅ ≤1e-12 |
| M2 | 功率平衡 V·I=P（电池链构造式） | ✅ ≤1e-12（对标 x8phys 2.01e-16 先例量级） |
| M2 | H9 电压跌落上限触发位 | ✅ az=3 m/s² 过载下 rpm_saturation=true 且 T_act=4·Tce(V)·g 封顶恒等式（≤1e-9 N） |
| M2 | 截止行为 | ✅ SOC 耗尽 → cutoff、power=0、V=cutoff_V、aKin=−1 |
| M3 | 静态扫描（+plane_quad 包无禁用词引用） | ✅ 4 个源文件零命中 |
| M3 | 行为锚点（无上下桨成对字段、诊断长度=4、eta 恒 1） | ✅ 指令 eta=1.2 被强制 1 |
| 附 | PWM 诊断派生式与 Q1 L0 反解口径互逆（Q3 预铺） | ✅ ≤1e-9（非饱和域） |

单元测试 8/8（`checks.log`）。

## 2. 轨 A 锚点（满电 29.40 V，quad_placeholder 占位）

| 量 | 值 | 备注 |
|---|---|---|
| 悬停功率 | **615.0 W** | = 4×台架 P(n(2.5 kgf)) + 30 W aux（每电机 2.5 kgf） |
| 稳态谷底 | **5.65 m/s @ 469.7 W** | 谷深 23.6%（X8：5.15 m/s @ 355.2 W，谷深 23.5%） |
| 谷底曲率 k | **9.91 W/(m/s)²** | X8 为 9.56——Q1 的倾斜敏感性结论量级可迁移 |
| 悬停 H9 裕度 | **20.8%**（2.5 vs 3.158 kgf） | 10 kg 占位质量悬停可行；低电压窗将进入饱和域（表内 sat_margin 列明示） |

配平基线表（M4' 轨 A 侧）：5 电压档（19.6–29.4 V）× 8 配平点（0–12 m/s）= 40 行（`quad_steady_table.csv`）+ 满电细步曲线（`quad_steady_curve_fullV.csv`）。低电压档为 H9 封顶运行（sat_margin=0），非真实配平——轨 B 对拍只取非饱和行。

## 3. 与 Q1 结论的衔接

- 轨 A 的谷同样**由 H3 创造**（纯台架静态映射无谷）——Q1 的"L0 不可部署、升 L1"结论**直接适用于轨 A 四旋翼**；L0-on-quad 的定量敏感性留 Q3/Q4 批。
- 谷底曲率 k=9.91 ≈ X8 的 9.56：Q1 误差带草案（常数 ≤5% + 倾斜 ≤1.4 %/m/s）在四旋翼上的量级预计不变，Q4 正式批复核。

## 4. 边界

- 占位参数（10 kg 整机 / MN1005 / 40 寸桨 / 7S4P）待老师参数替换（H4 换参演练门）；换参 = `plane_quad.config` name/value 覆盖 + 重跑本入口，无返工路径；
- M4' 双轨对拍门待轨 B（Simulink，油门正向 + 一阶电机动态 + 四元数刚体）就绪后执行：判据 ≥5 配平点准稳态 P(v) 相对差 ≤1.5%、就位时间比 ≤2×（只用非饱和行）；
- 与 P2 的差异仅为上述两条（拓扑与 eta）；任何其他数值差异 = 实现 bug（对拍原则）。

## 5. 文件清单

- `checks.log` —— 单元门 8/8 输出与轨 A 锚点打印
- `quad_steady_table.csv` —— M4' 轨 A 侧配平基线（5 V × 8 v）
- `quad_steady_curve_fullV.csv` —— 满电细步稳态曲线（0:0.05:14）
