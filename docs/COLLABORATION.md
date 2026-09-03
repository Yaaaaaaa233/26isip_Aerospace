# ESC与RL模块协作说明

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：周航正
主要撰写：周航正（协作与接口需求）
审核：待项目组审核
AI协助：Codex（权威边界、现状对齐与统一策略插槽整理，2026-09-02～09-03）

## 文档边界

本文只说明算法模块怎样调用、怎样接适配器以及怎样协作，不重复定义 Wind-Plane-Control 的公共字段。

- 公共字段的名称、单位、坐标系、时间戳和有效性以 [`architecture/04_interface_dictionary.md`](architecture/04_interface_dictionary.md) 为准。
- `interfaces/M*.md` 只负责某个阶段怎样把公共字段接到 PX4/Simulink，不得改变公共字段语义。
- 当前完成度、可引用结论和下一步只看 [`DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md)；模块入口和负责人只看 [`../modules/README.md`](../modules/README.md)。
- 本文中的 MATLAB 函数签名是现有模块局部接口。接入统一 Plane 时由适配器转换，不把局部命名反向写入公共字典。
- 名义功率图、隐藏运行对象和在线测量的可见范围以 [`decisions/ADR-004-power-map-information-boundary.md`](decisions/ADR-004-power-map-information-boundary.md) 为准。

## 模块目标

本文档约定核心 ESC 与残差 RL 模块的局部接口和共同因果边界。

模块 `modules/ratio_esc` 优化的是上下桨转速比：

\[
\eta_\Omega = \frac{\Omega_u}{\Omega_l}
\]

模块 `modules/speed_esc` 在配比固定 η=1 的假设下优化平飞速度参考 `v_ref`；模块 `modules/speed_rl_residual` 在速度基线之上学习残差修正 `v_ref = guard(v_base + Δv)`。三者当前都使用虚拟/代理功率对象，只用于验证在线寻优的软件逻辑。未来接入真实共轴模型时，功率、推力、偏航和饱和约束必须由经过标定的数据或模型提供。

## 统一慢层策略插槽（0.3建议接口）

现有模块局部API继续保留，由适配器统一成下面的概念接口：

```matlab
[policyState, candidate] = policy.reset(scenarioConfig);
[policyState, candidate] = policy.step( ...
    policyState, measuredContext, decisionDt);
```

`candidate`只包含 `v_ref_candidate_mps`、`eta_ref_candidate`、模式和诊断信息；SafetyGuard生成最终 `ControlCommand`。`fixed`、`nominal_sched`、`esc`和`rl_residual`一次只启用一种，使用同一个 `MeasuredContext`和同一套安全门控。

RL位于这个策略插槽中。残差形式先调用固定/名义/ESC基线得到 `v_base`，再输出 `delta_v`；它不与ESC并行争用命令，也不接收Plane真值或未来WindTruth。

## 共同接口

### ESC控制器

```matlab
p = ratioesc.controller_config(c);
s = ratioesc.esc_reset(p, initialRatio, initialMeasurement);
[reference, s, diagnostic] = ratioesc.esc_step( ...
    s, measuredPower, actualRatio, valid, p);
s = ratioesc.freeze(s, enabled);
```

- 输入 `measuredPower`：当前测量功率，不应包含真实最优点、完整曲线或解析梯度。
- 输入 `actualRatio`：对象实际达到的转速比。
- 输入 `valid=false` 或 `freeze=true`：保持上一执行参考；恢复后重新初始化滤波器，并经历一个微扰周期的热身。
- 输出 `reference`：经边界和变化率限制后的参考转速比。
- `diagnostic`：仅用于解释和画图，含中心值、微扰、高通、解调和梯度估计。

### 对象与测量链

```text
输入：reference, eta_optimum, noise, configuration
状态：actual_ratio, delay_buffer
输出：true_power, measured_power
```

`power_map`、`plant_advance`、`measure` 是各算法工程中替换代理对象的入口。它们不是统一 Plane 公共 API；接入时必须通过适配器映射为 `PlaneState`。若未来加入总推力、偏航、电机饱和或电池电压，应在对象侧输出明确的 `constraint_flags`；不要把这些隐藏量直接给ESC或RL策略。

### 强化学习环境

```matlab
env = ratioesc.make_rl_env(c);
validateEnvironment(env);
[observation, reward, done] = step(env, action);
```

- 动作：连续参考转速比，范围 `[0.75, 1.25]`。
- 观测：归一化实际转速比、归一化已执行参考、窗口平均测量功率、功率均值变化量。
- 奖励：窗口平均测量功率的负值。
- 上述说明只针对 `modules/ratio_esc` 内的 RL 接口样例：该模块不包含训练完成的TD3、PPO或Agent-PID。其他 RL 预研的实际状态以模块目录和开发状态文档为准。

### 平飞速度 ESC（modules/speed_esc）

```matlab
c = speedesc.config('version',3,'curve','cubic','method','regression');
p = speedesc.controller_config(c);   % 白名单校验，不含功率曲线、最优点或跳变时刻
s = speedesc.esc_reset(10,p);
[nextReference,s,diagnostic] = speedesc.esc_step( ...
    s, measuredPower, pairedSpeed, sampleTime, currentTime, valid, p);
```

- 输入 `measuredPower`：当前收到的测量功率；与 ratio_esc 相同，不含真实最优点、完整曲线或解析梯度。
- 输入 `pairedSpeed`：**与该功率采样时刻配对的实际速度**——功率经 FIFO 延迟队列到达，必须用同时刻的速度回归，不得配当前速度（这是本模块对原 Python 方案的关键修正）。
- `valid=false`：保持上一参考并冻结估计器；恢复后重新预热一个完整回归窗口。
- 输出 `nextReference`：中心（限幅+限速）叠加正弦微扰后的速度参考，变化率独立限制。
- 梯度估计默认为窗口最小二乘回归（约一个微扰周期），经典同频解调作为对照保留；两者参数不可机械互换。

### 残差速度 RL（modules/speed_rl_residual）

```matlab
[state,sample] = adapter.reset(seed,config);   % 可替换的被控对象适配器
[state,sample] = adapter.step(state,v_ref,dt);
[v_base,info]  = baseline.reference(measured_context);  % 基线提供方（固定值/ESC/解析式）
```

- 动作：TD3 输出的残差速度 `Δv ∈ [-3,3] m/s`；执行参考 `v_ref = guard(v_base + Δv)`，地速边界 `[2,15] m/s`、变化率 0.5 m/s/s 的硬约束在策略外（`guard`）。
- 观测：仅由带时间戳/噪声/延迟/有效标志的测量 sample 构建；`sample.evaluator` 中的真值只给评价器，不进基线器或策略。
- 基线契约：`v_base` 由 baseline 模块内部决定（可封装 ESC、固定值或解析式），RL 只收到一个 `v_base` 数值。
- 冻结语义：速度或功率反馈失效时保持上一参考；圆周轨迹径向误差超阈值时忽略残差、回退基线请求。

## 并行认领建议

| 技术线 | 主要目录/函数 | 独立交付 |
|---|---|---|
| ESC算法 | `+ratioesc/esc_step.m`、`freeze.m` | 收敛、边界、冻结和参数整定实验 |
| 对象与物理 | `power_map.m`、`plant_advance.m`、`measure.m` | 可替换的推力-功率-偏航约束对象及其标定说明 |
| 仿真与飞控 | `build_simulink.m`、`run_simulink.m` | SITL/PX4遥测适配与统一日志转换，不改控制器因果接口 |
| RL与评估 | `make_rl_env.m`、`rl_step.m`、`metrics.m` | 训练脚本、独立验证场景、ESC与RL公平对照 |
| 展示与证据 | `launch_ratio_esc.m`、`docs/evidence/` | 过程图、验收报告、汇报素材和可复现实验记录 |
| 速度ESC线 | `modules/speed_esc/+speedesc/`（`esc_step.m`、`estimate_step.m`） | 速度变量梯度估计器改进、窗口/增益整定、M0-C 内核替换候选 |
| 残差RL线 | `modules/speed_rl_residual/`（`train_td3.m`、`evaluate_policies.m`） | 适配器替换（真实轨迹/风数据）、课程训练、与固定/ESC/解析基线公平对照 |
| Plane物理对象 | 规划中的 `models/plane/` 与公共 `PlaneState` 适配器 | 空地速、执行动态、联合功率、电池和约束状态；不直接改算法内核 |
| WPC集成线 | `docs/architecture/04_interface_dictionary.md`、`integration/` | 把模块局部接口映射到公共字段，并提供契约测试 |

## 提交约定

1. 从 `main` 拉取最新内容后，以 `feature/<topic>` 建立分支。
2. 算法、对象和展示改动分成独立提交，提交信息使用动词开头，例如 `Add constrained power-map adapter`。
3. 修改算法或对象后运行 `run_acceptance`；修改UI、结果图或导出后运行 `qa_ui`。
4. 只提交源代码、模型、测试、文档和经过筛选的证据。默认仿真输出可在本地重建，不进入版本库。
5. 新文件和重要修改按 [`AUTHORSHIP.md`](AUTHORSHIP.md) 补充署名与贡献说明；保留已有作者记录，AI协助单独注明。
