# 运行场景定义

版本：0.2
日期：2026-09-03
状态：建议基线

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：周航正
主要撰写：周航正（场景思路）、Codex（整理成文）
技术依据：项目组现有直线/圆周、风场、ESC与RL预研成果
审核：待项目组审核
AI协助：Codex（结构整理、文字与一致性检查、信息结构修订）

## 先看结论

- 场景不要一上来全叠加，按“直线无风 → 直线有风 → 圆周规则风 → 圆周不规则风 → 速度和转速比一起调”推进。
- 每个新算法都要和固定速度等简单方法在同一阵风、同一初值下比较。
- 其他模块没完成时先用Mock，也就是输入输出相同的简化替代模型，不需要互相等。

## 1. 为什么要统一场景

如果每个人自己定义风速、时间和功率统计窗口，最后的结果就不能比较。这份文档把场景排好顺序，并规定每次测试需要保存哪些信息。

## 2. 坐标与运动约定

- 水平世界坐标统一为North-East（NE），二维向量顺序为 `[north, east]`。
- 地速、空速和风速满足：

```text
v_air_NE = v_ground_NE - v_wind_NE
```

- 圆周轨迹采用逆时针正方向；位置相位为 `theta` 时：

```text
tangent_NE(theta) = [-sin(theta), cos(theta)]
normal_NE(theta)  = [-cos(theta), -sin(theta)]
```

- 沿程风和侧风分别为：

```text
wind_tangent = dot(v_wind_NE, tangent_NE)
wind_normal  = dot(v_wind_NE, normal_NE)
```

- 圆周任务中的速度决策量默认指沿轨迹切向地速参考。若改为空速参考，必须在场景配置和ADR中明确。

## 3. 场景配置公共字段

```text
scenario_id
trajectory_type            straight | circle
duration_s
sample_time_s
decision_period_s
random_seed
initial_state
wind_model
power_model_id
nominal_power_model_id
hidden_plant_variant_id    只作追溯，参数不发给控制器
power_source               proxy | estimated | calibrated | measured
controller_mode            fixed | nominal_sched | esc | rl_residual
controller_information_mode measurement_only | nominal_model | measured_wind
baseline_mode
constraint_profile
evaluation_window_s
```

圆周场景额外包含 `circle_center_ne_m`、`circle_radius_m`、`direction`；直线场景额外包含 `start_ne_m`、`track_heading_rad`。

每个正式场景必须同时声明名义模型和隐藏运行对象。二者可以相同用于接口回归，但研究性试验至少使用多个未见隐藏参数集；否则只能证明算法在自己已知的单条曲线上工作。Oracle允许读取真风或隐藏最优值，只能作为Evaluation上界，不能填写为 `controller_mode`。

## 4. 递进场景矩阵

| ID | 轨迹 | 风场 | Plane对象 | 策略 | 当前用途 |
|---|---|---|---|---|---|
| S0 | 无空间轨迹 | 无风 | 静态单谷代理 | 固定/ESC | 单元测试与因果性检查 |
| S1 | 直线 | 无风 | 一阶速度闭环+代理功率 | 固定/速度ESC | 当前速度寻优基线 |
| S2 | 直线 | 恒定/分段/正弦风 | 风相关代理功率 | 固定/解析/ESC | 空速地速和风接口检查 |
| S3 | 圆周 | 无风 | 圆周运动代理 | 固定/解析/ESC | 轨迹约束和相位接口检查 |
| S4 | 圆周 | 固定世界风/正弦风 | 可给出解析或离线基准 | 固定/解析/ESC | 形成可解释基准与展示场景 |
| S5 | 圆周 | OU噪声/阵风/日志回放 | 未知时变对象 | 固定/解析/ESC/候选RL | 未见不规则风评价 |
| S6 | 直线或圆周 | 选定风场 | 校准X8对象+`eta_ref` | 单变量/交替优化 | M2/M3后系统验证 |

S0-S1已存在代理对象证据。S2-S6必须在对应模型、接口和评价证据生成后再标记完成。

## 5. 风场族

| 风场 | 定义 | 用途 |
|---|---|---|
| `none` | `[0,0] m/s` | 基线和回归 |
| `constant` | 固定NE风矢量 | 坐标、符号和稳态影响检查 |
| `piecewise` | 按给定时刻切换风矢量 | 在线重新适应能力 |
| `sine` | 幅值/频率/相位确定的正弦风 | 解析解和周期评价 |
| `ou` | 有色随机过程 | 连续不规则风 |
| `gust` | 随机阵风脉冲叠加背景风 | 瞬态与安全门控 |
| `replay` | 带时间戳的日志风场 | 真实数据回放 |

每个风样本都必须携带采样时间和有效标志。风速缺测时不允许把旧值伪装成当前真值；应同时输出数据年龄。

## 6. 基线与公平比较

每个正式场景至少包含一个固定策略基线。能够构造解析策略时，再加入解析基线；ESC或RL只能与同一场景实例比较。

公平比较要求：

1. 相同随机种子、初始状态、风序列和对象参数。
2. 相同仿真时长、预热期和评价时间窗。
3. 相同安全门控、速度范围和参考变化率。
4. 使用对象侧“真实/无测量噪声功率”评价，测量功率只供在线策略使用。
5. 记录被安全门控阻止的动作比例，不把非法动作裁剪后的结果冒充策略能力。

## 7. 训练、调参与验收划分

S0-S4可用于接口开发、算法调参与解析核对。S5若用于RL，必须固定划分：

```text
training_seeds
validation_seeds
held_out_test_seeds
```

测试种子在策略和超参数冻结前不得用于调参。正式RL结论至少覆盖20个未见风场种子，并报告均值、标准差、最差值和硬约束违规次数。

## 8. 并行开发Mock

| 工作包 | 未集成前使用的Mock | 不得依赖 |
|---|---|---|
| Wind | 预生成NE风CSV/确定性函数 | 完整六自由度模型 |
| Plane | 脚本风输入+固定控制指令 | 风场UI和正式优化器 |
| Control | 一阶速度对象+代理功率 | PX4/SITL可用性 |
| Data | 合成MAVLink风格日志 | 实机飞行 |
| Harness | 仓库已有MAT/CSV结果 | 所有场景同时完成 |

Mock与正式模块必须实现相同接口，集成时只替换适配器，不修改算法主体。

## 9. 场景验收状态

场景状态只允许使用：

```text
defined       已定义但未实现
runnable      可运行但未通过门槛
accepted      验收和证据齐全
deprecated    已废弃且说明替代项
```

“能运行”不等于“已验证”。每个 `accepted` 场景必须链接配置、代码版本、结果文件和判据。
