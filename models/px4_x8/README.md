# PX4 X8 Simulink 模型线

## 文件角色

- `air.slx`：只读的八旋翼飞控与 6DOF **基线模型**。已在 MATLAB R2022b 手动更新并完成 0--10 s 仿真（10001 个样本）。
- `air_spare.slx`：由基线复制的 **M0-A 开发快照**。它只新增观测支路，不改变既有飞控控制律：惯性速度、水平地速代理、8 路最终 PWM、及由当前植株映射得到的 RPM 估算。
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
