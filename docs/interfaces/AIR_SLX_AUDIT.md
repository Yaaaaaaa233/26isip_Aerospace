# `air.slx` 模型核查报告

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：叶安
主要撰写：叶安（核查范围与路线接入判据）、ZCode（脚本化核查与成文）
审核：待项目组审核、待指导教师确认
AI协助：ZCode（接口导出、包结构与配置审计脚本）

核查日期：2026-08-31\\
核查范围：模型包结构、配置、信号接口、内嵌算法、外部依赖和路线接入缺口。未修改 `air.slx`。

## 1. 结论

`air.slx` 是一个可作为项目快层与动力学基础的 **PX4 / Simulink 八旋翼六自由度模型**，不是空白模型。它已经包含：

- 无线电控制输入、解锁逻辑、姿态控制和八电机 PWM 输出；
- 8 路 PWM 到旋翼推力/反扭矩的转换；
- 机体系力/力矩到六自由度刚体运动学；
- 姿态、角速度、加速度和四元数反馈。

它还不是 PDF 技术路线所需的“在线能耗优化闭环对象”。当前缺失速度参考、上下桨转速比参考、电池电压/电流/功率、总推力/偏航约束状态和统一日志接口。因此，第一步应是在保留现有快层姿态稳定逻辑的前提下，补充慢层 ESC 所需的测量与参考接口；不应直接替换现有八电机混控器。

## 2. 模型与运行配置

| 项目 | 发现 |
|---|---|
| 文件版本 | MATLAB / Simulink R2022b；模型修订号 1.13 |
| 仿真时长 | 0–10 s |
| 求解器 | FixedStepAuto，固定步长参数 0.001 s，ODE3 |
| 数据记录 | `yout`、`logsout`、`tout` 已启用；Dataset / timeseries 格式 |
| 目标硬件 | ARM Cortex；模型内说明为 Pixhawk 1 预配置 |
| 电机输出采样 | `Motor 1` 至 `Motor 8` Outport 标为 1/250 s（4 ms） |

## 3. 已有结构与信号

### 顶层

```text
Radio Control Transmitter (px4Sensorslib)
        -> Attitude Control
        -> PX4 PWM Output (px4lib)

Attitude Control 的 8 路 motor PWM
        -> 6DOF Subsystem
        -> 四元数、p/q/r、accel-x/y/z
        -> Attitude Control 反馈
```

### 快层姿态控制

`Attitude Control` 的输入为：

- `quaternion`；
- 指令 `set_roll`、`set_pitch`、`set_thrust`、`set_yaw`；
- 角速度 `p`、`q`、`r`；
- 加速度 `accel-x/y/z`；
- `arm`。

其 `AttitudeControl` 子系统由内嵌 MATLAB Function 实现：外环姿态 P、内环角速度 PID、积分限幅、控制量限幅和 Octa-Quad X 八电机混控。未解锁时强制八路 PWM=1000。

### 六自由度对象

`Subsystem`（系统文件 `system_276.xml`）接收 `Ch1`–`Ch8`，包含：

- `shared6dof/6DOF (Euler Angles)`；
- 方向余弦矩阵到四元数转换；
- 反馈输出 `p/q/r`、四元数、`accel-x/y/z`。

其中 PWM 到物理力/矩的 MATLAB Function 使用：

- 质量 `m=1.4 kg`；
- PWM 范围 `[1000, 2000] us`；
- `omega_max=1000`；
- 推力/反扭矩系数 `C_T=1.42e-5`、`C_M=2.51e-7`；
- 臂长 `L=0.2 m`；
- 八电机的固定几何角与旋向。

该函数计算总力 `F_xyz` 和总力矩 `M_xyz`，并将重力投影到机体系。

## 4. 已确认缺口

| PDF 路线所需能力 | 当前状态 | 需要补充的位置 |
|---|---|---|
| `v_ref` 速度参考 | 缺失；当前输入为 RC 量 | 在 RC 指令与姿态/推力快层之间加入速度外环/参考选择器 |
| 速度反馈 `v` | 6DOF 状态存在，但未形成标准速度接口 | 从 6DOF 导出机体系/惯性系速度，并明确采用空速或地速 |
| `eta_omega_ref` | 缺失 | 在八电机混控后、PWM 映射前加入共轴分配器 |
| 上下桨实际比值 | 缺失 | 从上/下组 RPM 或命令计算并记录 |
| `U`、`I`、`P_e=U*I` | 缺失 | 增加电池/电机电功率模型；初期可接明确标注的代理测量链 |
| 8 路 RPM | 缺失 | 在 PWM→omega 转换处导出 `motor_rpm[8]` |
| `constraint_flags` | 缺失 | 统一汇集电机饱和、过流、姿态/偏航越界、遥测异常等标志 |
| 稳定窗口/Harness | 缺失 | 在模型外层或独立 Harness 中实现，不写进 ESC 内核 |
| MAVLink 日志接口 | 缺失 | 后续以统一日志字段接入，QGC 不直接承载优化算法 |

## 5. 依赖与可运行性

静态分析显示模型链接了以下外部库：

- `px4lib/PX4 PWM Output`；
- `px4Sensorslib/Radio Control Transmitter`；
- `shared6dof/6DOF (Euler Angles)`；
- `sharedtransform/Direction Cosine Matrix to Quaternions`；
- Stateflow MATLAB Function 图表。

因此实际运行至少需要 MATLAB R2022b、Simulink、Stateflow、提供上述 PX4 库的支持包，以及提供 `shared6dof` / `sharedtransform` 的相关产品或本地库路径。

本机已发现 MATLAB R2022b (`D:\matlab2022b\bin\matlab.exe`)；后续已在 MATLAB 图形界面完成模型更新和 10 s 仿真：`air` 从 0 到 10 s 返回 10001 个时间样本且没有错误，随后 `run_air_baseline` 也已通过并归档。早期非交互批处理未返回可判读结果这一点不再构成运行性结论，但仍不应把它当作完整的模型校准或飞控验证。复现基线可执行：

```matlab
load_system('air')
set_param('air', 'SimulationCommand', 'update')
sim('air')
```

并记录第一个缺失库、许可或变量错误。该错误清单是接入前必须关闭的阻塞项。

## 6. 风险与待验证项

1. 物理对象当前只根据 PWM 的二次关系计算推力和反扭矩；没有电池、电机效率、气动阻力、上下桨诱导干扰或电功率模型，不能用于真实节能率结论。
2. 八电机混控矩阵当前是固定的 Octa-Quad X 配置；尚无“给定总推力、零偏航力矩、指定上下桨转速比”的受约束分配器。
3. 姿态控制 MATLAB Function 的 `dt` 输入由模型中的常数 `0.05` 提供，而电机 Outport 标为 4 ms。是否存在采样率不一致须通过模型更新后的 Sample Time Display 和仿真日志确认。
4. 模型当前由无线电输入驱动；速度外环接入时必须保留解锁、限幅和失效保护，而不是绕过它们。

## 7. 建议的下一项实施任务：M0 最小闭环

在 `eta_omega = 1` 固定条件下，建立：

```text
速度 ESC -> v_ref -> 速度外环 / 快层控制 -> 现有八电机对象
        <- v, U, I, Pe, attitude, yaw_rate, motor_rpm, constraint_flags
```

实施顺序：

1. 先在 MATLAB 图形界面完成模型更新与 10 s 基线仿真；
2. 导出并标准化六自由度速度、8 路 PWM 和现有状态；
3. 增加不改动原姿态 PID 的速度参考选择器；
4. 增加可替换的功率测量子系统和日志总线；
5. 用固定 `eta_omega=1` 完成 M0 的 2、10、15 m/s 初值 Harness 场景；
6. M0 稳定后才接入 Git 仓库中的单变量转速比 ESC。
