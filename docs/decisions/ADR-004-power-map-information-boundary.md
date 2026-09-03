# ADR-004：名义功率图与在线优化信息边界

日期：2026-09-03
状态：**Proposed，待项目组与指导教师确认**
决策负责人：项目组；架构归口为周航正

项目组：周航正、霍奕茗、于跃、叶安、王健祺
提案与文件负责人：周航正
决策记录整理：Codex
审核：待项目组讨论、待指导教师确认
AI协助：Codex（仓库现状复核、选项收敛与成文）

## 一句话决定

无风仿真得到的空速-功率图作为已知的名义模型；在线策略优化沿航迹地速参考和后续转速比，只能使用其策略模式获准的名义信息与当前/历史测量，不能读取仿真器隐藏对象、真实最优点或未来真实风。

## 为什么要作这个决定

当前仓库包含两种都合理但不同的假设：

- `modules/speed_esc`：控制器不知道完整功率曲线，只通过速度-功率反馈做黑箱寻优。
- `modules/wind_field_sched`：已知三次名义空速功率曲线和 `V*=6.3 m/s`，再根据已知或在线估计风调度地速。

两者如果不区分信息结构，就会出现“曲线既已知又未知”“解析策略看真风而RL看不到”的矛盾，也无法公平比较。

## 统一模型

### 名义对象

```text
P_nom = P_nom(v_air, eta; nominal_parameters)
```

由无风仿真、文献、CFD/BEMT或后续数据标定得到。它可用于Plane基线、解析调度和评价参考，但必须记录模型版本与证据等级。

### 运行对象

```text
P_hidden = F(v_air, eta, turn_state, battery_state, disturbance; hidden_parameters)
P_meas   = measurement(P_hidden, noise, delay, validity)
```

仿真器内部需要知道 `F` 才能生成数据，但可部署策略不能直接读取 `hidden_parameters`、完整曲面或隐藏最优值。

### 在线决策

```text
action:  v_ref                      第一阶段
action: [v_ref, eta_ref]            后续阶段
cost:    fixed-window mean(P_e)      主任务口径
```

`v_ref`统一表示沿航迹切向地速参考。Plane输出实际地速，并按 `v_air = v_ground - wind` 计算空速和功率。

## 四类策略及其可见信息

| 策略 | 可见信息 | 项目角色 |
|---|---|---|
| `fixed` | 固定参数、当前有效状态 | 最低复杂度基线 |
| `nominal_sched` | `P_nom`、当前/历史风测量、路径状态 | 可部署的名义模型基线 |
| `esc` | 当前/历史实际速度、测量功率、有效性 | 不依赖完整功率图的黑箱在线基线 |
| `rl_residual` | 与可部署基线相同的测量历史和 `v_base` | 只学习名义模型未覆盖的残差 |

`oracle`可以读取完整场景或真风，但只允许进入Evaluation，用于给出理论上界，不能称为可部署在线策略。

## RL放在哪里

RL不是独立于Control的第二套控制器，而是慢层参考生成器的一种实现：

```text
nominal/ESC baseline -> v_base
measurement history -> RL -> delta_v
v_candidate = v_base + delta_v
SafetyGuard -> v_ref_applied
```

RL不输出姿态、推力或PWM，也不直接修改Wind和Plane。统一Plane、因果风场、强基线和Harness未接通前，沿用ADR-002，RL只保留接口与预研状态。

## 对当前成果的重新定位

- `speed_esc`、`ratio_esc`：黑箱在线算法验证资产。
- `wind_field_sched`：名义曲线下的解析/估风调度资产；`known`策略是Oracle参照。
- 多峰和曲线平移模块：算法压力测试，不代表真实Plane曲面。
- `models/px4_x8`：Control接入与安全机制资产，当前 `P_est` 不是已校准功率图。
- 残差RL模块：慢层插件预研，不是当前主交付。

## 什么时候在线方法才有研究意义

至少满足一项：运行对象相对名义图存在未知偏差；风只有当前/历史测量且带误差；执行动态和延迟使逐时刻解析最优不可直接执行；速度与转速比耦合；任务和安全约束需要长期权衡。

若最终统一Plane仍等于一条完全已知、静态、单谷曲线，应把成果降级为接口演示，不以“智能在线优化”作为创新结论。
