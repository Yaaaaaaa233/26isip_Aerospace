# Wind-Plane-Control接口字典

版本：0.2
日期：2026-09-02
状态：建议基线；实现前需冻结为1.0

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：周航正
主要撰写：周航正（接口需求）、Codex（字段整理）
技术依据：项目组现有ESC、RL、PX4-X8及未来数据接入需求
审核：待各模块负责人审核
AI协助：Codex（接口归并、命名、一致性检查与权威边界整理）

## 本文管什么

本文是 Wind-Plane-Control 公共字段语义的唯一基线，负责字段名、单位、坐标系、时间戳、有效性和来源。它不记录当前完成度，也不规定某个 `.slx` 内部怎样接线。

- 当前完成度以 [`../DEVELOPMENT_STATUS.md`](../DEVELOPMENT_STATUS.md) 为准。
- 阶段接线与验收以 [`../PROJECT_EXECUTION_ROADMAP.md`](../PROJECT_EXECUTION_ROADMAP.md) 和 `docs/interfaces/M*.md` 为准。
- 算法局部函数、适配器用法和协作流程以 [`../COLLABORATION.md`](../COLLABORATION.md) 为准。
- 局部模块字段与本文冲突时，由该模块的适配器转换；不能在下游另起一套公共语义。

## 先看结论

这份文档就是全组共同的数据清单。一个同学只要按这里输出数据，另一个同学就能接入，不需要了解对方模块内部怎么写。

最重要的规则只有四条：

1. 速度、风速和位置要说明坐标方向和单位。
2. 测量要带时间戳和是否有效，不能用0假装“没有数据”。
3. 功率要说明是代理值、模型估算、校准结果还是实测值。
4. 控制器不能收到真实最优点、完整功率曲线或未来风速。

## 1. 大家共同遵守的写法

- 变量名使用英文和下划线，文档说明使用中文。
- 时间单位为秒，距离为米，速度为米每秒，角度为弧度，功率为瓦，能量为焦耳。
- 二维世界坐标统一为NE，数组顺序为 `[north, east]`。
- 风矢量定义为“空气相对地面的速度”，因此 `air_velocity_ne_mps = ground_velocity_ne_mps - wind_ne_mps`。若局部模块把逆风向量写成加法项（例如 `v_air = v_ground + w_headwind`），适配器必须使用 `wind_ne = -w_headwind`，不得改变公共符号约定。
- 时间戳表示样本实际产生时刻，不使用接收时刻冒充采样时刻。
- 关键测量同时携带 `valid`；使用保持值时还应携带 `age_s`。
- 缺失数值使用 `NaN`，不得用0同时表示“真实为0”和“数据无效”。
- 所有功率和能量必须包含 `source`：`proxy`、`estimated`、`calibrated`或`measured`。

## 2. ScenarioConfig

Harness创建的只读场景配置。

| 字段 | 类型/维度 | 单位 | 说明 |
|---|---|---:|---|
| `schema_version` | string | - | 接口版本，当前建议 `0.2` |
| `scenario_id` | string | - | 唯一场景标识 |
| `trajectory_type` | enum | - | `straight`或`circle` |
| `duration_s` | scalar | s | 总运行时间 |
| `sample_time_s` | scalar | s | Plane基础步长 |
| `decision_period_s` | scalar | s | 慢层决策周期 |
| `random_seed` | integer | - | 随机种子 |
| `wind_model` | struct | - | 风场类型及参数 |
| `plane_model_id` | string | - | Plane实现与参数集标识 |
| `controller_mode` | enum | - | `fixed/analytic/esc/rl_residual` |
| `baseline_mode` | enum | - | 正式配对基线 |
| `constraint_profile` | string | - | 约束参数集标识 |
| `evaluation_window_s` | `[1x2]` | s | 指标统计窗口 |

## 3. WindSample

Wind模块输出。`truth`字段只供Plane对象和离线评价，在线控制只能读取允许的测量字段。

| 字段 | 类型/维度 | 单位 | 控制器可见 | 说明 |
|---|---|---:|---:|---|
| `time_s` | scalar | s | 是 | 当前场景时间 |
| `wind_truth_ne_mps` | `[1x2]` | m/s | 否 | 对象侧真实风矢量 |
| `wind_measured_ne_mps` | `[1x2]` | m/s | 条件允许 | 带噪声/延迟的风测量 |
| `wind_sample_time_s` | scalar | s | 是 | 风测量采样时刻 |
| `wind_age_s` | scalar | s | 是 | 当前时刻减采样时刻 |
| `wind_valid` | logical | - | 是 | 风测量有效性 |
| `path_phase_rad` | scalar | rad | 是 | 圆周相位，直线可为0 |
| `path_tangent_ne` | `[1x2]` | - | 是 | 单位切向量 |
| `path_normal_ne` | `[1x2]` | - | 是 | 单位法向量 |
| `scenario_id` | string | - | 是 | 追溯标识 |

## 4. PlaneState

Plane对象/数据适配器输出。

| 字段 | 类型/维度 | 单位 | 说明 |
|---|---|---:|---|
| `time_s` | scalar | s | 状态采样时刻 |
| `position_ne_m` | `[1x2]` | m | 水平位置 |
| `altitude_m` | scalar | m | 高度，正方向须由适配器统一 |
| `ground_velocity_ne_mps` | `[1x2]` | m/s | 世界坐标地速 |
| `air_velocity_ne_mps` | `[1x2]` | m/s | `ground-wind` |
| `tangential_ground_speed_mps` | scalar | m/s | 地速在路径切向投影 |
| `attitude_rpy_rad` | `[1x3]` | rad | roll/pitch/yaw |
| `body_rate_rpy_radps` | `[1x3]` | rad/s | 机体系角速度 |
| `radial_error_m` | scalar | m | 圆周径向误差，直线使用横向误差 |
| `power_w` | scalar | W | 在线可用功率样本 |
| `power_sample_time_s` | scalar | s | 功率采样时刻 |
| `power_source` | enum | - | `proxy/estimated/calibrated/measured` |
| `power_valid` | logical | - | 功率有效性 |
| `voltage_v` | scalar | V | 电池电压，无数据为NaN |
| `current_a` | scalar | A | 电流，无数据为NaN |
| `soc` | scalar | `[0,1]` | 电池荷电状态 |
| `motor_pwm_us` | `[1x8]` | us | 八路执行器指令 |
| `motor_rpm` | `[1x8]` | rpm | 八路转速 |
| `constraint_flags` | uint32/struct | - | 统一约束标志 |
| `state_valid` | logical | - | 状态总体有效性 |

## 5. ControlCommand

Control输出。必须同时保留候选值和安全门控后的实际施加值。

| 字段 | 类型/维度 | 单位 | 说明 |
|---|---|---:|---|
| `time_s` | scalar | s | 决策时刻 |
| `controller_mode` | enum | - | 当前参考生成器 |
| `v_base_mps` | scalar | m/s | 固定/解析/ESC基准 |
| `delta_v_candidate_mps` | scalar | m/s | 残差策略候选，非RL时为0 |
| `v_ref_candidate_mps` | scalar | m/s | 门控前速度参考 |
| `v_ref_applied_mps` | scalar | m/s | 实际施加速度参考 |
| `eta_ref_candidate` | scalar | - | 门控前转速比参考 |
| `eta_ref_applied` | scalar | - | 实际施加转速比参考 |
| `optimizer_status` | enum | - | `disabled/warmup/active/frozen/fallback` |
| `guard_reason_flags` | uint32/struct | - | 限幅、冻结和回退原因 |
| `command_valid` | logical | - | 命令是否有效 |

## 6. EvaluationRecord

Harness追加记录，不回送控制器。

| 字段 | 类型/维度 | 说明 |
|---|---|---|
| `scenario_config` | struct | 本次只读配置快照 |
| `git_revision` | string | 代码版本 |
| `model_revision` | string | 模型/参数版本 |
| `wind_log` | timetable/struct array | WindSample序列 |
| `plane_log` | timetable/struct array | PlaneState序列 |
| `command_log` | timetable/struct array | ControlCommand序列 |
| `metrics` | table/struct | MoP/MoE数值、单位和窗口 |
| `violations` | table | 约束、时刻、持续时间、原因 |
| `verdict` | enum | `pass/fail/inconclusive` |
| `evidence_level` | enum | `proxy/sim_calibrated/sitl/replay/measured` |

## 7. MATLAB里建议怎样调用

实现可以是结构体函数句柄或类，但对Harness暴露统一语义：

```matlab
[windState, windSample] = wind.reset(seed, scenarioConfig);
[windState, windSample] = wind.step(windState, positionNE, timeS);

[planeStateInternal, planeSample] = plane.reset(seed, scenarioConfig);
[planeStateInternal, planeSample] = plane.step( ...
    planeStateInternal, windSample, controlCommand, dt);

[controlState, controlCommand] = control.reset(scenarioConfig);
[controlState, controlCommand] = control.step( ...
    controlState, measuredContext, decisionDt);

evaluationRecord = evaluator.finalize( ...
    scenarioConfig, windLog, planeLog, commandLog);
```

`measuredContext`只能由允许的Wind测量字段和Plane可测状态组成，不能包含 `wind_truth`、隐藏最优点、完整功率曲线或未来场景。

## 8. 数据失效与回退

| 条件 | 慢层行为 | 记录要求 |
|---|---|---|
| 功率无效 | 冻结；持续超时后回退 | 无效比例、开始/结束时刻 |
| 速度/状态无效 | 立即冻结或回退 | 数据源与原因码 |
| 风无效 | 允许无风观测模式或冻结RL残差 | `wind_valid=0`，不得伪造0风有效 |
| 候选越界 | 安全门控限幅/限速 | 候选、施加值、阻止比例 |
| 执行器/姿态约束 | 冻结并按严重度回退 | 约束位、持续时间、恢复时刻 |

## 9. 与现有平台接口的映射

现有 `t/v/P_e/E_e/attitude/yaw_rate/motor_pwm/motor_rpm/constraint_flags` 保持兼容，并映射到 `PlaneState`。当前平台未提供的NE位置、显式风矢量、空速、SOC和径向误差允许先填 `NaN + valid=false`，不得自行猜测。

M0--M1历史阶段 `eta_ref_applied=1`；M2起平台已提供受约束的 `eta` 分配。功率来源在当前PX4-X8平台应标为 `estimated`；代理算法对象标为 `proxy`。

## 10. 接口变更规则

1. `0.x`阶段允许增补字段，但删除或改变语义必须更新本文、版本号和受影响的适配器契约测试。
2. 冻结为`1.0`后，兼容增补只提升次版本，破坏性变更提升主版本。
3. 每个模块至少提供一次确定性reset、边界值和无效数据测试。
4. 不允许用共享全局变量绕过接口传递最优点、未来风或评价结果。
