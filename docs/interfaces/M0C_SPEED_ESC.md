# M0-C 速度在线 ESC（`eta = 1`）接口与工作步骤

状态：**方案已定稿，实施中**（2026-09-01）。交付清单来源：`docs/PROJECT_EXECUTION_ROADMAP.md` §6。本文档是 M0-C 的执行基线：先按 §6 步骤落文档，再实施，实施完成后按 §7 判据验收并回填 §8。

红线：`air.slx` 只读；本阶段只改 `air_spare.slx`；**不接入 `eta` 分配器，不做 RL**；算法不得接触模型内部最优值、解析梯度或 PWM 控制权；P_est 未校准，一切能耗结论只作"模型估算"口径。

## 1. 目的与预期管理

验证"单变量速度在线功率优化"的闭环机制：ESC 只通过小范围 `v_ref` 搜索带寻优，安全层始终在平台侧（M0-B selector/监视器不动）。

**诚实预期（写明，防止为数字调参）**：M0-B 证据显示速度闭环保持期间 8 路 PWM ≈1500±4（5/9 m/s 稳态与阶跃场景一致），`P_est = Σ C_M·ω³` 对 `v` 在工作点附近近似平坦。因此本阶段 ESC 的预期结果是**梯度估计 ≈0、中心值停在初始参考附近、ΔE% ≈ 0**。M0-C 的验收对象是：接口封装正确、闭环机制成立、配对结论可复现、安全链不回退——**不是**节能数字。若 ESC 找到可测的功率下降，如实报告并只宣称"模型估算能耗改善"。

## 2. Git 算法模块的封装（路线图 §6 条目 3）

### 2.1 内核来源

直接复用 Git 仓库 `modules/ratio_esc/+ratioesc` 的 ESC 内核（不重写滤波/梯度逻辑）：

- `ratioesc.config(...)`：参数构造 + 白名单校验；
- `ratioesc.esc_reset(p, center0, P0)`：状态初始化，`lastReference = center0`；
- `ratioesc.esc_step(s, P_e, v, valid, p)`：冲洗滤波 → 同频解调 → 低通梯度 → 负梯度积分 → 中心投影 → 参考限速；`valid=false` 时保持上一参考、复位滤波器并等待一个扰动周期（模块自身语义，即冻结/无效样本处理）。

语义映射（转速比 → 速度）：`eta_actual → v`（被控量测量），`J_measured → P_e`（模型估算电功率），`center → v_ref 中心`，dither 叠加在 `v_ref` 上。

### 2.2 适配器 `m0c_vref_esc`（新文件 `models/px4_x8/m0c_vref_esc.m`）

Simulink 侧用 **Interpreted MATLAB Fcn 普通方块**（避开本环境 chart 断线坑，见 `M0B_SPEED_LOOP.md` §4），采样时间 0.05 s，采样间输出保持。

输入向量 `u`（18 维，严格路线图接口，缺一不可多亦不可少）：

| 分量 | 索引 | 根层信号源 |
|---|---|---|
| `t` | 1 | `Digital Clock`（0.05 s） |
| `v` | 2 | `M0B v ZOH 1ms` 出（与速度控制器/标志覆盖层同源） |
| `P_e` | 3 | `M0A Power Measurement` 出 1（`P_est_W`） |
| `E_e` | 4 | `M0A Power Measurement` 出 2（`E_est_J`，本代内核不用，接口预留） |
| `attitude` | 5:10 | `Attitude Control` wrapper 出 3（6 维；`yaw_rate = attitude(6)`） |
| `constraint_flags` | 11:18 | `M0B Flags Override` 出（覆盖后 8 位总线） |

输出：仅 `v_ref`（优化器参考请求，接 `M0B Reference & Safety` 入 3）。

行为规范：

1. **运行检测/复位**：`t` 回退（新仿真开始）时读 `global M0C_ESC_PARAMS` 快照到持久态，`ratioesc.esc_reset(p, center0, P_e(0))`；
2. **valid 判定**：硬位 `[1 2 3 4 6 7]` 全静默 且 `P_e`、`v` 有限；`esc_step` 的 `sampleOK` 同时要求 `v ∈ [lower, upper]`（搜索带）——速度未进带时 ESC 恒输出 `center0`，与 selector warm-up 天然衔接；
3. **`mode='esc'`**：每采样调用 `ratioesc.esc_step`，中心从 `center0` 起步在线寻优；
4. **`mode='fixed'`**：恒输出 `center0`（不做 dither、不做梯度更新）——**配对基线与 ESC 组用同一模型、同一接线，唯一差异是这一个参数**；
5. 速率限制 2 m/s² 与 selector 一致（双保险，selector 是安全端最终约束）。

### 2.3 模型改动（安装器 `models/px4_x8/add_air_m0c_esc.m`）

- 新增 `M0C v Ref ESC`（Interpreted MATLAB Fcn）+ `M0C ESC Input`（Mux 18）+ `M0C Clock`；
- 删除 `M0B v Ref Optimizer` 常量 → selector 入 3 的连线（**按"源→具体目标端口"逐支路删除**，P1 教训），改接 ESC 出；常量块保留但断开（手动对照用）；
- 保存前功能编译检查（`set_param(model,'SimulationCommand','update')`）；保存后**磁盘重载并断言连线清单**（M0-B 重载验证模式）；
- 幂等：重复运行报 `AlreadyInstalled`；
- 回退方案：`air_m0b.slx` 是 M0-C 前稳定快照，异常时拷回 `air_spare.slx` 即回退。

### 2.4 ESC 参数（初值，单元测试标定后归档终值）

| 参数 | 值 | 说明 |
|---|---|---|
| `Ts` | 0.05 s | 同模块默认 |
| 搜索带 `lower/upper` | 6 / 12 m/s | 收紧自 [0,15]，包含三组初始参考 7/9/11 |
| `amplitude` | 0.3 m/s | dither 幅值；中心投影 [6.3, 11.7] |
| `frequency` | 0.25 Hz | 周期 4 s；峰值斜率 2π·0.25·0.3≈0.47 m/s < 2 m/s² 限速 |
| `hpOmega/lpOmega` | 0.6 rad/s | 随 dither 频率从模块默认 0.05 标度放大 |
| `gain` | 5e-4（初值） | P_e 量纲为 W（数百），较模块归一化 J 大 ~2 个量级，增益相应缩小；以单元测试标定 |
| `rateLimit` | 0.1 m/s/步 | =2 m/s²，与 selector 一致 |

## 3. 稳定窗口评价（路线图 §6 条目 2）

- 代价/统计只在 **clean 样本**上计算：`status ∈ {1,2}` 且位 5（速度失跟）静默；warm-up 未完成、frozen/fallback、失跟样本一律剔除；
- 名义场景（roll 正弦置 0，内存修改，结构不动）全窗 clean，≥3 s；
- 扰动场景（基线 roll 正弦保留）clean 窗受限（M0-B 实测最长 0.87–1.59 s），**如实报告窗口长度**，窗口口径作为显式配置写入试验脚本与结果归档。

## 4. 单元测试（先于模型，`models/px4_x8/test_m0c_esc_unit.m`）

纯 MATLAB 循环，不碰模型，验证封装语义与增益标定：

1. **解析碗收敛**：`P(v)=P0+c·(v−v_opt)²`（`v_opt=8`），一阶执行动态 `τ=1 s`；esc 模式 20 s 内中心进入 8±0.2，全程 `v_ref ∈ [5.7,12.3]`；
2. **fixed 模式**：`v_ref ≡ center0`（逐样本差 <1e-12）；
3. **无效样本语义**：人为置 invalid 两个扰动周期 → `v_ref` 保持、无跳变，恢复后正常学习；
4. 若默认 `gain` 不满足 1，先调 `gain` 并把终值回填 §2.4，再动模型。

## 5. 配对试验（`models/px4_x8/run_air_m0c_trials.m`）

| 组 | 场景 | 初始参考/中心 | 模式 | 时长 |
|---|---|---|---|---|
| T1 | 名义（roll=0） | 7 m/s | fixed vs esc | 30 s ×2 |
| T2 | 名义 | 9 m/s | fixed vs esc | 30 s ×2 |
| T3 | 名义 | 11 m/s | fixed vs esc | 30 s ×2 |
| D-T2 | 扰动（基线正弦） | 9 m/s | fixed vs esc | 30 s ×2 |
| R | 复现组 | T2-esc 原样重跑 | esc | 30 s |

公共设置：`speed_loop_enable=1`、`optimizer_enable=1`、无噪声；每场景磁盘重载模型。30 s ≥ 1 个初始化周期 + ≥5 个评估周期（0.25 Hz）。

每对记录：`mean|v−v_ref|`、`mean P`、`∫P`（clean 窗内）、`ΔE%`（esc−fixed）、**收敛时间**（中心序列在最后一个完整扰动周期内变化幅度 <0.1 m/s 的首次时刻，自 active 起算；未收敛记 NaN）、frozen/fallback 次数、位 5 占比、PWM 8 通道 min/max/均值（`Aw(:,11:18)`）。

## 6. 结构变更回归（红线，每次结构变更后必跑）

1. `run_air_m0a_baseline_compare`：旁路（`speed_loop_enable=0`）三信号差必须仍为 0（含真 `Ve` 维度断言）；
2. `run_air_m0b_safety_injection`：位 1/4/6/7 注入链全部"触发→frozen→fallback→（位 6）恢复"。

## 7. 验收判据（对应路线图 §M0-C"验收"的落地口径）

1. T1–T3 三组 esc 均收敛（§5 收敛定义）或安全回退（触发 frozen/fallback 且过程有界）；
2. 无持续饱和：`|pitch_cmd|` 未长时间（>90% active 窗）钉在 0.40；姿态在自身限幅内；名义下硬标志静默（且该"静默"由 §6 注入证据支撑，非"不可能非零"式空洞）；
3. `v_ref` 优化器输出全程 ∈ [5.95, 12.05]（带 + dither 容差）；
4. 可复现：R 组与 T2-esc 逐样本最大差 <1e-9（无噪声确定性）；
5. 回归全绿（§6）；D-T2 扰动对如实报告窗口受限下的结论，不计入收敛判据；
6. 能耗结论只作"模型估算"口径；预期 ΔE% ≈ 0（§1），若显著非零须给出 P–v 面解释。

## 8. 验收结果（实施后回填）

待实施完成后填写：单元测试标定终值、安装器重载断言结果、五组配对数据表、回归结果、快照与归档路径、git 提交号。

## 9. 交付物清单

- 文档：本文档、`docs/evidence/M0C_TRIALS_20260901.md`、worklog `2026-09-01-zcode-m0c-speed-esc.md`、roadmap §5/§6 状态、`CURRENT_WORKSPACE_STATUS`、`DEVELOPMENT_STATUS`；
- 代码：`m0c_vref_esc.m`、`add_air_m0c_esc.m`、`test_m0c_esc_unit.m`、`run_air_m0c_trials.m`（均落 `models/px4_x8/`，终态同步仓库镜像）；
- 模型：`air_spare.slx`（M0-C 安装后）、快照 `air_m0c.slx`（验收全绿后）；
- 结果：`results/air_m0c_trials/<时间戳>/`（summary.csv + 每场景 mat）、`results/air_m0a_baseline_compare/` 与注入回归新时间戳目录。
