# M2 上下桨转速比 ESC（eta 分配器）接口与工作步骤

状态：**方案基线（实施中）**。本文档先于实施落地；实施完成后按 §11 判据验收并回填 §12。交付清单来源：`docs/PROJECT_EXECUTION_ROADMAP.md` §5 M2。

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：叶安
主要撰写：叶安（分配器实例化决策、接口契约与验收判据）、ZCode（方案文档代拟、适配器/安装器/试验实现）
技术依据：`docs/architecture/03_wind_plane_control.md` §7（快层控制、X8 分配与平台回归归叶安）、`docs/architecture/04_interface_dictionary.md` §9（M2 起 `eta_ref` 生效）、`docs/decisions/ADR-001`（`eta_ref` 为第二决策变量，不与速度同时寻优）
审核：待项目组审核、待指导教师确认
AI协助：ZCode（模型拓扑探针、分配器数学推导、实现与本文档代拟）

红线：`air.slx` 只读；本阶段只改 `air_spare.slx`（结构变更后另存 `air_m2.slx` 快照）；**不做 RL**；算法只输出 `eta_ref`，分配器属于快层平台侧，算法不得接触模型内部最优值、解析梯度或 PWM 控制权；`P_est` 未校准，一切能耗结论只作"模型估算"口径。

## 1. 目的与预期管理

把 `modules/ratio_esc` 的转速比内核从代理对象接入真实 X8 仿真闭环：新建受约束 eta 分配器（快层侧），`eta_ref` 由 M2 ESC 产生或固定给定，验证 eta 有界可追踪、姿态/偏航/电机约束满足、结果不差于固定 `eta=1` 基线（路线图 §5 M2 条目 1--5）。

**物理预期（由植株源码推导，见 §2/§3）**：eta 重分配在本植株上**严格保持**总推力与横滚/俯仰力矩，只改变偏航反扭矩，且偏航扰动正比于各同轴对内的指令不平衡（名义均衡指令下为零， maneuvers 时由既有偏航内环吸收）。`P_est = C_M·Σω³` 面上 eta 存在**真实梯度**：

```text
P_pair(η) = C_M·(T_pair/C_T)^{3/2} · g(η),   g(η) = (1+η³)/(1+η²)^{3/2}
g(1)=0.7071（最小）；η=0.8: g=0.720（+1.8%）；η=1.2: g=0.716（+1.2%）
```

与 M0-C 的平坦 P–v 面不同，M2 的 ESC 首次有模型内可测梯度：预期 ESC 从 0.8/1.2 初值向 ≈1.0 收敛，fixed η=0.8/1.2 配对功率高于 η=1 约 1.2--1.8%（251 W 工作点约 +3--4.5 W，高于 M1 噪声 σ=5 W 的一半，可测）。

**诚实边界**：η=1 最优是 `Σω³` 代理的数学性质（给定 Σω² 时 Σω³ 在相等处最小，凸性），模型不含真实同轴滑流干扰、电机效率差异与电池特性，真实 coax 效率完全可能偏好 η≠1。全部百分比只作模型估算口径，不构成真实节能证据。

## 2. 八电机配对、旋向与 eta 定义（路线图约束 2.3）

来源：`air_spare/Subsystem/MATLAB Function`（6DOF 力/矩核，探针 `models/px4_x8/diag_m2_probe.m` 导出）：

- 几何角 `theta = [45°, 315°, 225°, 135°] × 2`（电机 1--4 与 5--8 两两同臂位）；
- 旋向 `dir = [-1; 1; -1; 1; 1; -1; 1; -1]`——电机 5--8 与 1--4 逐对相反；
- 转速映射 `ω_i = (pwm_i − 1000)/1000 × ω_max`，`ω_max = 1000` rad/s；推力 `T_i = C_T·ω_i²`，反扭矩 `Q_i = C_M·ω_i²`，`C_T=1.42e-5`，`C_M=2.51e-7`，`L=0.2 m`。

**固定定义（全项目统一，M2 起生效）**：

| 同轴对 k | 下桨（lower） | 上桨（upper） | 臂位角 | 下桨旋向 dir |
|---:|---:|---:|---:|---:|
| 1 | 电机 1 | 电机 5 | 45° | −1 |
| 2 | 电机 2 | 电机 6 | 315° | +1 |
| 3 | 电机 3 | 电机 7 | 225° | −1 |
| 4 | 电机 4 | 电机 8 | 135° | +1 |

`eta = ω_upper / ω_lower`（无量纲，工作域 [0.75, 1.25]）。M2 采用**全机统一单标量 `eta_ref`**（四对同值）；分对独立 eta 不在本阶段范围。植株对上下桨物理对称（同臂位、仅旋向差），"上/下"是本行文档固定的命名约定。

## 3. 受约束 X8 Control Allocator：PWM 域后置实例化

### 3.1 实例化决策

路线图原文为"输入总推力/三轴力矩与 `eta_ref`，输出 `omega_1...omega_8`，再映射至 PWM"。实现采用**等价的 PWM 域后置分配器**，理由：

1. `Attitude Control/AttitudeControl` 的 8 路混控输出已完全编码总推力/三轴力矩指令（`motor_cmds = mix·[T;U_roll;U_pitch;U_yaw]`，钳位 [0,1] 后 `pwm = 1000+1000·val`）；打开该 MATLAB Function 重排混控矩阵等于改写 PX4 库快层代码，违反"快层负责稳定、不修改姿态 PID"约束 2.1；
2. PWM→ω 是植株明确定义的线性映射（§2），PWM 域重分配与 omega 域重分配一一对应，输出仍是 8 个 omega 对应的 PWM；
3. η=1 时分配器可走**逐位恒等快速路径**，结构变更后旁路回归差 0 有硬保证。

### 3.2 分配器数学（纯函数 `models/px4_x8/m2_eta_allocator.m`）

对每对 k：`c_l = ω_l²`，`c_u = ω_u²`（由 pwm 线性映射平方，单位 rad²/s²）。`|η−1| < 1e-12` 时直接透传输入 8 路 pwm。否则：

```text
c_l' = (c_l + c_u)/(1+η²),   c_u' = η²·c_l'      （每对 Σc 严格不变）
ω' = sqrt(c'),  pwm' = uint16(1000 + ω')，钳位 [1000, 2000]
```

- **推力/横滚/俯仰保持**：每对 Σc 不变 + 上下桨同臂位 ⇒ `ΣT_i`、`M_x = Σ−L·sinθ·T_i`、`M_y = Σ L·cosθ·T_i` 在连续域逐样本严格保持。PWM 1 us 量化（uint16 舍入 ω' 至整数 rad/s）引入每对 ±0.3% 级推力量化误差（@ω'≈552 rad/s 界界分析），对称舍入近似零均值；
- **偏航变化（解析已知、在线记录）**：`ΔM_z = C_M·Σ_k dir_k·[(c_u'−c_l') − (c_u−c_l)]`，由分配器第三输出在线计算并记录。名义均衡指令下 `Σ_k dir_k·(c_k+c_{k+4}) = 0 ⇒ ΔM_z = 0`；不平衡（横滚/俯仰/偏航机动）时非零，符号随 dir 交替部分抵消；
- **偏航补偿策略**：不新增偏航前馈。ΔM_z 作为扰动由既有偏航角速度内环（`r_des = cmd_yaw·1.5`，RC 偏航中位时 r→0）吸收；本阶段**检查**其可接受性（§11 判据 3），不改变偏航通道结构；
- **受约束性**：η 输入钳位 [0.75,1.25]；输出钳位 [1000,2000]；钳位发生时置 `sat` 输出 = 1。

### 3.3 饱和与安全链（不改 8 位标志布局）

分配器输出接回原线路后，`M0A Constraint Flags` 的 pwm 输入（in1 ← `M0A PWM ZOH 1ms` ← `M0A PWM Vector Double` ← 分接点下游）自动变为**后分配器**真值：分配器输出触轨 ⇒ 位 1/2（pwm/rpm 边界 ±5 us）照常触发 ⇒ 既有冻结/回退链照常动作。分配器自身 `sat` 标志**不并入** 8 位总线（位 8 保留不动），只（a）进 M2 独立日志，（b）进 eta ESC 的 valid 门控（饱和样本代价无效，ESC 冻结等待）。位 8 留给后续阶段。

## 4. eta_ref 通路与适配器

### 4.1 通路

`M2 Eta ESC`（Interpreted MATLAB Fcn，`models/px4_x8/m2_eta_esc.m`，显式 0.05 s 采样）→ `M2 Eta ZOH 4ms` → 分配器 eta 入口。**无独立选择器**：fixed/ESC 配对臂用同一模型同一接线，唯一差异是 global `M2_ETA_PARAMS.mode`（M0-C 模式）。`m2_eta_esc` 的 **mode 缺省为 `'fixed'、center0=1.0`**（与 M0-C 不同！）：M0-C 的 ESC 输出经 selector 门控，缺省 'esc' 安全；M2 分配器在 pwm 主路径上**永在环**，任何未配置 global 的旁路回归必须落到恒等快速路径——缺省 fixed 1.0 保证这一点。试验脚本每场景显式设置 global。

### 4.2 内核接线（原生语义，零映射）

M0-C 曾把内核原生转速比语义映射到速度；M2 直接用原生语义：

- `ratioesc.esc_step(s, P_est, eta_actual, valid, p)`：`measuredPower = P_est`（`M0A Power Measurement` 出 1，真实信号），`actualRatio = eta_actual`（由后分配器 pwm/rpm 计算）；
- `valid = 硬位 [1 2 3 4 6 7] 全静默 ∧ P_est 有限 ∧ 分配器 sat=0 ∧ 每对上下桨 ω>20 rad/s（armed 飞行中）`；内核 sampleOK 另要求 `eta_actual ∈ [lower,upper]`；
- 输入 mux 34 维 = `[t; v; P_est; E_est; att(6); pwm(8); rpm(8); flags(8)]`，满足路线图 §3.1 合同（M2 起 `motor_pwm`/`motor_rpm` 为必需输入）。内核只用 P/eta_actual/valid，其余为合同完整性与日志；
- `eta_actual = mean_k(ω_{k+4}/ω_k)`，ω 由输入 rpm 通道（`M0A rpm_est` 链，与 pwm 同源线性映射）计算；桨停转（ω<20）样本本就 invalid，无除零风险；
- dither/滤波参数（§4.3）：`band [0.75,1.25]`（模块缺省，覆盖 0.8/1.0/1.2 初值）、`amplitude 0.02`（中心投影 [0.77,1.23]）、`frequency 0.25 Hz`（周期 4 s，dither 斜率 2π·0.25·0.02 ≈ 0.031 /s ≪ rateLimit）、`hpOmega = lpOmega = 0.6`（自模块缺省 0.05 按 M0-C 同法标度）、`rateLimit 0.05 /s`（每步 0.0025）；`gain` 由单元测试标定后回填（量级预估 ~1e-4，见 §7 步骤 4）。

### 4.3 warmup 与初始瞬态

armed 前（ω<20）ESC 恒持 center0；首次 valid 后内核自带 1/(f·Ts)=80 样本（4 s）warmup。fixed 臂 eta 自 t=0 即为给定值（起飞段 c 小、η 影响小）；初始瞬态如实记录，配对能量窗 [20,30] s 不受影响。

## 5. 模型改动（安装器 `models/px4_x8/add_air_m2_allocator.m`）

唯一结构分接点：`Attitude Control` 出 2（`Output_Limits1` 出的 8×uint16 pwm；探针证实其下游恰为 `Demux` in1〔→6DOF Ch1--8 + PX4 PWM Output 通道 3--10〕与 `M0A PWM Vector Double` in1，3 条支线两处端口）。改动清单：

1. 删除 `Attitude Control` 出 2 的全部 3 条支线（按线句柄逐条删，P1 教训模式）；
2. 新增 `M2 Alloc Input`（Mux 2：pwm8 + eta_ref）与 `M2 Eta Allocator`（Interpreted MATLAB Fcn，采样 −1 继承 4 ms，纯函数无持久态）；分配器出 1（pwm8）重接回 `Demux` in1 与 `M0A PWM Vector Double` in1（恢复原语义），出 2（sat）、出 3（ΔM_z）接 `M2 Alloc Log`（新 ToWorkspace，`m2_alloc_log`）；
3. 新增 `M2 Eta ESC`（显式 0.05 s）与 `M2 ESC Input`（Mux 34 = 8 端口：t/v/P/E/att/pwm/rpm/flags）；v/P/E/att/flags 复用 M0-C 既有 0.05 s ZOH 的分支；新增 `M2 PWM ZOH`、`M2 RPM ZOH`（0.05 s；源分别为 `M0A PWM Vector Double` 出与 Log Bus rpm 段源，安装时枚举断言）；`M2 Clock`（Digital Clock 0.05 s）；
4. `M2 Eta ESC` 出 → `M2 Eta ZOH 4ms`（采样 0.004，跨率显式）→ `M2 Alloc Input` 入 2；
5. 保存前功能编译检查（η=0.9 fixed 功能试跑 + η=1 恒等性抽查）；保存后磁盘重载并断言连线清单（源端口句柄相等，codex 4.3 模式），含"分配器入 1 恰来自 Attitude Control 出 2、Demux in1 恰来自分配器出 1"；
6. 脏模型保护（`air:M2:DirtyModel`）、幂等（`air:M2:AlreadyInstalled`）、失败自动回滚备份；
7. 回退：`air_m0c.slx`（M2 前稳定快照）拷回 `air_spare.slx`。

## 6. 单元测试（先于模型，`models/px4_x8/test_m2_eta_esc_unit.m`）

纯 MATLAB，不碰模型：

1. **分配器纯函数**：(a) η=1 逐元素恒等（含 0/1000/2000 边界）；(b) η=0.8/1.2 每对 Σc 相对误差 ≤0.3%（量化限）；(c) η 输入 0.5/2.0 被钳位且 sat=1；(d) ΔM_z 解析值一致（构造不平衡 c）；
2. **解析碗收敛**：`P(η) = 251·g(η)/g(1)`，一阶执行动态 τ=1 s；esc 模式自 center0=0.8 与 1.2 各自 30 s 内中心进 1.00±0.02，全程 eta_ref ∈ [0.73,1.27]；
3. **fixed 模式**：eta_ref ≡ center0（逐样本差 <1e-12）；**invalid 语义**：人为置 invalid 两个扰动周期 → eta_ref 保持、无跳变；
4. gain 不满足 2 时先调 gain 并回填 §4.2，再动模型。

## 7. 配对试验（`models/px4_x8/run_air_m2_trials.m`）

名义（roll 正弦置 0）与扰动（基线正弦）双口径；`speed_loop_enable=1`、`optimizer_enable=1`（M0-C 同款，ESC mode 由 global 控制）；每场景磁盘重载模型；30 s ≥ 初始化 + ≥5 个评估周期。

| 组 | 场景 | eta 设置 | 时长 |
|---|---|---|---|
| E1/E2/E3 | 名义 | fixed 0.8 / 1.0 / 1.2 | 30 s ×3 |
| S1/S2/S3 | 名义 | esc center0 = 0.8 / 1.0 / 1.2（各配 E2 对照） | 30 s ×3 |
| D-E2 / D-S2 | 扰动 | fixed 1.0 / esc center0=1.0 | 30 s ×2 |
| R | 名义 | S2 原样重跑 | 30 s |

每场景记录：`ΔE%`（fixed/ESC 公共连续 [20,30] s 网格，932c55d 加固口径）、收敛时间（中心序列最后完整扰动周期变化 <0.01）、eta_actual 轨迹与 eta_ref 界、`ΔM_z` max/RMS、yaw_rate max 与位 4、位 1/2/8、位 5、姿态 max、PWM 8 通道 min/max、frozen/fallback 次数、alloc sat 占比。归档 `results/air_m2_trials/<stamp>/`。

## 8. 结构变更回归（红线，安装后必跑）

1. `run_air_m0a_baseline_compare`：旁路三信号差必须仍为 0（分配器 η=1 恒等快速路径在环；脚本需以缺省 global 运行——缺省 fixed 1.0 正是为此）；
2. `run_air_m0b_safety_injection`：位 1/4/6/7 注入链 4/4 通过（eta 缺省 fixed 1.0，排除 ESC 在线搜索干扰；位 1/2 由后分配器 pwm 触发，同时间接验证分配器输出进了安全链）；
3. AGENTS.md 平台线回归清单新增 M2 条目（单元测试 + trials）。

## 9. 快照

验收全绿后 `air_spare.slx` → 另存 `air_m2.slx`（M0-A/B/C 快照惯例）。此后任何 M3 改动从 `air_m2.slx` 语义基线出发。

## 10. 交付物清单

- 文档：本文档、`docs/evidence/M2_ETA_2026090X.md`（+CSV）、worklog、roadmap §4/§5/§6 与 DEVELOPMENT_STATUS/AGENTS/README 状态回填、模块 README 贡献表；
- 代码：`m2_eta_allocator.m`、`m2_eta_esc.m`、`test_m2_eta_esc_unit.m`、`add_air_m2_allocator.m`、`run_air_m2_trials.m`、`diag_m2_probe.m`；
- 模型：`air_spare.slx`（M2 安装后）、快照 `air_m2.slx`；
- 结果：`results/air_m2_trials/<时间戳>/`、旁路比较与注入回归新时间戳目录。

## 11. 验收判据（对应路线图 §M2"验收"的落地口径）

1. **稳定**：全部试验无 fallback，姿态在自身限幅内，无持续饱和（位 1/2 无长窗钉死）；yaw_rate max ≤1.5 rad/s（位 4 静默）且扰动场景偏航扰动量级如实报告；
2. **eta 有界可追踪**：eta_ref 全程 ∈ [0.73,1.27]（带 + dither 容差）；eta_actual 跟随 eta_ref（非饱和窗 |η̂−η_ref| ≤0.02 均值口径；量化与执行动态引起的瞬态如实报告）；
3. **偏航可接受**：`ΔM_z` 在线记录值与 §3.2 解析式一致；名义均衡段 |ΔM_z| ≈0；扰动场景偏航内环吸收后 r 有界（判据 1）；
4. **不差于基线**：S1/S2/S3 对 E2 的 ΔE% ≤ +0.5%（量化与瞬态容差；E1/E3 vs E2 的 +1.2--1.8%（模型估算）作为功率面非平凡性的旁证记录）；esc 收敛至 1.0±0.05（S1/S3 从 0.8/1.2 出发）；
5. **可复现**：R 与 S2 逐样本最大差 <1e-9；
6. **回归全绿**（§8）；
7. **口径**：一切能耗结论只作模型估算；η=1 最优是代理面性质，不构成真实节能证据。

## 12. 验收结果（验收后回填）

（待实施完成后回填。）
