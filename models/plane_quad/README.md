# models/plane_quad：四旋翼双轨对象（Q2 轨 A + 轨 B）

> 状态：**轨 A + 轨 B（MATLAB 权威链）交付，M4' 对拍门通过**；**建模调整 P0/P1 落地（2026-10-11，工作簿三套 baseline 参数包 + 冒烟 3/3 PASS）**；**P2 控制现实性关闭（2026-10-11，现实性链+时延×饱和×噪声磨损表全门 PASS）**；**P3 算法验证交付（2026-10-14 G-P4 修复两轮复评 G-P0–G-P4 全门槛 PASS + vi 测量档复评全 PASS，见方案 §4.4/§4.6/§4.7/§4.8）**；**P4 薄包装收尾（2026-10-13，air_quad.slx + 商飞 0xF2 接口位，冒烟全过）；R8 接口三裁决落实（2026-10-14，叶安：校验和累加和/油门两组均值+主母线/**加电流采样器**——P̂=V·I 测量主档 `est_model='vi'`，l1/l0 降级链），`docs/AIR_QUAD_INTERFACE.md` 已审查**。
> 方案：[`docs/QUAD_MIGRATION_PLAN_20260921.md`](../docs/QUAD_MIGRATION_PLAN_20260921.md) §4-Q2；建模调整期按 [`docs/QUAD_SIM_MODEL_PLAN_20261011.md`](../docs/QUAD_SIM_MODEL_PLAN_20261011.md)（含妥协登记 C1–C9）。
> 口径：默认配置维持 **quad_placeholder（P4）** 占位（Q2 证据可复现）；工作簿机型走 `quad_sim.baseline('bg'/'b40'/'b42')` opt-in（workbook_baseline_20261011，非老师参数，不可外引为真实结论）。

## 问题

载具从四轴八旋翼换为四轴四旋翼（老师要求，重心不在转速比优化）。双轨制（D2）：
轨 A = MATLAB 降阶链（算法线日常实验，迭代快）；轨 B = 油门正向权威链（x8phys
结构 + 台架标定 + 自带飞控）；两轨以 M4' 对拍门绑定（准稳态 ≤1.5%、就位比 ≤2×）。

## 轨 A：+plane_quad（降阶链）

`plane.step`（P2，冻结）骨架复用，仅两处差异：4 电机单桨（无上下桨分配/共轴干扰，
参数键不存在，M3 扫描门）；eta 恒 1（接口字段保留、值强制 1）。其余（H6/H3/H4/H9/
电池链/字段名/因果序）与 P2 逐位同式；标定从冻结源只读；`steady_curve` 供 M4' 基线。

## 轨 B：+quad_sim（油门正向权威链）

x8phys 结构（冻结只读移植）：PWM→throttle→ω_target=throttle·KV_eff·V̂（电压耦合
固定点）→一阶电机滞后 τ→推力/力矩→NED/FRD 四元数刚体→逐轴废阻→电池链；标定换
MN1005 台架 T(n)/P(n;V)/H3（替代 x8phys 代理系数）；`ctrl` = v_ref→4×PWM 薄内环
（H6 型前向 + 垂直阻尼 + 姿态 PD + 混控，传感器集 = 实机 FC 可观测量）；电气记账
与轨 A 同口径（废阻功计电功率）；J² 前进比功率项为声明级旋钮（对拍模式置 0）。

## 入口

```matlab
cd models/plane_quad
run_quad_checks       % 轨 A: 单元门 M2/M3 + 稳态配平表
run_quad_sim_checks   % 轨 B: 单元门 + M4' 对拍表 + n 效应 + 就位比
launch_quad_demo      % 展示面板(演示层, v4=老 3.6 面板骨架逐项同构+增量绘图)
run_quad_demo_smoke   % 面板开发级冒烟(S-D1–S-D5)
```

面板口径（黑箱红线）：`launch_quad_demo` 仅供演示，**不作可引用数据源**——
数字口径以 [`docs/evidence`](../docs/evidence/) 证据 CSV 为准。演示链 =
`air_quad_tick`（P4 薄包装）逐步推进，臂 = `p3_arm` 策略句柄（白名单信息面），
P(v) 曲线加载 E1 证据 CSV 不重算；估计档可切 vi/l1/l0（R8 降级链演示）。
面板 v4（2026-10-15）：布局与运行模型整体回贴老 UI（模块切换/滚动表单/操作钮
3 行/6 行评价卡/resizeLayout 动态配平），绘图=setupPanels 一次建图元 + 每帧
只推 XData/YData（热态一拍 30 步+重绘 43.5 ms）；smoke S-D1–S-D5 全过。

## 验收（2026-09-21，证据 [q2_track_a](../docs/evidence/quad_migration/q2_track_a/) / [q2_track_b](../docs/evidence/quad_migration/q2_track_b/)）

- 轨 A 单元门 **8/8**（M2 物理不变量全项 + M3 清除扫描/行为锚点）；锚点：悬停 615 W、谷底 5.65 m/s（k=9.91）、悬停 H9 裕度 20.8%；
- 轨 B 单元门 **7/7**；**M4' 对拍 6 点 0.009–0.36%**（门 ≤1.5%）、**就位比 0.92**（B 10.75 s / A 11.70 s，门 ≤2×）；
- **n 效应复核（功率侧）**：Jgain=3 下 P̂_L0 全程平坦（极差 <1%）——L0 盲性在轨 B 独立结构复现（D1 升 L1 加固）；bias 驼峰 +19.9%（谷区）→ −9.5%（高速）；J² 把真谷底压到 5.00 m/s。推力侧 n 效应（pwm 携带空速信息的唯一通路）无数据，待老师参数（C2）；
- **t_dwell 定稿**：电机贡献 4τ = 0.32 s，接口"≥2 s（以就位带为准）"覆盖充足；
- 轨 B 调试入档两项结构发现：垂直通道符号（az_fb=+kvz·vz）与电气记账口径（废阻功须计电功率，x8phys 原口径高速端差 33%）。

## 局限

- 占位参数待老师交付（换参 = config 覆盖 + 重跑入口，H4 演练门）；
- B2 已交付（2026-10-13）：air_quad.slx 薄包装 + 0xF2 组帧接口位；既有 .slx
  零触碰；接口审查已闭环（R8 三裁决 2026-10-14，[`docs/AIR_QUAD_INTERFACE.md`](../docs/AIR_QUAD_INTERFACE.md) §5.1）；
  电流采样器规格/质量待老师确认（≥50 g 级需同步 R2 BOM 与 b40 质量）；
- Q1 结论在本模块加固：谷由 H3 创造、纯静态 L0 盲——估计链按 D1 用 L1 档；
- P3 G-P4 已按登记两轮修复关闭（2026-10-14 全门槛 PASS：锚定选谷+邻域钳位+
  曲率门槛+探针边界防退化，`p3_arm`/`p3_opt`/方案 §4.6–4.7）；多臂适配按序最后。

## 署名

实现：叶安（ZCode 协助，2026-09-21）；上游 P2/x8phys 链：平台线既有成果（冻结只读）。

