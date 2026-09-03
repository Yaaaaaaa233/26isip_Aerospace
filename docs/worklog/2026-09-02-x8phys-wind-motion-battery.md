# X8 风场运动电池对象

## 本次完成

- 按 `COLLABORATION.md` 的对象边界新增 `models/px4_x8/+x8phys`。
- 实现与 `air.slx` 一致的 NED/机体坐标、电机角度/旋向、PWM 到转速/推力/反扭矩；风致旋翼来流负载；四元数刚体积分（含 `omega×Iomega`）。
- 实现电机/ESC效率、辅助功率、电池内阻端电压、电流、SOC 和能量增量。
- 输出对象诊断、累计电能和经 `map_flags` 映射的平台约束标志；`platform_step` 提供 M0-C 观测字段；未修改现有 `.slx` 或 ESC/RL 接口。
- 增加 `test_x8phys` 与使用说明；MATLAB R2022b 实测通过，零风/20 m/s 风功率分别为 334.208/430.097 W。

## 边界与后续

- 当前参数是代理/占位值，不能作为真实节能或飞行性能结论。
- 风输入为惯性坐标三维风速，尚未从 Simulink 风场端口接入。
- 后续应使用台架、CFD/BEMT 和电池标定数据校准，再建立 adapter/Harness 接入 `air_spare`。

## 验证

- 可运行 MATLAB 时执行 `addpath('models/px4_x8'); test_x8phys`。
