# 2026-09-02 X8PHYS 平台适配接入

## 本次做了什么
- 复审修正版 `models/px4_x8/+x8phys`：对象契约测试已通过，零风/20 m/s 风功率为 334.208/430.097 W。
- 修正 `make_platform_adapter` 的 reset 包装，使其返回 M0 测量样本而不是对象私有 truth。
- `platform_step` 支持从平台结构读取可选 NED 风，并按 M0-C 硬位 `[1 2 3 4 6 7]` 计算 `sample.valid`；速度失跟位 5 仅记录。
- 新增 `test_x8phys_platform` 与 `run_x8phys_acceptance`，验证 PWM 指令、风、运动、功率、累计能量、SOC、8 位 flags 和 M0 字段尺寸。
- 更新 `X8PHYS_README.md`、`models/px4_x8/README.md` 和开发状态说明。

## 关键决策与理由
- 采用 MATLAB function-handle 适配边界，不改动 `air.slx`、`air_m0b.slx` 或 `air_m0c.slx`，符合平台线“冻结基线只读、对象通过 adapter/Harness 接入”的规则。
- `sample` 只暴露测量上下文（`t/v/P_e/E_e/attitude/yaw_rate/motor_pwm/motor_rpm/constraint_flags` 等）；对象 truth 仅作为适配器第三输出供测试和诊断使用，不进入 ESC/RL 观测。

## 遗留问题 / 风险
- 对象参数仍是未校准代理；功率来源为 `estimated`，不能用于真实节能结论。
- 风场尚未从 `air_spare`/Simulink 端口接入；当前适配器需要调用方提供最终 PWM 和 NED 风。
- 运动对象尚未与 `shared6dof` 逐样本等价，也未建立真实电机/螺旋桨/电池标定数据。

## 下一步
- 建立独立 Harness，将 `air_spare` 的最终 PWM 与风场日志送入 `platform_step`，并对齐时间戳和功率来源。
- 用台架、CFD/BEMT 或文献数据替换代理参数，再进行 M1 扰动/噪声/时延验证。

## 验收状态
- `run_x8phys_acceptance`：通过。
- `run_air_m0a_baseline_compare`：通过，旁路关键信号最大差 0。
- `run_acceptance`：未运行；本次未修改算法模块。
