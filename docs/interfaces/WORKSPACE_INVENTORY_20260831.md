# 当前工作区文件清单

盘点日期：2026-08-31。此清单描述现有文件的作用与当前状态。2026-08-31 起本地工作区已按第 5 节结构整理（依据：用户指示，且 Git 仓库结构已建立运行）；模型与脚本位于 `models/px4_x8/`，文档位于 `docs/`，历史归档 `results/` 原地未动。此后移动或重命名模型/归档前须先更新本清单。

## 1. `models/px4_x8/`：模型与脚本（文档在 `docs/`）

| 文件 | 用途 | 当前状态 | 后续处理 |
|---|---|---|---|
| `air.slx` | 原始 PX4/Simulink 八旋翼飞控与 6DOF 基线模型 | 已成功完成 10 s 仿真 | 只读基线；不直接开发 |
| `air_spare.slx` | 从 `air.slx` 复制的开发副本 | **2026-09-01 复核判定 M0-B 验收不通过（P1 缺陷：`M0A Constraint Flags` 出 1 → `M0B Flags Override` 入 1 连线丢失，透传位 1/2/4/6/7 恒 0，故障注入证明保护链路断裂）**；速度外环本体、限幅/限速与旁路零差异经复核确认有效 | 修复轮唯一修改对象：按路线图 §6 修复清单执行，从 `air_m0a.slx` 恢复后重装 |
| `air_m0a.slx` | M0-A 验收通过后的稳定快照 | 2026-08-31 由 `air_spare` 另存；与 `air` 基线比对零差异 | 冻结快照；后续阶段不再修改 |
| `air_m0b.slx` | M0-B 稳定快照 | **含 P1 缺陷，已被复核否定（`M0B_REVIEW_20260901.md`），只能作为待修复阶段快照** | 修复轮全绿后重新另存 |
| `add_air_m0b_speed_loop.m` | 原子安装 M0-B 层：参考选择器+安全监视器、PI 速度控制器、算术融合俯仰插入、flags 位 3/5 普通方块覆盖（含运行时阈值常量）、Ve_x 观测出口、`m0b_log_bus`；保存前先做功能检查（enable=1 时 ve_x 必须离开 0） | 已执行并验证 | M0-C 复用此模式 |
| `add_air_m0b_controller_gains.m` | 把控制器 `Kp`/`Ki` 从 chart 字面量提升为根层常量输入（重建 7 输入 chart，避免脚本编辑断线问题） | 已执行（默认 Kp=0.12、Ki=0.04） | 扫参见 `diag_m0b_gain_sweep` |
| `run_air_m0b_tests.m` | M0-B 验收（2026-08-31 版）：5/9 m/s 稳态、6→9 m/s 阶跃、安全演示 | 复核指出四项缺口：阶跃前窗口恒空（pre 指标 NaN）、注释阈值 0.5 与代码 2.0 不一致、5 m/s 场景不检查误差、安全演示全程 active=0（8 次转换不能证明完整恢复） | 修复轮按路线图 §6.4 重写为名义/扰动双口径 |
| `diag_m0b_pitch_sign.m` / `diag_m0b_pitch_gain.m` | 俯仰符号与增益标定实验（内存改参数，不保存模型） | 已执行：`pitch_cmd>0 → θ+ → 加速 -x`，每单位指令约 15 m/s² | 证据链保留 |
| `diag_m0b_gain_sweep.m` / `diag_m0b_test_postmortem.m` | 增益扫描与试验数据复核 | 已执行（0.12/0.04 相对最优；复核正确指出扫描不足以证明扰动误差为物理下限） | 证据链保留 |
| `run_air_baseline.m` | 更新、仿真并归档 `air` 的非破坏性基线脚本 | 已成功执行 | 后续可泛化为支持指定模型名 |
| `inspect_air_interfaces.m` | 更新模型、导出关键子系统和 6DOF 端口连接 | 已成功执行 | M0-B 前再次运行验证接口变化 |
| `add_air_m0a_velocity_observability.m` | 在 `air_spare` 中加入 6DOF 惯性速度与水平速度观测链，并保存模型 | 已通过 GUI 执行与仿真验证 | M0-A 后续日志与功率模块的可复现安装脚本 |
| `add_air_m0a_actuator_observability.m` | 在快层混控后的 8 路 PWM 处加入 PWM 与估算 RPM 观测链，并保存模型 | 已通过 GUI 执行与仿真验证 | M0-A 功率与约束模块的执行器输入 |
| `add_air_m0a_power_measurement.m` | 在 `air_spare` 根层加入可替换 `M0A Power Measurement` 子系统（`P_est`、`E_est`、来源标志 0=estimated），从根级 PWM 指令网分支 | 已执行并验证：`P_est` 与 `C_M·Σω³` 重算最大偏差 5.7e-14 W | M2 起替换为电机/ESC/电池模型或实测功率 |
| `add_air_m0a_constraints_and_logbus.m` | 加入姿态/角速度观测出口、`M0A Constraint Flags`（8 位）、35 维统一日志总线、`optimizer_enable=0`，并写场景配置 | 已执行；与 `fix_m0a_rpm_width_and_zoh.m` 联合验证通过 | 阈值在 M0-B 校准 |
| `fix_m0a_rpm_width_and_zoh.m` | 修正 rpm 派生链：Fcn 块只能输出标量，替换为逐元素 Subtract+Gain（总线级与执行器级两处）；ZOH 初始条件保持 0 并在验收中把 t<5 ms 作为初始化窗 | 已执行；rpm 现为 8 维，与 `9.5493·(pwm-1000)` 零误差 | 无 |
| `write_m0a_scenario_config.m` | 写 M0-A 场景配置归档（阈值、总线布局、optimizer_enable=0） | 已执行 | M0-B 演进为场景配置结构 |
| `run_air_m0a_baseline_compare.m` | M0-A 验收：`air` 与 `air_spare` 同场景 10 s 比对，并复核日志总线 | 复核指出：原第 113 行把 6DOF 输出 4（DCM）误标为 `Ve`；复核者已用真输出 1 补证差 0，零差异结论不变 | 修复轮改标输出 1 并加 `[N×3]` 维度断言 |
| `AIR_SLX_AUDIT.md` | `air.slx` 静态结构、依赖和差距审计 | 已完成；其中早期“尚未确认运行”的表述已被后续实际仿真验证覆盖 | 作为结构参考；以路线文件为执行依据 |
| `PROJECT_EXECUTION_ROADMAP.md` | 全项目阶段、接口、验收、数据回灌与变更规则 | 当前执行基线 | 每次策略/接口/验收改变时同步更新 |
| `CURRENT_WORKSPACE_STATUS.md` | 本文件 | 当前文件盘点 | 阶段交付后更新 |

## 2. 方向与参考资料

| 位置 | 内容 | 用途 |
|---|---|---|
| `references/共轴八旋翼在线功率优化-任务定义与技术路线.pdf` | 项目任务定义、M0–M4 路线、风险与里程碑 | 技术路线的原始依据 |
| `references/文献/` | 五篇共轴旋翼、功率优化与相关研究 PDF | 建模、功率/干扰机理、论证与报告引用 |

这些文件不宜混入仿真输出目录；未来放入 Git 时建议归入 `docs/` 与 `references/`，并先确认公开仓库的版权与分发许可（2026-08-31 整理：本地已移入 `references/`，仍未入仓库）。

## 2a. 2026-08-31 结构整理记录

- **本地工作区已按第 5 节结构整理**：文档移入 `docs/`，模型与全部脚本移入 `models/px4_x8/`（与仓库布局同构，`M0A_OBSERVABILITY.md` 中的 `models/px4_x8/*.slx` 路径自此在本地同样成立）；参考资料此前已移入 `references/`；历史归档 `results/` 留在工作区根且原地未动；再生的 `slprj/`、`*.slxc` 缓存已删除（Simulink 自动重建，不入版本控制）。
- 全部 9 个脚本已改为按脚本自身位置定位（`mfilename` 路径）：从 `models/px4_x8/` 加载同级模型，结果统一写入工作区根 `results/`（脚本位置两级上层），从任意工作目录均可运行。
- M0-A 的五个脚本在本地与仓库 `models/px4_x8/` 两处内容保持一致；仓库旧脚本（`run_baseline`、`inspect_interfaces`、`add_m0a_*`）为带路径自适应的早期版本，与本地原始命名（`run_air_baseline` 等）并存；统一命名待协作商定，暂不改动。

## 3. 已归档的可复现结果

| 位置 | 结论 | 包含内容 |
|---|---|---|
| `results/air_baseline/20260831_161623/` | **PASS**：`air` 从 0 到 10 s，共 10001 样本，无错误 | `baseline.mat`、`summary.csv`、`top_level_blocks.csv` |
| `results/air_interface_inspection/20260831_164903/` | **PASS**：发现 1 个 6DOF 块，导出 59 条端口连接 | `interface_inspection.mat`、`port_connectivity.csv` |
| `results/m0a_config/20260831_195541/` | M0-A 场景配置：`optimizer_enable=0`、总线布局、标志阈值 | `m0a_scenario_config.mat`、`m0a_scenario_config.txt` |
| `results/air_m0a_baseline_compare/20260831_201430/` | **PASS（M0-A 验收）**：`air` 与 `air_spare` 的 `pwm_cmd`/`Ve`/`quat` 逐样本最大绝对差 0；日志总线 35×10001 复核通过 | `summary.csv`、`comparison.mat` |
| `results/air_m0a_baseline_compare/20260831_232611/` | **PASS（M0-B 装入后复验）**：旁路模式三信号最大绝对差仍为 0 | `summary.csv`、`comparison.mat` |
| `results/air_m0b_tests/20260831_234117/` | **PASS（M0-B 验收）**：四场景全过——5 m/s 稳态均值误差 1.62、9 m/s 1.60、阶跃后 1.88 m/s（roll 正弦扰动下限）；安全演示 8 次 frozen/fallback 转换且回退参考 5 m/s | 各场景 `S*.mat`、`summary.csv` |
| `results/m0b_config/` | M0-B 两版安装配置（外环参数、增益默认值） | `m0b_config.*`、`m0b_gains.mat` |
| `results/m0b_diagnostics/` | 俯仰符号/增益标定与 wrapper 拓扑导出 | `pitch_sign_diag.mat`、`wrapper_topology.txt` 等 |

这些结果是阶段 0 与 M0-A 的证据，应保留。后续每次实验使用新时间戳目录，不覆盖此处内容。

## 4. 当前模型能力与缺口

已有：RC/解锁、姿态控制、固定 X8 混控、8 路 PWM、PWM 至推力/力矩、6DOF、姿态/角速度/加速度反馈。

已新增（M0-A 完成）：从 6DOF `Ve` 分支的 `m0a_Ve_inertial_mps` 与 `m0a_horizontal_speed_mps`（`sqrt(Ve_x^2 + Ve_y^2)`，无风地速代理）；从 `AttitudeControl/Demux` 分支的 `m0a_motor_pwm_us[8]`（uint16 量化命令，1 kHz）与 `m0a_motor_rpm_est[8]`（`rpm = (PWM_us-1000)·60/(2π)` 命令转速估算，非实测）。

已新增（本次交付）：`M0A Power Measurement` 可替换子系统输出 `m0a_P_est_W`、`m0a_E_est_J` 与 `m0a_power_source`（0=estimated）。`P_est = C_M·Σω³`（`ω=clip(PWM,1000,2000)-1000`，`C_M=2.51e-7` 与植株扭矩系数严格一致），从植株实际消费的根级 PWM 指令网（未量化、250 Hz）分支；悬停约 251 W，10 s 积分 `E_est` 与均值功率×时长相对误差 4e-8。**未校准估算，不得宣称真实节能率。**

已新增（本次交付）：`M0A Constraint Flags` 8 位（pwm/rpm 饱和、姿态、偏航率、速度失跟、功率异常、信号缺失、预留；阈值均为文档化占位值）；35 维统一日志总线 `m0a_log_bus` @1 ms：`[v, P_est, E_est, power_source, att(6)=φθψ pqr, pwm(8), rpm_est(8), flags(8), optimizer_enable]`（4 ms 的 pwm/P_est 经 ZOH 对齐到 1 ms）；`m0a_optimizer_enable=0` 固定基线模式。名义 10 s 运行中，初始化窗（t<5 ms）后仅速度失跟标志按占位 `v_ref=0` 语义激活（飞机实际飞行约 8.4 m/s），其余标志全零。

已验收：`air` 与 `air_spare` 在相同 10 s 场景下 `pwm_cmd`/`Ve`/`quat` 逐样本最大绝对差为 0——观测层完全不改变飞行轨迹、姿态与执行器命令。姿态/角速度取自 `Attitude Control/quat2eul` 三输出与 `control_and_mix` 第 5 输入口 `pqr`（按已核验函数签名顺序），悬停段 φ 与 p 同相振荡（±0.207 rad / ±0.206 rad/s），量级合理。

已知细节：根级 PWM 指令网在 t=0 输出 0（包装层滞后一拍，air 原模型固有行为）；内部 `m0a_motor_pwm_us` 为 uint16 量化版（与根网最大差 1 us）。

已新增（M0-B 完成）：速度通道完整闭环——参考选择器（手动/优化器切换 + [0,15] m/s 范围与 2 m/s² 变化率限制 + warm-up 语义）、投影 PI 速度外环（`Kp=0.12`、`Ki=0.04`，`|pitch_cmd|≤0.40`、积分 ≤0.15、变化率 0.25/s）、wrapper 内俯仰注入（算术融合，旁路逐位一致）、安全监视器（硬标志冻结 0.5 s → 回退手动参考，清除 1.5 s 后重进）与 `optimizer_status`（0 基线/1 warm-up/2 active/3 frozen/4 fallback）。约束位 3/5 阈值改为运行时常量（`M0B Att Tol` 0.523 rad、`M0B Speed Tol` 1.0 m/s），位 5 语义升级为 `|v − v_ref(延迟一拍)| > tol`。`m0b_log_bus`（7 维 @1 ms）：`[v_ref, pitch_cmd, v_err, optimizer_status, speed_loop_enable, ve_x, v]`。

重要模型事实（M0-B 审计确认，M0-A 文档未覆盖）：`InputConditioning` 完全忽略 RC 输入（四路接 Terminator），roll 指令由内部正弦（幅 200 us → ±0.4 @1 rad/s）生成，pitch 常数 1500（即 0，经 `Gain2=[1 -1]` 取负），thrust 常数 0.5，yaw 0；chart `arm` 由 wrapper 内 Constant 1 提供（恒解锁）。垂直方向为原始模型固有自由落体（PWM=1500×8、P_est≈251 W 但净推力≈0）。这些均为 `air` 原模型行为，M0-A/M0-B 未改变。

尚缺：慢层 ESC 算法本体（M0-C）、`eta_ref` 和 X8 受约束分配器（M2）、真实 RPM/电功率模型与校准、Harness、SITL 接口。

因此当前模型是“可运行、可观测、可安全比较、且慢层可经俯仰通道安全操纵速度”的飞控与动力学基座，尚未接入任何能耗优化算法（M0-C 起接入）。

## 5. 工作区结构（2026-08-31 起已实施；Git 仓库同构）

```text
docs/                    路线、接口、审计、实验说明
references/              可公开分发的参考资料或引用清单
models/px4_x8/           air 基线与各验收快照 + 工作脚本
modules/speed_esc/       M0/M1 慢层速度算法（仓库）
modules/ratio_esc/       同学维护的 eta 算法模块（仓库）
integration/air_esc/     算法适配、安全层、控制分配、日志接口（仓库）
harness/                 多场景与批量试验配置（仓库）
tests/                   单元、接口、回归测试（仓库）
results/                 本地归档；默认不提交大体积原始结果
```

仓库 `26isip_Aerospace/` 与本地工作区均已按此结构建立（`references/` 因版权仅存本地）。`results/` 位于工作区根，所有脚本将新归档写入此处；历史归档不覆盖、不移动。

提交前应忽略 `slprj/`、`*.slxc`、Simulink 自动保存文件和未筛选的大型结果文件；可提交小型 CSV 摘要、配置、脚本和图表生成代码。
