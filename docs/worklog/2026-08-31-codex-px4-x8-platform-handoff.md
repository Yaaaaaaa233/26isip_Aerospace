# 2026-08-31 Codex PX4 X8 平台整理与交接

## 本次做了什么

- 核查并固化了本地 PX4 X8 Simulink 平台的现状：`air.slx` 是不直接修改的基线；`air_spare.slx` 是唯一的 M0-A 开发副本。
- 已验证的基线事实写入仓库：`air.slx` 在 MATLAB R2022b 中完成 0--10 s 仿真，返回 10001 个时间样本；接口审计发现 1 个 6DOF 块和 59 条端口连接。
- 将基线模型、M0-A 观测快照、非破坏性运行/接口检查脚本，以及筛选后的 CSV 证据纳入 `models/px4_x8/` 与 `docs/evidence/`。
- 新增项目路线、模型审计、M0-A 接口和工作区清单；README 加入整体数据流图，并建立 `speed_esc`、`integration/air_esc`、`harness` 与 `tests` 的职责边界。
- 本次整理已作为提交 `2f8a5c7 Add PX4 X8 model baseline and roadmap` 推送至 `main`；之后已同步跨 agent 工作简报机制（`c0513a7`）。

## 关键决策与理由

- 不改动 `modules/ratio_esc`：它仍是恒推力假设下的转速比代理对象，尚未满足接入真实 X8 的功率、约束与控制分配前提。
- M0-A 只增加无侵入观测支路：记录 `m0a_Ve_inertial_mps`、`m0a_horizontal_speed_mps`、`m0a_motor_pwm_us` 与 `m0a_motor_rpm_est`，不替换原有解锁、姿态控制、混控或动力学连线。
- `m0a_motor_rpm_est` 明确标注为按当前 PWM 至角速度植株映射得到的估算值，不等同于带电机动态/传感器的实测 RPM。
- 只提交可追溯 CSV 摘要，不提交 `slprj`、`.slxc`、MAT 原始仿真输出或原始参考 PDF。

## 遗留问题 / 风险

- M0-A 尚缺 `P_est`、`E_est`、统一日志/场景配置、`optimizer_enable=0` 固定基线模式和 `constraint_flags`。
- 当前模型没有真实 RPM、电池/电流/电功率、速度外环、`eta_ref` 受约束分配器或 Harness，不能报告真实节能率或宣称算法已部署飞控。
- `air_spare.slx` 是二进制开发快照；若下一阶段验收通过，应按路线另存稳定快照并避免多分支同时修改该模型。

## 下一步

1. 仅在 `air_spare.slx` 中增加可替换的 `Power Measurement`，输出带来源标识的 `P_est` 与 `E_est`。
2. 建立统一日志和 `optimizer_enable=0` 固定基线配置，加入 PWM/RPM 饱和、姿态、偏航率、速度失跟、功率异常与信号缺失等约束标志。
3. 运行 10 s 基线并比较观测加入前后的轨迹、姿态和 PWM；通过后才开始 M0-B 速度闭环。

## 验收状态

- `air.slx` 基线仿真：通过（MATLAB R2022b，0--10 s，10001 样本）。
- M0-A 速度、PWM 与 RPM 估算日志：通过 `air_spare.slx` 仿真验证。
- `modules/ratio_esc/run_acceptance`：本会话未运行；未改动该模块的代码或模型。
