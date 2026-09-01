# M0-A 观测与接口现状

状态：**M0-A 已完成并通过验收（2026-08-31）**。开发模型 `models/px4_x8/air_spare.slx`，验收快照 `models/px4_x8/air_m0a.slx`。这份文件定义当前可安全使用的观测量；它不把估算量误称为实测量。

| 字段 | 单位 | 来源 | 状态与限制 |
|---|---:|---|---|
| `t` | s | Simulink `tout` | 可用 |
| `m0a_Ve_inertial_mps` | m/s, 3 元向量 | 6DOF `Ve` 输出 | 可用，惯性坐标速度 |
| `m0a_horizontal_speed_mps` | m/s | `sqrt(Ve_x^2 + Ve_y^2)` | 可用；无风条件下的地速代理，不是空速 |
| `m0a_motor_pwm_us` | us, 8 元向量 | `AttitudeControl/Demux` 的最终 PWM 支路 | 可用；uint16 量化命令 @1 kHz |
| `m0a_motor_rpm_est` | rpm, 8 元向量 | Subtract+Gain 逐元素链 | 可用但仅为估算；`rpm=(PWM_us-1000)*60/(2*pi)` 命令转速（原 Fcn 形式只能输出标量，已修正为 8 维） |
| `m0a_P_est_W` | W | `M0A Power Measurement` 子系统 | 可用；`P_est=C_M·Σω³`，`ω=clip(PWM,1000,2000)-1000`，`C_M=2.51e-7` 与植株扭矩系数同源；从植株实际消费的根级 PWM 指令网（未量化、250 Hz）分支，250 Hz 更新 |
| `m0a_E_est_J` | J | `P_est` 的连续积分 | 可用；10 s 能量与均值功率×时长相对误差 4e-8 |
| `m0a_power_source` | 枚举 | 常量 0 | 0=estimated；日后替换实测/校准源时改 1 |
| `m0a_log_bus` | 35 元向量 @1 ms | 根层 Mux | `[v, P_est, E_est, power_source, att(6)=φθψ pqr, pwm(8), rpm_est(8), flags(8), optimizer_enable]`；4 ms 的 pwm/P_est 经 ZOH 对齐 |
| `m0a_constraint_flags` | 8 位 0/1 | `M0A Constraint Flags` 子系统输出，经 `M0B Flags Override` 覆盖位 3/5 后对外 | 可用；M0-B 起位 3/5 由运行时常量重算（`M0B Att Tol` 0.523 rad、`M0B Speed Tol` 1.0 m/s，位 5 语义 `|v−v_ref(延迟一拍)|>tol`）；其余位沿用原阈值：偏航率 1.5 rad/s、功率上限 1500 W、PWM 边界 5 us |
| `m0a_optimizer_enable` | 0/1 | 常量 0 | 固定基线模式；M0-B 起接入参考选择器 |
| `eta_ref`、实际 `eta` | -- | 待建 X8 受约束分配器/RPM 接口 | 缺失（M2） |

姿态与角速度来源：`Attitude Control/quat2eul` 三输出（φ、θ、ψ）与 `AttitudeControl` 内 `control_and_mix` 第 5 输入口 `pqr`（按已核验函数签名 `(phi, theta, roll_pitch, yaw, pqr, Thrust, dt, arm)` 顺序）。

验收证据：`air` 与 `air_spare` 在相同 10 s 场景下 `pwm_cmd`/`Ve`/`quat` 逐样本最大绝对差为 0（`docs/evidence/air_m0a_baseline_compare_20260831_201430.csv`）；名义运行初始化窗（t<5 ms，根级 PWM 网固有输出 0）后除速度失跟标志（占位 `v_ref=0` 语义，飞机实际飞行约 8.4 m/s）外全部为零。

## 不变约束

1. 观测支路不能断开或替换原有姿态控制、解锁、混控和动力学连线。
2. 慢层优化器只可输出 `v_ref`（M0 起）和 `eta_ref`（M2 起），不直接输出 8 路 PWM。
3. 每次优化试验必须与 `optimizer_enable=0` 的同条件固定参考基线配对。
4. 数据源必须显式标注为 `estimated` 或 `measured`。未校准的 `P_est` 只用于模型内部对照，不得报告真实节能率。

M0-B（速度闭环与安全回退）与 M0-C（速度在线 ESC 接入）均已完成；接口分别见 [`M0B_SPEED_LOOP.md`](M0B_SPEED_LOOP.md) 和 [`M0C_SPEED_ESC.md`](M0C_SPEED_ESC.md)。注意 M0-B 起 `Attitude Control` 新增输入 13/14（`m0b_pitch_cmd`、`m0b_speed_loop_enable`），`Subsystem` 新增出口 9（`Ve_x`）。当前下一步按 [`PROJECT_EXECUTION_ROADMAP.md`](../PROJECT_EXECUTION_ROADMAP.md) 进入 M1 扰动、噪声与时延鲁棒性。
