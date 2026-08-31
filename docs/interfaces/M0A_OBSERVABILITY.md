# M0-A 观测与接口现状

状态：部分完成，模型快照为 `models/px4_x8/air_spare.slx`。这份文件定义当前可安全使用的观测量，以及仍然缺失的接口；它不把估算量误称为实测量。

| 字段 | 单位 | 来源 | 状态与限制 |
|---|---:|---|---|
| `t` | s | Simulink `tout` | 可用 |
| `m0a_Ve_inertial_mps` | m/s, 3 元向量 | 6DOF `Ve` 输出 | 可用，惯性坐标速度 |
| `m0a_horizontal_speed_mps` | m/s | `sqrt(Ve_x^2 + Ve_y^2)` | 可用；无风条件下的地速代理，不是空速 |
| `m0a_motor_pwm_us` | us, 8 元向量 | `AttitudeControl/Demux` 的最终 PWM 支路 | 可用；为最终执行器命令 |
| `m0a_motor_rpm_est` | rpm, 8 元向量 | 当前植株的 PWM 至角速度映射 | 可用但仅为估算；`rpm=(PWM_us-1000)*60/(2*pi)` |
| `P_est`、`E_est` | W、J | 待建 `Power Measurement` 子系统 | 缺失；不能计算或报告节能率 |
| `constraint_flags` | 布尔总线 | 待建安全监视器 | 缺失 |
| `eta_ref`、实际 `eta` | -- | 待建 X8 受约束分配器/RPM 接口 | 缺失 |

## 不变约束

1. 观测支路不能断开或替换原有姿态控制、解锁、混控和动力学连线。
2. 慢层优化器只可输出 `v_ref`（M0 起）和 `eta_ref`（M2 起），不直接输出 8 路 PWM。
3. 每次优化试验必须与 `optimizer_enable=0` 的同条件固定参考基线配对。
4. 数据源必须显式标注为 `estimated` 或 `measured`。未校准的 `P_est` 只用于模型内部对照。

下一步按 [`PROJECT_EXECUTION_ROADMAP.md`](PROJECT_EXECUTION_ROADMAP.md) 的 M0-A 项 3--5 完成。
