# 仿真系统—算法模块接口定义（SIM_ALGO_INTERFACE）

版本：v0.1（建议/Proposed，待 R0 组内确认后冻结为 1.0）
日期：2026-09-05
依据：2026-09-05「无人机仿真系统接口定义与验收标准研讨会」决议

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：周航正（会议指定：发言人1）
本次贡献：ZCode（依据会议决议与既有 `plane.step` 契约成文）
审核：待项目组审核
AI协助：ZCode（全文起草，待人工复核精简）

## 1 目的与权威关系

本文件定义仿真系统与算法模块之间的数据交互标准，落实会议确立的闭环控制模式：

> 算法输出目标速度 → 仿真执行并反馈实际状态 → 算法调整

| 事项 | 权威文档 |
|---|---|
| Wind-Plane-Control 公共字段与语义 | [`../architecture/04_interface_dictionary.md`](../architecture/04_interface_dictionary.md)（0.3 建议版，R0 后冻结 1.0） |
| 项目阶段与放行 | [`../PROJECT_EXECUTION_ROADMAP.md`](../PROJECT_EXECUTION_ROADMAP.md) |
| 签名事实基线 | `models/plane/+plane/step.m`（`schema_version` 0.3）；PX4 测量面 `models/px4_x8/+x8phys`（`platform_step`） |
| 本文件角色 | 阶段接口：只做细化映射，不覆盖公共字段语义 |

本文件冻结为 1.0 后，签名、字段、单位或符号约定的任何变更必须新增 ADR，并同步接口字典与受影响适配器测试。

## 2 控制模型与闭环语义

### 2.1 控制权归属

- 算法侧（慢层）每个**控制周期**输出一次**目标速度** `v_ref`：沿轨迹切向的地速参考，单位 m/s；后续阶段增加转速比参考 `eta_ref`。
- 仿真侧（Plane）负责执行：跟踪 `v_ref`，产生实际运动、功率与电池状态，并回传实际状态。
- 算法**不得**直接输出加速度、姿态、转速或 PWM 等物理量；这些由仿真侧的执行动态与内环产生（会议决议："目标速度主导"，而非直接控制物理量）。

### 2.2 保持语义（热运行）

- 两次指令之间，仿真按最近一次 `v_ref` 持续热运行（零阶保持），直至收到新指令。
- 仿真步长 `dt`（默认 0.01 s）与控制周期 `Tc`（典型 0.05 s，ESC 决策周期）分离：`Tc ≥ dt`，一个控制周期内仿真推进 `Tc/dt` 步并使用同一指令。

### 2.3 闭环时序

```text
每个控制周期 k：
  算法 policy.step(measuredContext_k) ──v_ref[k]──▶ 仿真 plane.step(...) × (Tc/dt)
  仿真 out（实际速度/位置/功率/…）──测量时延+噪声+有效性──▶ measuredContext_{k+1}
```

## 3 仿真系统输入

### 3.1 场景设置（每个仿真回合一次）

| 字段 | 类型/单位 | 约束 | 说明 |
|---|---|---|---|
| `trajectory_type` | char | `'circle'`（主任务）/ `'line'`（开发基线） | 任务几何类型 |
| `circle_radius_m` | double, m | > 0；物理化验收建议 50–150 | **运动半径 R** |
| `circle_center_ne_m` | 2×1 double, m | 有限 | 圆心（NE 坐标） |
| 风速参考 | 见 §3.2 | — | 交给 Environment 的风参考 |
| 回合时长/圈数 | double, s | 任务窗 T=3600 s（harness 口径） | 评价窗 |

### 3.2 风速参考与风的三面

风速参考是**场景参数**（描述风的名义模式），不是逐周期运行时输入：

- 算法侧提交风速参考（模式 + 参数）：恒风 `windSpeed`（m/s）、`windDirDeg`；正弦风 `windAmp` / `windOmega` / `windBias`；双正交风另加 y 分量 `windAmpY` / `windOmegaY` / `windBiasY`。
- Environment 依据参考生成**风真值** `wind_truth_ne_mps`（仿真内部，可含种子扰动）与**风测量** `wind_measured_ne_mps`（带时间戳、噪声与退化，给算法）。
- **风参考 ≠ 风真值**：开环 Task 1 允许算法按风参考计算名义调度（nominal_sched）；闭环 Task 2 的公平性要求在线策略只使用风测量与历史数据，不得读风真值或未来风。
- 三步走信息结构（见 [`../SIM_ACCEPTANCE_ROUTE.md`](../SIM_ACCEPTANCE_ROUTE.md) §2.1）：风参考供第①步开环规划（曲线已知·风已知）；风测量供第②步在线估计（曲线已知·风未知）；第③步黑箱寻优（曲线未知·风未知）只依赖逐周期测量面。

### 3.3 控制指令（每控制周期）

`command`（ControlCommand）字段：

| 字段 | 类型/单位 | 定义域（config 限幅） | 说明 |
|---|---|---|---|
| `v_ref_applied_mps` | double, m/s | `speed_bounds_mps = [0, 20]` | 目标速度（必填） |
| `eta_ref_applied` | double | `eta_bounds = [0.75, 1.25]` | 转速比参考（必填，现阶段固定 1） |
| `controller_mode` | char | — | 模式诊断（可选） |

越界值由仿真侧夹断到定义域（不报错、不静默改写指令语义）；算法可通过回传的 `v_ref_applied_mps` 核对实际应用值。

## 4 仿真系统输出（状态回传）

### 4.1 算法可见的测量面

`plane.step` 输出 `out` 的核心字段：

| 字段 | 单位 | 含义 |
|---|---|---|
| `time_s` | s | 仿真时间 |
| `position_ne_m` | m | **实际位置**（NE） |
| `ground_velocity_ne_mps` / `tangential_ground_speed_mps` | m/s | **实际速度**（地速矢量 / 沿轨迹切向分量） |
| `air_velocity_ne_mps` | m/s | 实际空速（= 地速 − 风） |
| `power_w` | W | **实际功率**（测量值，附 `power_sample_time_s`、`power_valid`） |
| `energy_electrical_J`（`energy_electrical_Wh`） | J / Wh | 累计实际能耗 |
| `soc` | 0–1 | 电池荷电状态 |
| `constraint_flags` | 8 位 | pwm / rpm / attitude / yaw_rate / speed_miss / power_anomaly / signal_missing / reserved |
| `radial_error_m`、`path_phase_rad` | m、rad | 圆周径向误差 / 航迹相位（圈定位） |
| `v_ref_applied_mps`、`eta_ref_applied` | m/s、— | 实际应用的目标值（夹断后） |

PX4/Simulink 侧对应测量面见 `platform_step` 输出（`t / v / P_e / E_e / attitude / yaw_rate / motor_pwm / motor_rpm / constraint_flags / …`）；平台 8 位 flags 的映射唯一入口为 `map_flags`。

### 4.2 测量与真值分离（因果红线）

- 算法只能接收**测量值**：带时间戳、年龄、噪声/延迟与有效性标志。
- 完整功率曲面、真实最优点、解析梯度、风真值与未来风**不得**进入控制器或 RL 观测；真值只给评价器（harness `truth()`、`sample.evaluator`）。

## 5 物理限制约束（仿真侧职责）

会议决议：仿真系统需模拟真实物理限制，保证**实际速度不发生瞬时跳变**，并计入惯性与环境扰动：

| 约束 | 参数（`plane.config`） | 口径 |
|---|---|---|
| 速度一阶惯性 | `speed_tau_s = 1.0` s | 实际速度向目标的指数趋近 |
| 速度变化率限幅 | `speed_rate_mps2 = 2.0` m/s² | 任一步 Δv ≤ 2.0·dt |
| 定义域夹断 | `speed_bounds_mps = [0,20]`、`eta_bounds = [0.75,1.25]` | 越界夹断 |
| eta 惯性与限幅 | `eta_tau_s = 0.5` s、`eta_rate_s = 0.10` /s | 同上 |
| 风扰动 | `air = ground − wind`，功率按空速计算 | 风改变空速进而改变功率与最优速度 |
| 电池 | SOC 单调不增 ∈ [0,1]，截止电压后功率置 0 | 能耗积分 `E = ∫P·dt` 相对误差 ≤ 1e-6 |

## 6 数据一致性校验清单（接入前双方核对）

1. **单位**：时间 s；长度 m；速度 m/s；功率 W；能量 J（Wh = J/3600）；角度 rad；角速度 rad/s；SOC 0–1；PWM µs；转速 rpm。
2. **坐标系与符号**：统一 NE 平面；全仓约定 **`v_air = v_ground − wind`**（减号）。`wind_field_sched` 局部加号约定（`u = v·t̂ + w`）接入时必须适配，不得直接传入（适配参考实现：`modules/wind_semantics_correction`，空速恒等式精度 1e-9）。
3. **时间戳配对**：功率与速度必须按各自采样时刻配对（功率经延迟 FIFO 到达时使用同时刻配对样本，见 `speedesc.esc_step` 的 `pairedSpeed` 约定）。
4. **有效性传播**：`power_valid` / `state_valid` / `wind_valid` 为假时，算法不得使用对应样本，评价器标记剔除。
5. **能量对账**：回传 `energy_electrical_J` 与 `Σ P·dt` 在数值积分精度内一致。
6. **版本对齐**：`schema_version`（当前 0.3）与接口字典版本核对一致后方可升级。

## 7 解耦原则（会议决议）

- 仿真系统与算法模块**相对独立**：仿真侧只保证接口一致，不关心算法内部实现；算法侧不依赖仿真内部状态。
- 物理对象升级只替换对象侧（`power_map` / `plant_advance` / `measure` 的等价层，或整体替换 `plane` / `x8phys` 对象），不得修改接口签名。
- 双方在接口层面保持字段、单位与符号定义一致（§6 清单），仿真结果方为有效。

## 8 MATLAB 接口签名汇总

```matlab
c = plane.config();                                % 仿真配置（含物理限制参数）
[s, sample0] = plane.reset(c, initial);            % 回合初始化
[s, out] = plane.step(s, windSample, pathCommand, command, dt, c);  % 单步推进

% 算法侧统一慢层插槽（COLLABORATION.md）
[policyState, candidate] = policy.reset(scenarioConfig);
[policyState, candidate] = policy.step(policyState, measuredContext, decisionDt);
% candidate.v_ref_candidate_mps / eta_ref_candidate → SafetyGuard → command
```

- `windSample`：`time_s / wind_truth_ne_mps / wind_measured_ne_mps / wind_valid`
- `pathCommand`：`trajectory_type / circle_center_ne_m / circle_radius_m / path_phase_rad / path_tangent_ne / path_normal_ne / path_valid`
- 评价器：harness `mop_moe` + Percent 口径（定义见 [`../SIM_ACCEPTANCE_ROUTE.md`](../SIM_ACCEPTANCE_ROUTE.md) §3）

## 9 接口符合性验收判据（随 Task 1 执行）

1. §6 清单逐项核对通过（单位 / 符号 / 时间戳 / 有效性 / 能量对账 / 版本）。
2. P0–P4 六门槛复跑全绿：零风空速=地速、顺逆风符号正确、无瞬时跳变、圆周相位闭合、切片退化到既有基线、优化器不可读完整曲面/真最优点/未来风。
3. 负向测试：注入越界 `v_ref`、缺失风真值、无效 `pathCommand` 时按定义行为夹断或拒绝，不产生静默错误。
