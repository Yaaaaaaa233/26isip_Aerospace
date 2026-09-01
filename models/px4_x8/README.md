# PX4 X8 Simulink 模型线

## 文件角色

- `air.slx`：只读的八旋翼飞控与 6DOF **基线模型**。已在 MATLAB R2022b 手动更新并完成 0--10 s 仿真（10001 个样本）。
- `air_spare.slx`：由基线复制的 **当前开发模型**（M2 装入后）。在 M0-A 观测支路（惯性速度、水平地速代理、8 路 PWM、RPM 估算、`P_est`/`E_est`、8 位约束标志、35 维日志总线）之上，已按阶段叠加 M0-B 速度闭环与安全回退、M0-C 速度在线 ESC 接口、M2 受约束 eta 分配器与转速比 ESC；`speed_loop_enable=0` 且 eta 缺省 1.0 时与 `air.slx` 逐位一致。
- `air_m0a.slx` / `air_m0b.slx` / `air_m0c.slx` / `air_m2.slx`：M0-A / M0-B / M0-C / M2 各阶段**验收通过后的冻结快照**，后续阶段不再修改（`air_m0c.slx` SHA256 `f9be88df…`）。
- `m0c_vref_esc.m` + `add_air_m0c_esc.m`：M0-C 优化器接口（包装 `modules/ratio_esc` 内核，输入仅 t/v/P_e/E_e/attitude/flags，输出仅 v_ref）与其原子安装脚本；安装器检测到 GUI 中有未保存的 `air_spare` 时会拒绝执行。`test_m0c_esc_unit.m`、`test_m0c_installer_dirty_guard.m`、`run_air_m0c_trials.m` 分别验证适配器、安装器保护和配对试验。
- `run_air_m0b_tests.m`、`run_air_m0b_safety_injection.m`、`run_air_m0a_baseline_compare.m`：结构变更回归三件套（速度双口径验收、逐位故障注入、旁路零差异）。
- `run_air_m1_robustness.m` + `diag_m1_probe.m`：M1 鲁棒性场景矩阵（2% 功率噪声、0.5 s 时延、风扰动与组合、噪声背景故障回归；27 场景固定种子，全程内存注入、零 `.slx` 变更）与 P_est 拓扑探针。

### M2 上下桨转速比 ESC（2026-09-01，快照 `air_m2.slx`）

状态：三轮复验问题全部关闭（2026-09-02）。120 s 数值协议、脏入口背靠背完整链、九场景硬断言与脚本异常退出恢复均验证通过（三入口函数化 + 错误注入矩阵 10/10 PASS）。当前证据见 [`M2_REACCEPT_ROUND3_FIX_20260902.md`](../../docs/evidence/M2_REACCEPT_ROUND3_FIX_20260902.md)。

- `m2_eta_allocator.m` + `m2_alloc_diag.m`：受约束 PWM 域 eta 分配器（同轴对 (1,5)(2,6)(3,7)(4,8)，每对 Σω² 严格保持 → 总推力/横滚/俯仰不变；η=1 位精确透传；sat/dmz 诊断单口输出）。
- `m2_eta_esc.m` + `add_air_m2_allocator.m`：`ratioesc` 内核原生转速比接线（输入 35 维含 motor_pwm/rpm 与 alloc_sat；eta 经全局 `M2_ETA_APPLIED` 交接，慢层信号不进 pwm 主路径）与原子安装器。
- `test_m2_eta_esc_unit.m`、`run_air_m2_trials.m`、`diag_m2_probe.m`：单元测试与 gain 标定（3.2e-3）、9 场景配对试验、模型拓扑探针。
- `init_model.m`：添加模型路径并加载模型。
- `run_baseline.m`、`inspect_interfaces.m`：非破坏性基线运行与接口导出入口；生成的原始结果写到本地 `results/`，默认不提交。

## 署名与贡献

依据 [`docs/AUTHORSHIP.md`](../../docs/AUTHORSHIP.md)：代码与 `.slx` 的署名统一记录于此，不在函数顶部逐个堆叠。

| 姓名 | 角色 | 主要文件/功能 | 日期 |
|---|---|---|---|
| 叶安 | 平台线负责人 | 阶段判据与验收决策、安全链与 ESC 接口契约、各阶段快照放行 | 2026-08-31 ～ 09-01 |
| Codex（AI 协助） | 独立复验 | M0-B 复核/再验收、M0-C 验收加固、M1 独立复验、M2 两轮独立复验与自动化闭环审查 | 2026-09-01 |
| ZCode（AI 协助） | 实现与执行代理 | M0-A 观测层与旁路比对、M0-B 速度环/安全链修复、M0-C 内核封装与配对试验、M1 鲁棒性矩阵、M2 eta 分配器与配对试验 | 2026-08-31 ～ 09-01 |

`air.slx` 基线与各阶段快照的当前负责人为叶安；每次 `.slx` 结构修改在此表追加修改人与内容，不重写历史。

## 快速复现

在 MATLAB 中把 `repoRoot` 替换为本仓库绝对路径后执行：

```matlab
repoRoot = 'D:\path\to\26isip_Aerospace';
addpath(fullfile(repoRoot, 'models', 'px4_x8'))
init_model('air')
result = run_baseline
interfaceResult = inspect_interfaces

% M0-C 复现与回归
test_m0c_esc_unit
test_m0c_installer_dirty_guard
run_air_m0c_trials
m0cResult = result
baselineResult = run_air_m0a_baseline_compare
safetyResult = run_air_m0b_safety_injection

% M1 鲁棒性矩阵（27 场景，约 3--4 分钟）
run_air_m1_robustness
m1Result = result

% M2 完整链（正常路径可复现；异常清理仍待第四轮关闭）
run_m2_session_chain
```

模型依赖 MATLAB/Simulink R2022b、Stateflow，以及模型引用的 `px4lib`、`px4Sensorslib`、`shared6dof` 和 `sharedtransform` 库。若缺少这些库，先恢复本机原有的 PX4/Simulink 支持包路径。

## 边界与下一步

当前模型已具备 RC/解锁、姿态控制、固定 X8 混控、8 路 PWM、PWM 至力/力矩、6DOF、姿态反馈、M0-B 速度外环/安全回退、M0-C 速度 ESC 接口，以及 M2 `eta_ref` 受约束分配器与转速比 ESC；M1 鲁棒性矩阵、M2 修订数值协议和正常完整链已通过。它仍没有电池、电流、真实 RPM、校准后的真实电功率或完整 Harness 接入，因此不能据此宣称真实节能率或算法已经部署飞控。当前先函数化 M2 验收入口并关闭异常恢复，再进入 M3 `.slx` 结构集成；M3 方案文档可并行。详细观测接口见 [`M0A_OBSERVABILITY.md`](../../docs/interfaces/M0A_OBSERVABILITY.md)，阶段门槛见 [`PROJECT_EXECUTION_ROADMAP.md`](../../docs/PROJECT_EXECUTION_ROADMAP.md)。
