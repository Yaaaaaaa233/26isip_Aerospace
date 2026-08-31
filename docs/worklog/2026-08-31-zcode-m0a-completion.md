# 2026-08-31 ZCode M0-A 完成与验收

## 本次做了什么

- 在本机 MATLAB R2022b 批处理模式下完成 M0-A 剩余三项交付，全部只修改 `air_spare.slx`，原快层控制连线未动：
  - 新增可替换 `M0A Power Measurement` 子系统：从植株实际消费的根级 PWM 指令网（`Attitude Control` 输出 2，未量化、250 Hz）分支，输出 `m0a_P_est_W`、`m0a_E_est_J`（积分）与 `m0a_power_source`（0=estimated）。
  - 新增 `M0A Constraint Flags`（8 位：PWM/RPM 饱和、姿态、偏航率、速度失跟、功率异常、信号缺失、预留；阈值均为文档化占位值）与 35 维统一日志总线 `m0a_log_bus` @1 ms（4 ms 的 pwm/P_est 经 ZOH 对齐），以及 `m0a_optimizer_enable=0` 固定基线配置；场景配置归档 `results/m0a_config/`。
  - 新增姿态/角速度观测出口：`Attitude Control/quat2eul` 三输出与 `AttitudeControl` 内 `control_and_mix` 第 5 输入口 `pqr`（按已核验签名顺序），经新增包装层出口引至根层。
- 验收：新增 `run_air_m0a_baseline_compare.m`，对 `air` 与 `air_spare` 以相同 10 s 场景比对 `pwm_cmd`/`Ve`/`quat`（内存临时信号日志，不落盘改模型）。**三信号逐样本最大绝对差均为 0**；日志总线 35×10001、`E_est` 与均值功率×10 s 相对误差 3.98e-8；初始化窗（t<5 ms）后仅速度失跟标志按占位 `v_ref=0` 语义激活。验收归档 `results/air_m0a_baseline_compare/20260831_201430/`。
- 按路线图 §7 另存稳定快照 `air_m0a.slx`；更新路线图、M0-A 接口文档、工作区清单与开发状态。

## 关键决策与理由

- `P_est = C_M·Σω³`（`ω=clip(PWM,1000,2000)-1000`，`C_M=2.51e-7`）：与植株 `chart_14` 的扭矩系数严格同源，物理上即 `ΣQ_i·ω_i`；与独立重算最大偏差 5.7e-14 W。明确标注 estimated/未校准。
- 功率取自根级未量化指令网而非内部 uint16 量化日志：植株消费的就是前者（两者最大差 1 us，为量化误差）。
- 发现并修正 rpm 派生的宽度缺陷：Fcn 块只能输出标量，总线级与执行器级两处均替换为逐元素 Subtract+Gain，`m0a_motor_rpm_est` 现为真正的 8 维（与 `9.5493·(pwm-1000)` 零误差）。
- 根级 PWM 网在 t=0 输出 0 为 `air` 固有行为（包装层滞后一拍），不人为掩盖：验收把 t<5 ms 作为初始化窗，标志语义保持真实。
- 速度失跟标志在名义飞行中激活是正确语义（占位 `v_ref=0`，飞机实际约 8.4 m/s），M0-B 建立速度通道后该校准。

## 遗留问题 / 风险

- `pqr` 分支按 `control_and_mix` 函数签名顺序取第 5 口；悬停段 φ 与 p 同相（±0.207 rad / ±0.206 rad/s）量级合理，但未做独立解析验证。
- 阈值（姿态 0.523 rad、偏航率 1.5 rad/s、功率上限 1500 W 等）为占位值，M0-B 校准。
- `P_est` 仍是未校准机械轴功率代理；无电池/电机效率/气动阻力模型，不得报告真实节能率。
- `.slx` 为二进制，`air_spare.slx` 与 `air_m0a.slx` 已同步入仓库；后续避免多分支并行修改同一模型。

## 下一步

按路线图 §6 执行 M0-B：参考选择器（手动/固定 `v_ref` 与优化器可切换）、`v_ref→速度控制器→pitch_ref` 外环、范围/变化率限制与 warm-up、安全监视器（约束触发冻结回退）、固定速度点阶跃/稳态试验；每次结构变更后重跑 `run_air_m0a_baseline_compare`。不接入 `ratio_esc`，不做 RL。

## 验收状态

- `run_air_m0a_baseline_compare`：**PASS**（max diff 0.000e+00，容差 1e-6；总线复核通过）。
- `m0a_P_est_W` 交叉验证：与 `C_M·Σω³` 独立重算最大偏差 5.7e-14 W。
- `modules/ratio_esc/run_acceptance`：本会话未运行；未改动该模块的代码或模型。
