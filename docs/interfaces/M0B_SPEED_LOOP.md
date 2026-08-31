# M0-B 速度闭环与安全回退接口

状态：**M0-B 已完成并通过验收（2026-08-31）**。开发模型 `models/px4_x8/air_spare.slx`，验收快照 `models/px4_x8/air_m0b.slx`。试验归档 `results/air_m0b_tests/20260831_234117/`（本地），比对归档 `results/air_m0a_baseline_compare/20260831_232611/`（本地）。

这份文件固定 M0-B 速度通道的因果边界、信号定义与安全语义；M0-C 的 ESC 只能在这些接口内工作。

## 1. 模型结构事实（M0-B 审计确认）

以下为 `air.slx` 原始行为，M0-A/M0-B 均未改变：

1. `Attitude Control/InputConditioning` **忽略全部 RC 输入**（四路 Inport 接 Terminator），指令由内部生成：roll = 正弦（偏置 1500、幅 200 us → 归一化 ±0.4 @1 rad/s）、pitch = 常数 1500（归一化 0）、thrust = 常数 1500（归一化 0.5）、yaw = 常数 1500（0）。
2. `InputConditioning/Roll_Pitch1` 输出（2 维、single 精度）经 `Gain2 = [1 -1]` 对 pitch 取负后送入内层 `control_and_mix` 的第 3 输入 `roll_pitch`；chart 内 `theta_des = clamp(roll_pitch(2),-1,1)·0.523 rad`。
3. chart 的 `arm` 由 wrapper 内 Constant 1 提供（恒解锁）；RC `arm` 只进 `ARMINGControl` → PX4 PWM Output 的解锁引脚。
4. 垂直方向为原始模型固有自由落体：PWM=1500×8、`P_est≈251 W`，但 6DOF 垂直速度按 ~g 下降。功率数字只作模型内对照。
5. 基线水平运动由 roll 正弦驱动：`Ve_y ∈ [0, 8.4] m/s` 摆动（周期 ≈6.28 s），`Ve_x ≈ 0`。

## 2. M0-B 新增信号与模块

| 信号 / 模块 | 位置 | 定义与限制 |
|---|---|---|
| `M0B Reference & Safety` | 根层子系统 | 参考选择器 + 安全监视器（安全层在平台侧，绝不在 ESC 内核）。输入 `optimizer_enable, v_ref_manual, v_ref_optimizer, flags(8), Ts`；输出 `v_ref`（范围 [0,15] m/s、变化率 2 m/s²、warm-up 由速率限制实现）与 `optimizer_status` |
| `optimizer_status` | 枚举（double） | 0=固定基线（optimizer_enable=0，走手动参考）；1=warm-up（向所选参考爬升）；2=active；3=frozen（硬标志触发，保持最后参考 ≤0.5 s）；4=fallback（回退手动参考，标志清除 1.5 s 后重进） |
| `M0B Speed Controller` | 根层子系统 | 投影 PI：`e=v_ref−v`，`e_eff=e·s2`（`s2=−1` 当 `e<−0.1 且 Ve_x<0`，否则 `+1`），`pitch_cmd=−(Kp·e_eff+Ki·∫e_eff)`。符号约定（实测标定）：**`pitch_cmd>0 → θ_des>0 → 推力向 −x 倾 → 加速 −x**（`dVe_x/dθ≈−147`）。`Kp`、`Ki` 为根层常量（默认 0.12、0.04），`|pitch_cmd|≤0.40`、积分 ≤0.15、变化率 0.25/s；`enable=0` 时输出 0 并复位 |
| 俯仰注入点 | `Attitude Control` wrapper 内 | `InputConditioning` 出 2（Roll_Pitch）→ `M0B Pitch Demux` → **算术融合** `y = orig·(1−e) + m0b_cmd·e`（`e=speed_loop_enable`，`m0b_cmd` 经 double→single 转换）→ `M0B Pitch Mux` → 内层 `roll_pitch`。`e=0` 时 IEEE754 下 `orig·1.0+0.0 = orig` 逐位复现。roll/yaw/thrust/arming 通路零改动。不用 Switch 控制口（该安装环境下 chart/控制口连线在编译时会被静默断开，见 §4） |
| `M0B Speed Loop Enable` | 根层常量，默认 0 | 0=旁路（与 `air` 基线逐位一致，验收差 0）；1=速度外环接管俯仰 |
| `M0B v Ref Manual` / `M0B v Ref Optimizer` | 根层常量，默认 5 / 5 | 手动固定参考（optimizer off 时生效）/ 优化器参考占位（M0-C 替换为算法输出） |
| `M0B Flags Override` | 根层子系统 | 用普通逻辑方块（Demux/Abs/Relational/OR/DTC/Mux）重算 8 位约束中的位 3（`|φ|>att_tol ∨ |θ|>att_tol`）与位 5（`|v−v_ref(unit delay)|>speed_tol`），其余位透传 M0-A chart 原样输出。**阈值 `M0B Att Tol`（默认 0.523 rad）与 `M0B Speed Tol`（默认 1.0 m/s）为运行时常量**，试验可在内存中改 |
| `m0b_log_bus` | 7 元向量 @1 ms | `[v_ref, pitch_cmd, v_err, optimizer_status, speed_loop_enable, ve_x, v]` |
| `Ve_x` 观测 | `Subsystem` 出口 9 | `M0B Ve X`（`u(1)`）+ 根层 ZOH 对齐 1 ms |

## 3. 安全语义

- 硬标志集合 = 位 1（PWM 边界）、2（RPM 边界）、3（姿态）、4（偏航率）、6（功率异常）、7（NaN）；位 5（速度失跟）只记录、不参与冻结门控。
- 触发链：硬标志 → frozen（状态 3，保持最后参考，最长 0.5 s）→ 仍触发则 fallback（状态 4，参考回退手动值）；标志连续清除 1.5 s 后恢复 active（经速率限制 warm-up）。
- `optimizer_enable=0` 时恒为状态 0（固定基线），任何标志都不切换参考；`speed_loop_enable=0` 时俯仰通路完全旁路。

## 4. 该 Simulink 环境的两个已知工程约束（踩坑记录）

1. **chart 脚本一经设置即断线**：对已存在的 MATLAB Function chart 重新赋值 `Script`（哪怕仅改字面量）或在其端口重推导的编译中，其连线会被静默丢弃（表现为输入接地、输出悬空，编译只报"欠定信号维度"或下游莫名错误）。对策：M0-A chart 永不改动；需要改语义时用普通方块在外层覆盖；新增 chart 时创建→设脚本→立即接线→编译后逐一验证连线（`ensureLine` 模式）。
2. **Switch 控制口连线不可靠**：同环境下 wrapper 内新增 Inport → Switch 控制口的连线在编译后失效（控制口视为断开，Switch 恒选 in1）。对策：选择器一律用算术融合（Product/Sum）实现。

## 5. 验收结论（2026-08-31）

- **旁路零差异**：装入全部 M0-B 层后 `speed_loop_enable=0`，`run_air_m0a_baseline_compare` 三信号（`pwm_cmd`/`Ve`/`quat`）与 `air` 逐样本最大绝对差 = 0。
- **固定速度跟踪**（窗口 t∈[6,10] s）：5 m/s 均值 |err| 1.62 m/s；9 m/s 1.60 m/s。误差受 §1.5 roll 正弦扰动的物理下限约束（增益扫描 0.06–0.30 证实更大增益放大振荡：0.30 时均值误差 3.32 m/s）。PWM 全程 1500±4（无边沿饱和）、姿态在自身限幅 0.209 rad 内、硬标志静默。
- **阶跃** 6→9 m/s @t=4 s：后段均值 |err| 1.88 m/s。
- **安全回退演示**（运行时收紧 `M0B Att Tol` 至 0.15 rad 使 roll 正弦合法触发位 3；optimizer 参考设 13 m/s）：状态序列含 8 次 warmup/frozen/fallback 转换，fallback 期间参考回退手动 5 m/s，俯仰恢复。

## 不变约束

1. `speed_loop_enable=0` 必须保持与 `air` 基线逐位一致；任何不满足此验收的结构变更不得合入。
2. 优化器（M0-C 起）只能经 `v_ref`（以及 M2 起 `eta_ref`）作用于平台，不得触碰 8 路 PWM、roll/yaw/thrust 通路与安全监视器。
3. 每次优化试验与 `optimizer_enable=0`、`speed_loop_enable∈{0,1}` 的同条件基线配对归档。
4. `P_est` 未校准；一切对比结论仅限"模型估算"口径。

下一步按 [`PROJECT_EXECUTION_ROADMAP.md`](PROJECT_EXECUTION_ROADMAP.md) §6 的 M0-C 项 1–5 接入单变量速度 ESC。
