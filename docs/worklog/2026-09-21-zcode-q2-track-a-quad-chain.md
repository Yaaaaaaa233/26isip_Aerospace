# worklog 2026-09-21：ZCode（叶安）——Q2 轨 A 四旋翼降阶链

对应方案：[`QUAD_MIGRATION_PLAN_20260921.md`](../QUAD_MIGRATION_PLAN_20260921.md) §4-Q2 / §5-M2·M3。
上游：同日 Q0（dd9ff2a）、Q1（d44314b）。下游：Q2 轨 B（Simulink）+ M4' 对拍、Q3。

## 做了什么

1. **`models/plane_quad/`（+plane_quad 包）**：`plane.step`（P2 冻结）骨架复用的四旋翼降阶链：
   - config/step/reset：与 P2 的差异仅两条——4 电机单桨（T_i=T_need/4 各自受 T_ce(V) 封顶，
     无上下桨分配/共轴干扰项，参数键不存在）与 eta 恒 1（接口字段保留、值强制 1、无状态动态）；
   - 标定从冻结 `models/plane/data/calibration/` 只读加载（单一事实源）；
   - `power_source='quad_placeholder'` + config 占位声明（P4）；
   - `steady_curve`：无风配平稳态 P(v) 解析曲线（M4' 轨 A 侧基线）。
2. **单元门 M2/M3（tests_quad，8/8）**：悬停恒等式（reset dt=0 采样拍逐位口径，≤1e-12，
   且 4 电机严格对称）、能量积分 ≤1e-12、V·I=P ≤1e-12、H9 触发位 + T_act=4·Tce·g 封顶
   恒等式、SOC 耗尽截止行为；M3 静态扫描（包内零禁用词）+ 行为锚点（诊断长度 4、无上/下
   桨字段、eta=1.2 指令被强制 1）；附 PWM 诊断与 Q1 L0 反解口径互逆（Q3 预铺）。
3. **M4' 轨 A 侧基线**：5 电压档（19.6–29.4V）× 8 配平点（0–12 m/s）= 40 行稳态表 +
   满电细步曲线，落 `results/` 并归档证据目录。低电压档为 H9 封顶运行（sat_margin=0 明示），
   轨 B 对拍只取非饱和行。
4. **轨 A 锚点（满电）**：悬停 615.0 W（4×台架 P(n(2.5 kgf))+30 aux）、稳态谷底 5.65 m/s
   @ 469.7 W（谷深 23.6%）、k=9.91 W/(m/s)²、悬停 H9 裕度 20.8%（T_h=2.5 vs Tce=3.158 kgf）
   ——10 kg 占位质量悬停可行，低电压窗进入饱和域属预期物理。

## 调试记录（开批前修掉）

- H9 触发测试初版用 voltage_v 覆盖注入低电压——电池链每拍从 OCV(SOC) 重算端电压，覆盖一拍
  后即被拉回，饱和不持续；改为 az_cmd_mps2=3 过载在满电下直接推过 T_ce（更贴 H9 的物理语义）；
- M3 静态扫描初版扫到测试文件自身 + config 注释含禁用词——扫描域改为 +plane_quad 包目录，
  注释改写，测试内敏感词用字符串拼接避免自含；
- 行为锚点的 up/lo 子串检查误中 `velocity` 内的 'lo'——改为词元边界正则匹配。

## 勘误（同批入档）

Q1 证据文档 §1 的 X8 谷深初版误写 7.6%；按归档 `q1_trim_curve.csv`（P(0)=464.62 W）与
checks.log（Pmin=355.2 W）更正为 **23.5%**。S2/S3 等结论均用赢面/超额差值，不依赖该数，
结论不变。

## 边界

- quad_placeholder（P4）：10 kg/MN1005/40 寸桨/7S4P 全部占位，换参路径 = config name/value
  覆盖 + 重跑 run_quad_checks（H4 演练门的对象）；
- 轨 A 的谷同样由 H3 创造——Q1"L0 不可部署、升 L1"结论直接适用于本链；
- 冻结零改动：`models/plane`、`modules/platform_link*`、全部既有 `.slx` 与证据；
- 轨 B（Simulink 油门正向 + 一阶电机动态 + 四元数刚体）与 M4' 对拍门（≤1.5%/≤2×）待后续；
  轨 B 同时承载 Q1 遗留的 n 效应复核（L0 在完整桨气动下是否保留谷）与 t_dwell 复测。
