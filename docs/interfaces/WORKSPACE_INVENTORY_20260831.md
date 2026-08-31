# 当前工作区文件清单

盘点日期：2026-08-31。此清单描述现有文件的作用与当前状态；不移动、不重命名任何已有模型或归档结果。

## 1. 根目录：模型、脚本与文档

| 文件 | 用途 | 当前状态 | 后续处理 |
|---|---|---|---|
| `air.slx` | 原始 PX4/Simulink 八旋翼飞控与 6DOF 基线模型 | 已成功完成 10 s 仿真 | 只读基线；不直接开发 |
| `air_spare.slx` | 从 `air.slx` 复制的开发副本 | 已加入 M0-A 速度、PWM 与 RPM 估算观测支路；原快层控制逻辑未改 | M0-A 起唯一修改对象 |
| `run_air_baseline.m` | 更新、仿真并归档 `air` 的非破坏性基线脚本 | 已成功执行 | 后续可泛化为支持指定模型名 |
| `inspect_air_interfaces.m` | 更新模型、导出关键子系统和 6DOF 端口连接 | 已成功执行 | M0-A 后再次运行验证接口变化 |
| `add_air_m0a_velocity_observability.m` | 在 `air_spare` 中加入 6DOF 惯性速度与水平速度观测链，并保存模型 | 已通过 GUI 执行与仿真验证 | M0-A 后续日志与功率模块的可复现安装脚本 |
| `add_air_m0a_actuator_observability.m` | 在快层混控后的 8 路 PWM 处加入 PWM 与估算 RPM 观测链，并保存模型 | 已通过 GUI 执行与仿真验证 | M0-A 功率与约束模块的执行器输入 |
| `AIR_SLX_AUDIT.md` | `air.slx` 静态结构、依赖和差距审计 | 已完成；其中早期“尚未确认运行”的表述已被后续实际仿真验证覆盖 | 作为结构参考；以路线文件为执行依据 |
| `PROJECT_EXECUTION_ROADMAP.md` | 全项目阶段、接口、验收、数据回灌与变更规则 | 当前执行基线 | 每次策略/接口/验收改变时同步更新 |
| `CURRENT_WORKSPACE_STATUS.md` | 本文件 | 当前文件盘点 | 阶段交付后更新 |

## 2. 方向与参考资料

| 位置 | 内容 | 用途 |
|---|---|---|
| `共轴八旋翼在线功率优化-任务定义与技术路线.pdf` | 项目任务定义、M0–M4 路线、风险与里程碑 | 技术路线的原始依据 |
| `文献/` | 五篇共轴旋翼、功率优化与相关研究 PDF | 建模、功率/干扰机理、论证与报告引用 |

这些文件不宜混入仿真输出目录；未来放入 Git 时建议归入 `docs/` 与 `references/`，并先确认公开仓库的版权与分发许可。

## 3. 已归档的可复现结果

| 位置 | 结论 | 包含内容 |
|---|---|---|
| `results/air_baseline/20260831_161623/` | **PASS**：`air` 从 0 到 10 s，共 10001 样本，无错误 | `baseline.mat`、`summary.csv`、`top_level_blocks.csv` |
| `results/air_interface_inspection/20260831_164903/` | **PASS**：发现 1 个 6DOF 块，导出 59 条端口连接 | `interface_inspection.mat`、`port_connectivity.csv` |

这些结果是阶段 0 的证据，应保留。后续每次实验使用新时间戳目录，不覆盖此处内容。

## 4. 当前模型能力与缺口

已有：RC/解锁、姿态控制、固定 X8 混控、8 路 PWM、PWM 至推力/力矩、6DOF、姿态/角速度/加速度反馈。

已新增：从 6DOF `Ve` 分支的 `m0a_Ve_inertial_mps` 与 `m0a_horizontal_speed_mps`；后者定义为 `sqrt(Ve_x^2 + Ve_y^2)`，目前仅是无风条件的地速代理。已在 `air_spare` 的 0–10 s 仿真中验证，日志包含 10001 个样本。

已新增：从 `AttitudeControl/Demux` 分支的 `m0a_motor_pwm_us[8]` 与 `m0a_motor_rpm_est[8]`。RPM 依据当前植株的即时映射 `rpm = (PWM_us-1000) * 60/(2*pi)` 估算；它反映当前模型的命令转速，不等同于带电机动态与传感器误差的实测 RPM。

尚缺：标准速度接口、速度参考与速度外环、8 路 RPM 输出、功率/能耗模型、`eta_ref` 和 X8 受约束分配器、统一约束总线、Harness、真实数据校准与 SITL 接口。

因此当前模型是“可运行飞控与动力学基座”，不是已经完成的能耗优化仿真平台。

## 5. 建议的未来 Git 结构（暂不移动）

```text
docs/                    路线、接口、审计、实验说明
references/              可公开分发的参考资料或引用清单
models/px4_x8/           air 基线与各验收快照
modules/speed_esc/       M0/M1 慢层速度算法
modules/ratio_esc/       同学维护的 eta 算法模块
integration/air_esc/     算法适配、安全层、控制分配、日志接口
harness/                 多场景与批量试验配置
tests/                   单元、接口、回归测试
results/                 本地归档；默认不提交大体积原始结果
```

提交前应忽略 `slprj/`、`*.slxc`、Simulink 自动保存文件和未筛选的大型结果文件；可提交小型 CSV 摘要、配置、脚本和图表生成代码。
