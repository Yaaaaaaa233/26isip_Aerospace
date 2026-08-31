# 转速比ESC分阶段开发

**对象：恒推力假设下的归一化功率代理模型，非实测。**

本工程验证的是：在不知道完整功率曲线及最优点的情况下，能否根据实时反馈在线调整上下桨转速比。它不证明真实X8节能率，不验证偏航稳定性，也不产生虚构的推力或RPM结果。

## 1. 从这里开始

MATLAB R2022b，基础仿真需要MATLAB；模型需要Simulink；RL适配需要Reinforcement Learning Toolbox。控制器本身由显式代码和原生离散模块实现，不依赖新版ESC模块功能。

打开 `START_HERE.m` 并运行，或在当前工程目录输入：

```matlab
launch_ratio_esc       % 中文交互面板
run_demo              % 导出五个阶段的静态图、数据与ESC动画
run_acceptance        % 算法、Simulink、RL验收并写实际报告
qa_ui                 % 实际界面回调、截图、播放/暂停与导出检查
```

用面板先切换A到E五个阶段，再试不同初值、噪声和延迟。参数修改后，下次播放或重置会重新仿真。导出文件保存到 `results/ui_时间戳`。数值时间参数必须是0.05 s的整数倍，错误会显示在状态栏。

播放是已完成的**因果闭环仿真日志回放**，不是每一帧重新计算控制器。仿真器按时间顺序产生反馈，每一步只能用当前和过去的测量；预先运行完整仿真以便回放，不等于提前把答案交给优化器。

## 2. 五阶段的意义

| 阶段 | 做什么 | 不应误解为 |
|---|---|---|
| A 静态曲线 | 评价器扫描功率曲线，并显示固定工作点 | 已经做了在线控制 |
| B 固定参考反馈 | 固定目标转速比，检查一阶执行响应、限速与测量链 | 已经知道最低功率点 |
| C 微扰观察 | 中心固定，观察扰动、高通、解调、低通梯度 | 中心值在寻优 |
| D 在线ESC | 负梯度更新中心值，持续调整转速比 | 直接读取完整曲线或解析梯度 |
| E RL接口验证 | 随机连续动作通过同一对象和测量链运行 | 训练完成的TD3或Agent-PID |

建议在C阶段分别输入0.8、0.9和1.1：左侧估计梯度为负，右侧为正，附近趋近零。D阶段仍会存在微扰，因此最优附近不是一条完全水平的直线。

## 3. 模型与更新顺序

统一变量 `eta = Omega_upper / Omega_lower`，默认范围 `[0.75, 1.25]`。功率对象：

```text
J = 1 + curvature * (eta_actual - eta_optimum)^2
curvature = 4
eta_optimum = 0.9
变化场景：t >= 300 s 后 eta_optimum = 1.05
```

该曲线只是假设沿恒推力条件得到的功率映射，不包含真实共轴气动计算。0.9、功率曲率、执行时间常数和范围都是调试参数，不是文献结论的实机复现。

每个0.05 s采样时刻严格按以下顺序：

1. 根据当前实际转速比和隐藏对象工况计算真实功率。
2. 经过测量延迟，再加入独立高斯噪声，形成当前测量。
3. 控制器接收当前测量，估计梯度并生成参考。
4. 对参考进行边界和变化率限制。
5. 对象推进到下一采样时刻。

一阶对象使用精确离散化：`eta_next = r*eta + (1-r)*eta_ref`，其中 `r=exp(-Ts/tau)`。测量延迟以整数样本FIFO实现，起始缓冲区填初始功率。噪声标准差0.02指参考功率1的2%，不是当前功率的2%。

## 4. ESC公式与因果边界

控制器状态包括中心值、功率基线、梯度、上一参考及采样计数。高通和低通用固定系数递推：

```text
sinusoid = sin(2*pi*f*k*Ts)
highpass = J_measured - bias
bias_next = bias + (1-exp(-omega_h*Ts))*highpass
demod = (2/amplitude)*highpass*sinusoid
gradient_next = gradient + (1-exp(-omega_l*Ts))*(demod-gradient)
center_next = project(center - gain*Ts*gradient_next)
eta_request = center_next + amplitude*sinusoid
eta_ref = bounded_slew_limit(eta_request, previous_reference)
```

C阶段关闭中心更新，D阶段打开。中心边界为 `[lower+amplitude, upper-amplitude]`，为微扰保留余量；默认即 `[0.77,1.23]`。

`controller_config` 使用白名单，只复制控制器所需参数。`esc_step` 不接收对象配置、真实功率、真实最优点、解析梯度或离线搜索结果。图中的完整曲线和最优点属于评价器，可隐藏，隐藏与否不改变日志。

```matlab
c = ratioesc.config('initialRatio',1.2,'noiseSigma',0.02,'delay',0.5);
p = ratioesc.controller_config(c);
s = ratioesc.esc_reset(p,1.2,1.36); % 初始功率应来自初始测量
[reference,s,diagnostic] = ratioesc.esc_step(s,1.36,1.2,true,p);
s = ratioesc.freeze(s,true);
s = ratioesc.freeze(s,false);
```

冻结或测量无效时保持上一执行参考，不更新估计器；恢复时重新初始化滤波器，并等待一个扰动周期后恢复学习。暂停面板仅暂停回放，不能代替该算法API的冻结。

## 5. Simulink模型

```matlab
[file,model] = build_simulink(ratioesc.config());
open_system(file);
```

模型保存于 `models/ratio_esc_closed_loop.slx`。模型工作区保存配置和预生成噪声/工况输入，打开保存后的模型可直接运行，不依赖基础工作区的同名变量。

顶层分别为ESC、执行动态、隐藏功率模型、测量链。打开ESC可以看到正弦微扰、高通基线递推、同频解调、低通梯度、负梯度积分、中心投影和参考限速；不是整套算法塞进单个黑箱。

本轮Simulink模型用于**健康测量信号下**的离散数值一致性验证，支持噪声、延迟和最优点变化。无效数据及冻结恢复由MATLAB控制器API单独实现和测试，未宣称该部分已在Simulink中等价展开。Simulink只支持C/D控制器配置；B的独立响应验证由MATLAB阶段运行器完成。

同一次比较使用相同的采样时刻和预生成噪声，比较每个采样点的实际转速比、参考和功率，不只比较最终数值。测试后恢复默认模型配置。

## 6. 强化学习接口

```matlab
env = ratioesc.make_rl_env(ratioesc.config());
validateEnvironment(env);
observation = reset(env);
[observation,reward,isDone] = step(env,0.95);
```

- 连续动作：参考转速比，范围 `[0.75,1.25]`；环境再次限幅，再经过与ESC相同的执行限速。
- 每次动作保持1 s，内部执行20个0.05 s对象步。
- 观测4×1：归一化实际转速比、归一化已执行参考、本动作窗口平均测量功率、与上一窗口的功率均值差。
- 奖励：本窗口平均测量功率的负值。它不是功率后悔值，不使用隐藏最优答案。
- 回合长度600 s；结束后必须reset。非有限动作报错，有限越界动作投影至合法范围。
- R2022b通过 `LoggedSignals` 保存内部状态和延迟队列；它不作为策略输入。带延迟/隐藏工况的观测不保证是完整Markov状态。
- ESC和RL作为替代参考生成器，不同时驱动对象。本轮没有神经网络、TD3训练或训练结果。

下一步TD3只需要接这个环境的动作与观测规格，并另行设计训练集、验证集和评价预算；不要把真实最优点加入观测或奖励。

## 7. 结果与验收口径

`results/acceptance/report.md` 和 `scenarios.csv` 保存真实运行结果。未通过项会保留，且批量入口以错误状态退出。`results/ui_qa` 保存界面截图和导出检查结果。

最后100 s超额功率：`100 * mean(J_true/J_optimum - 1)`。真实功率只用于评价，包含持续微扰的功率代价。固定1.0基线使用相同初始状态、执行动态和对象工况。

收敛时间采用完整50 s后向均值低于3%且其后不再越线的时刻，因此即使初始点已经接近最优，也至少需要观察50 s。未收敛记NaN。最优点变化后重新计算该窗口。

导出包含 `overview.png`、可编辑 `overview.fig`、`run.mat`、`run.csv`、`metrics.csv`，在线演示另有32帧 `online_process.gif`。CSV中的 `truePower`、`optimum`、`offlinePower` 为离线评价字段，不可直接作为后续Agent的观测。

## 8. 三人可并行接手的边界

| 技术线 | 可修改内容 | 共享接口 |
|---|---|---|
| ESC算法 | 参数整定、滤波、梯度估计与冻结策略 | `esc_reset / esc_step / freeze` |
| 对象与物理升级 | 用恒推力标定数据替换代理曲线，补充偏航与分配可行性 | `power_map / plant_advance / measure` |
| 实验、展示与RL | 场景、评价、演示、未来训练器 | `run / metrics / make_rl_env` |

替换物理对象时，控制器不应获得新的隐藏参数。真实电功率、总推力/偏航约束、SITL/HITL和硬件接口属于后续工作。

## 参考依据

- [MathWorks: Extremum Seeking Control原理](https://www.mathworks.com/help/slcontrol/ug/extremum-seeking-control.html)
- [MathWorks: rlFunctionEnv](https://www.mathworks.com/help/reinforcement-learning/ref/rl.env.rlfunctionenv.html)，本工程按本机R2022b接口实现。
- [MathWorks: validateEnvironment](https://www.mathworks.com/help/reinforcement-learning/ref/rl.env.basicgridworld.validateenvironment.html)

本工程的代理曲线及数值设置是工程测试设计，不应作为上述文献或Opazo研究的实测数据引用。
