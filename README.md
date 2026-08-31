# 26isip_Aerospace

共轴八旋翼在线能耗优化协作仓库。

当前仓库的第一个可运行模块是 **上下桨转速比在线极值寻优控制（ESC）**。它用一个明确标注为“恒推力假设”的归一化功率代理对象，验证在线寻优的因果闭环、扰动鲁棒性、Simulink一致性和强化学习环境接口。它不是实机飞控、不是电子调速器（ESC），也不构成真实X8节能率或偏航稳定性结论。

## 快速开始

环境要求：MATLAB R2022b；运行Simulink模型需要 Simulink；运行RL接口需要 Reinforcement Learning Toolbox。

```matlab
cd modules/ratio_esc
START_HERE                 % 打开中文交互演示面板
run_demo                   % 导出A--E阶段的结果图和动画
run_acceptance             % 运行自动验收并写出实际报告
qa_ui                      % 检查交互面板、播放、暂停与导出
```

在交互面板中，从“C 微扰观察”开始，再切到“D 在线ESC”。播放展示的是已经完成的因果仿真日志回放；仿真本身每一步只使用当前和过去的测量功率。

## 当前成果

- 上下桨转速比定义为 `eta = Omega_upper / Omega_lower`，默认测试范围为 `[0.75, 1.25]`。
- 完成静态对象、固定参考反馈、微扰观察、完整在线ESC和RL环境接口五个阶段。
- 完成MATLAB离散实现与原生Simulink离散模型的一致性验证。
- 完成12项单元测试和35组验收场景：无噪声三初值、2%测量噪声、0.5 s延迟、工况变化及RL完整回合。
- 已验证的代理模型结果：2%噪声叠加0.5 s延迟时10个随机种子均通过3%最终超额功率阈值；具体口径见 [验收报告](docs/evidence/acceptance-report.md)。

![在线ESC过程](docs/evidence/online_process.gif)

## 目录

```text
modules/ratio_esc/       可运行MATLAB、Simulink与RL接口模块
docs/COLLABORATION.md    模块边界、接口和协作约定
docs/DEVELOPMENT_STATUS.md 当前完成项、局限与下一步
docs/evidence/           已核验的报告、过程图和模型结构图
```

## 协作原则

- 控制器只能接收测量功率、实际转速比、采样时间和有效性标志；完整功率曲线、真实最优点及解析梯度不得传入控制器或RL观测。
- 物理对象升级应替换 `power_map`、`plant_advance` 和 `measure`，不应修改ESC的因果接口。
- 不提交 `slprj`、`.slxc`、临时动画帧、重复日志或本地自动保存文件；需要共享的证据放入 `docs/evidence`。
- 提交前运行 `run_acceptance`。涉及面板或导出的修改，再运行 `qa_ui`。

详细的接口和可并行认领项见 [协作说明](docs/COLLABORATION.md)，当前状态与已知局限见 [开发状态](docs/DEVELOPMENT_STATUS.md)。
