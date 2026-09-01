# PX4 X8 Simulink 模型线

## 文件角色

- `air.slx`：只读的八旋翼飞控与 6DOF **基线模型**。已在 MATLAB R2022b 手动更新并完成 0--10 s 仿真（10001 个样本）。
- `air_spare.slx`：由基线复制的 **当前开发模型**（M0-C 装入后）。在 M0-A 观测支路（惯性速度、水平地速代理、8 路 PWM、RPM 估算、`P_est`/`E_est`、8 位约束标志、35 维日志总线）之上，已按阶段叠加 M0-B 速度闭环与安全回退、M0-C 速度在线 ESC 接口；`speed_loop_enable=0` 时与 `air.slx` 逐位一致。
- `air_m0a.slx` / `air_m0b.slx` / `air_m0c.slx`：M0-A / M0-B / M0-C 各阶段**验收通过后的冻结快照**，后续阶段不再修改（`air_m0c.slx` SHA256 `f9be88df…`）。
- `m0c_vref_esc.m` + `add_air_m0c_esc.m`：M0-C 优化器接口（包装 `modules/ratio_esc` 内核，输入仅 t/v/P_e/E_e/attitude/flags，输出仅 v_ref）与其原子安装脚本；`test_m0c_esc_unit.m`、`run_air_m0c_trials.m` 为单元测试与配对试验入口。
- `run_air_m0b_tests.m`、`run_air_m0b_safety_injection.m`、`run_air_m0a_baseline_compare.m`：结构变更回归三件套（速度双口径验收、逐位故障注入、旁路零差异）。
- `init_model.m`：添加模型路径并加载模型。
- `run_baseline.m`、`inspect_interfaces.m`：非破坏性基线运行与接口导出入口；生成的原始结果写到本地 `results/`，默认不提交。

## 快速复现

在 MATLAB 中从任意目录执行：

```matlab
addpath('models/px4_x8')
init_model('air')
result = run_baseline
interfaceResult = inspect_interfaces
```

模型依赖 MATLAB/Simulink R2022b、Stateflow，以及模型引用的 `px4lib`、`px4Sensorslib`、`shared6dof` 和 `sharedtransform` 库。若缺少这些库，先恢复本机原有的 PX4/Simulink 支持包路径。

## 边界与下一步

当前模型已具备 RC/解锁、姿态控制、固定 X8 混控、8 路 PWM、PWM 至力/力矩、6DOF 与姿态反馈。它还没有电池、电流、真实 RPM、电功率、`eta_ref` 受约束分配器、速度外环或 Harness；因此不能据此宣称节能率或算法已经部署飞控。详细接口见 [`docs/interfaces/M0A_OBSERVABILITY.md`](../../docs/interfaces/M0A_OBSERVABILITY.md)。
