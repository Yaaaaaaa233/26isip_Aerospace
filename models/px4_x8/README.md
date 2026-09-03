# PX4 X8 Simulink 模型线

## 文件角色

- `air.slx`：只读的八旋翼飞控与 6DOF **基线模型**。已在 MATLAB R2022b 手动更新并完成 0--10 s 仿真（10001 个样本）。
- `air_spare.slx`：由基线复制的 **当前开发模型**（M0-C 装入后）。在 M0-A 观测支路（惯性速度、水平地速代理、8 路 PWM、RPM 估算、`P_est`/`E_est`、8 位约束标志、35 维日志总线）之上，已按阶段叠加 M0-B 速度闭环与安全回退、M0-C 速度在线 ESC 接口；`speed_loop_enable=0` 时与 `air.slx` 逐位一致。
- `air_m0a.slx` / `air_m0b.slx` / `air_m0c.slx`：M0-A / M0-B / M0-C 各阶段**验收通过后的冻结快照**，后续阶段不再修改（`air_m0c.slx` SHA256 `f9be88df…`）。
- `m0c_vref_esc.m` + `add_air_m0c_esc.m`：M0-C 优化器接口（包装 `modules/ratio_esc` 内核，输入仅 t/v/P_e/E_e/attitude/flags，输出仅 v_ref）与其原子安装脚本；`test_m0c_esc_unit.m`、`run_air_m0c_trials.m` 为单元测试与配对试验入口。
- `run_air_m0b_tests.m`、`run_air_m0b_safety_injection.m`、`run_air_m0a_baseline_compare.m`：结构变更回归三件套（速度双口径验收、逐位故障注入、旁路零差异）。
- `run_air_m1_robustness.m` + `diag_m1_probe.m`：M1 鲁棒性场景矩阵（2% 功率噪声、0.5 s 时延、风扰动与组合、噪声背景故障回归；27 场景固定种子，全程内存注入、零 `.slx` 变更）与 P_est 拓扑探针。

### M2 上下桨转速比 ESC（2026-09-01，快照 `air_m2.slx`）

状态：M2 核心实现与修订数值协议保持放行；第十轮在治理提交 `71acd56` 按规则 v1.7 独立复跑 52/52 针对性矩阵 PASS（runId `88e0204a`），R9-F1 的上限+stamps 协同篡改和删除 c5+声明行两个原始复现均被独立探针以 `air:M2Verify:ManifestContract` 精确拒绝，R9-F2 的 8 份真实批次日志零 U+FFFD，R9-F1/R9-F2/R8-F1 满足关闭三件套。功能实现与当前冻结验收基础设施均 VALIDATED。c3 盖章后与 c5 盖章前各发生一次自然堆崩溃，驱动分别按 fresh done 无害放行与 attempt=2 完整重执行成功；环境堆崩溃仍为 OPEN LIMITATION，全量同会话双链仍未覆盖。当前判定见 [`M2_REACCEPT_ROUND10_CODEX_20260903.md`](../../docs/evidence/M2_REACCEPT_ROUND10_CODEX_20260903.md)；第九轮修复见 [`M2_REACCEPT_ROUND9_FIX_20260903.md`](../../docs/evidence/M2_REACCEPT_ROUND9_FIX_20260903.md)；跨项目分层治理见 Proposed [`ADR-003`](../../docs/decisions/ADR-003-layered-acceptance-closure-governance.md)。

- `m2_eta_allocator.m` + `m2_alloc_diag.m`：受约束 PWM 域 eta 分配器（同轴对 (1,5)(2,6)(3,7)(4,8)，每对 Σω² 严格保持 → 总推力/横滚/俯仰不变；η=1 位精确透传；sat/dmz 诊断单口输出）。
- `m2_eta_esc.m` + `add_air_m2_allocator.m`：`ratioesc` 内核原生转速比接线（输入 35 维含 motor_pwm/rpm 与 alloc_sat；eta 经全局 `M2_ETA_APPLIED` 交接，慢层信号不进 pwm 主路径）与原子安装器。
- `test_m2_eta_esc_unit.m`、`run_air_m2_trials.m`、`diag_m2_probe.m`：单元测试与 gain 标定（3.2e-3）、9 场景配对试验、模型拓扑探针。
- `init_model.m`：添加模型路径并加载模型。
- `run_baseline.m`、`inspect_interfaces.m`：非破坏性基线运行与接口导出入口；生成的原始结果写到本地 `results/`，默认不提交。
- `+x8phys/`：可替换的风场-运动-电池 MATLAB 对象。输入 8 路请求 PWM、NED 三维风速和时间步长，输出请求/实际施加 PWM、四元数刚体代理、相对气流、风致旋翼负载、电功率、累计能量、SOC，以及经 `map_flags` 映射的平台约束标志；`platform_step`/`make_platform_adapter` 只向 M0-C 暴露测量上下文，`test_x8phys_platform` 与 `run_x8phys_acceptance` 验证接入契约。详见 `X8PHYS_README.md`。

## 署名与贡献

依据 [`docs/AUTHORSHIP.md`](../../docs/AUTHORSHIP.md)：代码与 `.slx` 的署名统一记录于此，不在函数顶部逐个堆叠。

| 姓名 | 角色 | 主要文件/功能 | 日期 |
|---|---|---|---|
| 叶安 | 平台线负责人 | 阶段判据与验收决策、安全链与 ESC 接口契约、各阶段快照放行 | 2026-08-31 ～ 09-01 |
| Codex（AI 协助） | 独立复验 | M0-B 复核/再验收、M0-C 验收加固、M1 独立复验、M2 多轮独立复验与自动化闭环审查 | 2026-09-01 ～ 09-02 |
| Codex（AI 协助） | 对象实现与审核 | X8PHYS/Plane 代理、平台测量适配、数据追溯与 P0--P4 契约验收 | 2026-09-02 ～ 09-03 |
| ZCode（AI 协助） | 实现与执行代理 | M0-A 观测层与旁路比对、M0-B 速度环/安全链修复、M0-C 内核封装与配对试验、M1 鲁棒性矩阵、M2 eta 分配器与配对试验 | 2026-08-31 ～ 09-01 |

`air.slx` 基线与各阶段快照的当前负责人为叶安；每次 `.slx` 结构修改在此表追加修改人与内容，不重写历史。
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

原始 `air.slx` 链路已具备 RC/解锁、姿态控制、固定 X8 混控、8 路 PWM、PWM 至力/力矩、6DOF 与姿态反馈。新增 `+x8phys` 提供独立的风/运动/电池对象，但尚未接入现有 `.slx` 连线，也不是实测校准模型；`eta_ref` 受约束分配器、真实 RPM 和飞控集成仍待后续阶段。详细接口见 [`docs/interfaces/M0A_OBSERVABILITY.md`](../../docs/interfaces/M0A_OBSERVABILITY.md)。
