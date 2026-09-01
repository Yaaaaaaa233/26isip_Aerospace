# 开发状态与下一步

## 总览：算法线三模块与平台线尚未集成

| 工作线 | 当前状态 | 可作出的结论 | 不能作出的结论 |
|---|---|---|---|
| `modules/ratio_esc` | 可运行的单变量在线 ESC、Simulink 一致性与代理对象验收 | 代理对象上存在受边界约束的因果寻优行为 | 真实 X8 节能、偏航安全、已部署飞控 |
| `modules/speed_esc` | 2026-09-01 并入。平飞速度 ESC（η=1），窗口回归估计为主、解调为对照；14 单元测试、14 组 Python 逐样本复现、6 组 Simulink 一致性、74 性能场景 | 代理功率曲线上速度变量因果寻优行为成立，且与原 Python 方案逐样本一致 | 真实 X8 节能、速度定位全场景达标（63/74，未达标场景如实记录）、实机飞控 |
| `modules/speed_rl_residual` | 2026-09-01 并入。速度基线之上的 TD3 残差修正（虚拟风场/电池/轨迹代理）；11 单元测试、20 未见风种子零硬约束违规 | 代理对象上残差接口可用：可观测风解析残差 -1.25% 功率（19/20 种子）、TD3 恒定风候选 -3.02% | 不规则风下 RL 有效（TD3 候选 0–1/20 种子胜出，如实记录为训练起点）、任何飞行相关结论 |
| `models/px4_x8` | 阶段 0、M0-A、M0-B、M0-C 完成（M0-C 于 2026-09-01 验收通过） | 旁路与原基线零差异（真 `Ve` 维度断言）；速度俯仰通道名义误差 0.03 m/s 量级、扰动下有界；位 1/4/6/7 故障注入全链保护通过（含 13 s 严格恢复）；M0-C：ESC 接口封装 + 五组配对试验收敛/可复现（能耗 ΔE≈0，平坦功率面） | `eta` 分配器（M2）、真实功率模型校准、M1 扰动/噪声/时延、扰动场景长稳定窗口 |

飞控平台的唯一执行基线是 [`PROJECT_EXECUTION_ROADMAP.md`](PROJECT_EXECUTION_ROADMAP.md)。M0-B 复核缺陷已修复并通过独立再验收（[`evidence/M0B_RERUN_20260901.md`](evidence/M0B_RERUN_20260901.md)、[`evidence/M0B_REACCEPT_CODEX_20260901.md`](evidence/M0B_REACCEPT_CODEX_20260901.md)）。**M0-C 已于 2026-09-01 完成并通过验收（执行基线 [`interfaces/M0C_SPEED_ESC.md`](interfaces/M0C_SPEED_ESC.md)，证据 [`evidence/M0C_TRIALS_20260901.md`](evidence/M0C_TRIALS_20260901.md)）：`ratio_esc` 内核封装为 `m0c_vref_esc` 接口并替换优化器占位，快照 `air_m0c.slx`。当前下一项是 M1：扰动、噪声与时延鲁棒性**；不接入转速比 ESC，也不做 RL。

**独立复验确认（2026-09-01，`00fd67e`）**：基线、四个速度场景、四类故障注入均实际复跑通过；另在保存快照上验证姿态保护和完整功率故障恢复（9.001 s 释放 fallback、11 s 回到 active/9 m/s）。详细证据与非阻塞建议见 [`evidence/M0B_REACCEPT_CODEX_20260901.md`](evidence/M0B_REACCEPT_CODEX_20260901.md)。M0-B 阶段可放行；M0-C 开始实现成本窗口前须统一路线中状态 1/2 的歧义，排除 warmup、仅使用满足稳定条件的 active 样本。通过范围限于当前模型的速度通道及监视器/参考回退，不扩展为真实飞行安全或真实节能结论。

### 已验证的模型平台证据

- `air.slx`：MATLAB R2022b 手动更新、仿真 0--10 s 成功，10001 个样本；摘要见 [`evidence/air_baseline_20260831_161623_summary.csv`](evidence/air_baseline_20260831_161623_summary.csv)。
- 接口审计：1 个 6DOF 块、59 条端口连接；见 [`evidence/air_interface_20260831_164903_port_connectivity.csv`](evidence/air_interface_20260831_164903_port_connectivity.csv)。
- `air_spare.slx`：M0-A 观测层完整——速度、PWM、8 维 RPM 估算、`P_est`/`E_est`（未校准估算，来源标志 0）、8 位约束标志、35 维统一日志总线与 `optimizer_enable=0` 基线模式。
- M0-A 历史验收（2026-08-31）：三个命名信号逐样本最大差 0，见 [`evidence/air_m0a_baseline_compare_20260831_201430.csv`](evidence/air_m0a_baseline_compare_20260831_201430.csv)；稳定快照 `models/px4_x8/air_m0a.slx`。2026-09-01 发现旧脚本将 DCM 误标为 `Ve`；本次已额外核验当前 M0-B 旁路下真正的 `[10001 3]` 惯性速度，与 `air` 差异仍为 0，详见独立复核报告。
- M0-B 修复与再验收（2026-09-01，[`evidence/M0B_RERUN_20260901.md`](evidence/M0B_RERUN_20260901.md)）：flags_raw 链路修复后逐位注入位 1/4/6/7 全链"触发→frozen 0.000 s→fallback 0.500 s→（位 6）恢复"；速度验收双口径——名义（roll 正弦置 0）9 m/s 均值误差 0.032 m/s、失跟 0%，扰动 5/9 m/s 1.615/1.598 m/s（与复核复跑一致）；旁路比对修正 `Ve` 端口后三信号差 0。稳定快照 `models/px4_x8/air_m0b.slx` 已替换为修复版。
- M0-C 验收（2026-09-01，[`evidence/M0C_TRIALS_20260901.md`](evidence/M0C_TRIALS_20260901.md)）：`ratioesc` 内核白名单封装 `m0c_vref_esc`（输入仅 t/v/P_e/E_e/attitude/flags，输出仅 v_ref），Interpreted MATLAB Fcn + 每输入 0.05 s ZOH 接入 selector 入 3；成本窗口按 status==2 且位 5 静默口径；三组名义配对（7/9/11 m/s）esc 均收敛（4/4/8 s）、无饱和无触发，复现组逐样本差 0；ΔE −0.12%~−0.36% 为窗口掩码伪差（P 均值 251 W 一致，平坦功率面，无可宣称节能）；旁路差 0 与注入回归（含 13 s 恢复）全绿。稳定快照 `models/px4_x8/air_m0c.slx`。

### 算法线速度模块证据（2026-09-01 并入）

- `modules/speed_esc`：14 项单元测试、14 组原 Python 逐样本复现（最大误差 5.33e-15）、6 组 MATLAB/Simulink 一致性（最大差 1.25e-14）全部通过；正式种子 11--20 性能验收功率指标 74/74 达标、速度定位指标 63/74（11 个未达标场景多为二次曲线噪声场景，如实列出）。证据：[`evidence/speed_esc/report.md`](evidence/speed_esc/report.md)、[`evidence/speed_esc/scenarios.csv`](evidence/speed_esc/scenarios.csv)。
- `modules/speed_rl_residual`：11 项单元测试与适配器契约通过；20 个未见不规则风种子零硬约束违规；可观测风解析脚本 19/20 种子优于固定基准（平均功率 480.255→474.229 W，约 -1.25%）；TD3 恒定风候选同类场景 477.825→463.379 W（-3.02%），但迁移到不规则风 0/20 胜出，随机恒定风候选 1/20——均为课程训练起点而非最终策略。证据：[`evidence/speed_rl_residual/report.md`](evidence/speed_rl_residual/report.md)、[`evidence/speed_rl_residual/policy_evaluation.csv`](evidence/speed_rl_residual/policy_evaluation.csv)、TD3 检查点 `td3_candidate_*.mat`。

## 已完成

- 问题定义：在满足恒推力假设的代理对象上，在线最小化上下桨转速比对应的归一化功率。
- 五阶段演示：静态对象、固定参考反馈、微扰观察、在线ESC、RL环境接口验证。
- 因果边界：ESC和RL观测均不可读取完整功率曲线、真实最优点或解析梯度。
- 鲁棒性测试：多初值、噪声、测量延迟、隐藏最优点变化、边界、冻结和无效样本。
- Simulink：原生离散块展开微扰、高通、解调、低通、下降、投影和限速；与MATLAB健康测量仿真逐采样点一致。
- 协作材料：交互面板、模型结构图、过程动画、可读报告、测试与自动验收脚本。

## 已知局限

- `J = 1 + 4(eta - eta_optimum)^2` 是代理曲线，不是实验功率数据。
- 当前“恒推力”是建模假设，尚未通过控制分配计算实际总推力、偏航力矩或八电机饱和。
- Simulink一致性目前覆盖健康测量信号；冻结和无效数据恢复在MATLAB控制器API中验证。
- RL接口已经可运行，但没有训练策略，不能以此宣称强化学习优于ESC。
- 未接PX4、QGC、SITL/HITL、真实电压电流、螺旋桨台架数据或实机。
- `speed_esc` 的两条速度功率曲线与 `speed_rl_residual` 的风场/电池/轨迹代理均为虚拟对象，三者功率模型互不相同，跨模块不得直接横比节能率；`speed_esc` 速度定位指标 63/74（未全达标）；`speed_rl_residual` 的 TD3 候选在不规则风下尚未胜出基线。

## 下一步优先级

1. 用台架、CFD/BEMT或文献校准数据替换代理功率对象，明确参数来源、适用区间和误差。
2. 建立给定总推力与零偏航力矩条件下的上下桨分配器，输出可行性、饱和和约束违规标志。
3. 将 `measuredPower` 对接真实或SITL的电压、电流与时间戳；加入日志回放测试。
4. 在固定的训练/验证场景划分下训练TD3等策略，并与ESC、固定比值基线使用同一扰动和评价口径比较（`speed_rl_residual` 的课程训练与未见种子评估口径可直接沿用）。
5. 再考虑速度寻优与转速比寻优的交替或多频耦合，不能在单变量对象未标定前宣称二维优化成果。
6. M0-C 完成后评估是否用 `modules/speed_esc` 的回归估计器内核替换 `M0C v Ref ESC` 中的解调内核，并按 `M0C_SPEED_ESC.md` §7 重新验收。

## 当前可引用的结果边界

仓库内的验收通过只支持以下表述：

> 在恒推力假设下的归一化代理模型中，所实现的单变量转速比ESC能够在预设噪声、延迟和最优点变化场景下保持有限、受边界约束的在线寻优行为，并与其原生Simulink离散实现一致。

> 在虚拟速度功率代理曲线（二次/三次）上，平飞速度ESC（窗口回归梯度估计）在正式种子下功率指标 74/74 场景达标、速度定位 63/74 场景达标，且与原Python方案逐样本一致；在不规则风场虚拟代理中，可观测风解析残差可在多数未见种子上降低平均代理功率，TD3 残差候选在恒定风场景有效、在不规则风场景尚未超过基线。

不支持“真实八旋翼节能百分比”“已解决偏航影响”“强化学习优于传统控制”或“算法已部署飞控”等表述。
