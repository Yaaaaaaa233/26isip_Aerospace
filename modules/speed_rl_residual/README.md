# 不规则风场下的残差速度强化学习

本工程以本仓库 `modules/speed_esc`（本地工程名 `speed_esc_matlab`）为基线，将速度参考拆成：

```text
v_ref = guard(v_base + delta_v)
```

- `v_base` 由固定值、ESC（`modules/speed_esc`）或同学后续的多峰/圆周解析模块提供。
- `delta_v` 由TD3根据测量历史输出，范围为 `[-3,3] m/s`。
- 快层速度、姿态和轨迹控制不属于RL；当前只用一阶速度响应代理。
- 所有功率、风场和电池数据均为仿真量，不是X8实测或飞控安全值。

## 1. 从这里开始

在MATLAB R2022b中运行：

```matlab
START_HERE                 % 圆周+正弦风接口演示，不训练
run_checks(false)          % 单元测试、环境检查和20个不规则风种子
run_checks(true)           % 另外执行1回合TD3训练冒烟

% 简单固定恒定风候选；适合检查能否学会一个残差
[agent,stats,file] = train_td3(50,60,'constant',false);

% 每回合随机二维恒定风；用于检查是否真正利用风观测
[agent,stats,file] = train_td3(100,60,'constant',true);

% 可选课程训练：无风 -> 可观测不规则风 -> 缺测 -> 隐藏风
[agent,stageStats,file] = train_curriculum([10 20 20 20 50 30 50],120);

% 在20个未见种子上比较固定、基准、解析脚本和TD3
c = speedrl.config('windMode','irregular','trajectory','circle');
R = evaluate_policies(file,2001:2020,c,'fixed');

% 把某个候选纳入正式不规则风检查；性能不达标会保留并报警
run_checks(false,file);
```

`run_demo` 中的“残差接口参考”是可观测风解析脚本，用来证明接口中的风信息可被利用，**不是训练完成的RL策略**。只有传入保存的agent文件时才会额外绘制“TD3候选”。

## 2. 数据流

```text
风场/轨迹/功率适配器（可替换）
        ↓ 带时间戳、噪声、延迟、有效标志的sample
基准模块 -> v_base
TD3观测历史 -> delta_v
        ↓
速度范围、变化率、数据质量和轨迹门控
        ↓
v_ref -> 一阶速度闭环代理 -> 二维地速
        ↓
v_air = v_ground - v_wind -> 代理功率 -> 测量反馈
```

控制器观测只由测量sample构建；`sample.evaluator` 中的真实风和真实功率只用于报告，不进入基准器或TD3观测。

## 3. 当前场景

| `windMode` | 含义 |
|---|---|
| `none` | 无风，检查残差应接近0 |
| `constant` | 单回合内固定二维风；训练时每回合随机方向和强度，测试可设置 `randomizeWind=true` |
| `step` | 中途改变方向的分段风 |
| `sine` | 正弦二维风，供圆周解析接口演示 |
| `irregular` | 二维OU有色噪声叠加随机衰减阵风 |
| `mixed` | 每回合按种子选择constant/step/sine/irregular |

`windObservation` 支持 `observable`、`dropout`、`hidden`。即使风完全隐藏，观测维度仍保持不变：风值置0、有效标志置0，策略只能根据速度和功率历史判断。

`trajectory` 支持 `straight` 与 `circle`。圆周模式使用：

```text
tangent(theta) = [-sin(theta); cos(theta)]
ground_velocity_NE = tangent * ground_speed
air_velocity_NE = ground_velocity_NE - wind_velocity_NE
```

当前轨迹误差为0的占位输出，等待同学的轨迹跟踪模型替换；接口、惩罚和冻结逻辑已经存在。

## 4. 观测、动作与奖励

每1秒决策一次，内部对象以0.05秒推进。每帧18项：切向地速、空速、当前参考、基准速度、上一残差、平均功率、功率变化、切向/法向风、风数据年龄、SOC、电压、相位正余弦、径向误差和3个有效标志。最近8帧拼成144维向量。

策略看不到完整功率曲线、真实最优速度、真实风、未来正弦波或下一时刻扰动。观测字段和归一化尺度见 `+speedrl/observe.m`。

```text
reward = - mean(measured_power)/powerScale
         - 0.002 * normalized_delta_change^2
         - 10 * missing_power_fraction
         - 10 * blocked_fraction
         - 2 * normalized_radial_error^2
```

训练回合时长固定。主要验收值是平均真实代理功率，不是累计reward；估算续航采用 `usableEnergyWh / meanPowerW`。

硬约束位于策略外：地速参考 `[2,15] m/s`，参考变化率 `0.5 m/s/s`。速度或功率反馈失效时保持上一参考；风缺测不直接阻止飞行；径向误差超过5 m时忽略RL残差并回到基准请求。

## 5. 给同学预留的接口

环境必须提供：

```matlab
[state,sample] = adapter.reset(seed,config);
[state,sample] = adapter.step(state,v_ref,dt);
```

基准模块必须提供：

```matlab
[v_base,info] = baseline.reference(measured_context);
```

多峰曲线的全局谷点选择应封装在baseline内部；RL仍只接收一个 `v_base`。圆周/正弦风模块提供二维地速、二维观测风、相位、切向量和轨迹误差即可。完整字段、有效性规则和接入步骤见 [接口说明](docs/INTERFACES.md)。

## 6. 公平比较

`evaluate_policies` 对每个种子重新创建相同的环境：

- `fixed`：固定6.3 m/s绝对参考。
- `baseline`：只使用传入的基准器，残差为0。
- `scripted`：基于可观测风的解析残差，仅作为接口上限参考。
- `td3_agent`：仅在传入agent时运行。

报告平均功率、累计电能、估算续航、最低/最高地速、边界/限速违规、缺测覆盖率和径向误差。训练种子从1000开始，默认验收种子为2001–2020。结果同时写入 `policy_evaluation.csv` 和带风场/观测模式名称的CSV，避免后续场景覆盖关键结果。

## 7. 限制

- 简化功率函数只依赖空速偏差和加速度，不是论文气动模型。
- 没有六自由度、侧滑、倾角、总推力、偏航、电机饱和或真实轨迹误差。
- 当前SOC参与电池状态与观测，但不会被武断地用于移动最优速度。
- 训练候选不能直接下发PX4；本工程没有MAVLink写指令代码。
- 残差范围可能不足以跨越相距很远的多个谷点。第一版约定全局谷点由同学的baseline负责；以后若让RL选谷，需要新增混合动作环境。

实际检查结果见 [验证说明](docs/VERIFICATION.md)。

当前保存了两类候选：固定恒定风候选在同类简单场景中相对固定基准降低约3.02%代理功率，但直接迁移到不规则风后0/20个种子胜出；随机二维恒定风候选在未见随机恒定风中仅5/20个种子胜出，在不规则风中仅1/20个种子胜出。二者都是课程训练的起点，不是不规则风最终策略。

两个训练候选与训练冒烟检查点（`td3_candidate_*.mat`、`td3_smoke_mixed.mat`，属训练产物而非仿真输出）已作为证据存入仓库 `docs/evidence/speed_rl_residual/`；`results/` 下的评估CSV与演示图同样有精选副本在该目录，完整产物可用本README脚本在本地重建。
