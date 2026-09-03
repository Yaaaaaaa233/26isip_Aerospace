# Plane P0--P4 统一物理对象

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：待组内确认
主要撰写：Codex（按 2026-09-02 架构基线实现）
技术贡献：沿用 `models/px4_x8` 已核验参数与 `modules/wind_field_sched` 空速关系
审核：待项目组审核、待指导教师确认
AI协助：Codex

本目录实现路线图 P0--P4 的独立 MATLAB Plane 代理。`plane.step(state, windSample, pathCommand, controlCommand, dt, config)` 分别接收对象侧允许读取的 `WindSample.wind_truth_ne_mps`、Scenario/Path 生成的 `PathCommand` 和已安全门控的 `ControlCommand`（`v_ref_applied_mps`、`eta_ref_applied`），输出公共字典 0.3 定义的 `PlaneState` 字段及代理诊断：地速/空速、位置、圆周向心需求、姿态代理、联合功率、电池、累计能量和约束标志。测量风只属于控制器可见上下文，不驱动物理对象，轨迹字段不再混入 WindSample。

当前证据等级为 E0/E1 代理，`power_source=proxy`：功率模型和电池参数未校准，`motor_pwm_us`/`motor_rpm` 在该统一代理中暂以 `NaN +` 非直接执行器有效语义保留；PX4 M2 的 PWM/RPM 适配仍通过 `models/px4_x8/+x8phys` 与后续 P4 接入完成。不得据此宣称真实节能、续航或飞行安全。

运行：

```matlab
addpath('models/plane')
result = run_plane_acceptance()
```

测试覆盖零风空地速一致性、风速符号、速度/转速比限速、联合功率随风变化、累计能量和 SOC 消耗。
