# platform_link_39（T3.9 / Q 系 Q1）：油门-电压功率估计链与敏感性批

> 状态：Q1 敏感性批执行完毕（占位参数口径不适用——本模块全部跑在既有 X8 P2 链上，
> 数字为**管线敏感性口径**，不是四旋翼结论）。方案与门定义见
> [`docs/QUAD_MIGRATION_PLAN_20260921.md`](../docs/QUAD_MIGRATION_PLAN_20260921.md)。

## 一、问题（为什么需要这个模块）

老师约束（2026-09-21）：实机无法直接获得输出功率，可观测 = **每电机油门**（飞控控制量）
+ **电池电压**（传感器直读）。现有算法线把"功率测量"当成真值在用（平台 P2 链
`q()` 返回就位真功率），功率一旦变成"从油门+电压估出来的量"，误差从
0.2 s/1.2% 无偏噪声变成**有结构、有偏、与被学习信号（空速）相关**的模型失配。

本模块在既有 X8 P2 平台上把测量链换成 **L0 静态台架估计器**，量化这个失配对
曲线寻优算法族的容忍度要求，产出三个决策输入：

1. **临界倾斜 b₁\***：估计器空速倾斜偏差多大时吃光学习臂的全部赢面（→ D1 是否需要 L1）；
2. **可申报误差带草案**：S1–S4 档位内五臂真实超额的漂移界（→ Q4/M6 的放行带）；
3. **最小驻留 t_dwell**：指令后采样需要等多久（→ 接口文档就位语义显式化，R4）。

## 二、估计器（L0，D1 推荐档）

```
P_hat = Σ_i P_bench(n_hat_i(pwm_i, V_hat), V_hat),   V_hat = V·(1+s4_vpct)
n_hat = frac(pwm)·nce(V_hat)      （H9 电压耦合反解，正向式 = plane.step L128 的诊断派生式）
P_bench = 电压分块 MN1005 多项式（与 P2 链同一查表，q39.p_coef）
不含：H3 前飞诱导节省 / H5 共轴干扰 / H4 废阻 / 辅助负载 / 电机动态
```

- 输入 = 植物诊断 `motor_pwm_us`(8) + `voltage_v`，即实机"指令侧+传感器侧"可观测
  量的仿真对应物（P2：接口不变，PWM 保持派生诊断量地位）；
- 结构性偏差（S3）= 上述"不含"项的物理内置失配：`P_hat − P_true =
  8·sav_H3 − 4·bench·δ_H5 − P_drag − P_aux`，逐项解析分解见 `q39/trim_curve.m`；
- 场景偏差注入（合成台架标定误差，非估计器知识）：S1 常数乘性、S2 空速倾斜
  `×(1+b·|u_air|)`、S4 电压标定偏差（反解与查表同时被污染）、S5 固定驻留采样；
- 预训练域一致性：purerl 臂在 L0 场景一律**在线预训练于同一估计口径 plant**
  （`pretrainCache=false`），避免真值链缓存模型的域差与估计器偏差混淆；
  ANCHOR（真值锚点幕）保留缓存以复现 moe38 口径。

## 三、实现与冻结边界

- 基底 = `platform_link_38/+w36/make_platform_plant.m`（滑动电压参照 + 真相位
  句柄，moe38 权威口径）复制为本模块 `+q39/make_platform_plant_l0.m`，唯一语义
  差异 = `q()` 返回口径（真值 → L0 估计）+ S5 驻留制替换就位委托制；
- 调度器 `+q39/run_algorithm.m` = 38 号 `run_algorithm` 副本（含 3.7 `*_pre`
  分支），plant 构造换 q39 版，臂函数仍调用 `w36.*` 原实现（臂只依赖三原语）；
- **零改动**：`models/plane`、`modules/platform_link{,_37,_38}`、全部 `.slx`、
  全部既有证据（P5 冻结）。真值口径日志列（powerTrue / 滑动电压 minPowerTrue）
  与基底逐位一致；新增 powerEstN / voltV 两列诊断；
- 双口径（P3）：真值口径照旧进 MOE/excess；估计口径 = powerMeas 列（0.2 s 延迟
  + 1.2% 噪声搬到估计量上）+ bias_meas_pct 记账。

## 四、Q1 矩阵（预注册，`+q39/q1_opt.m` 单一事实源）

共性：platform 后端，seed=11，3600 s，复合风 B=2.5 σ=0.3（moe38 锚点同配置）。
**预注册修正（开批前，依据 trim_curve 实测谷由 H3 创造、L0 曲线无谷）**：S1/S2/S5
改在 truth 口径+合成标定残差上测（b₁* 只对"已抓住曲线形状"的估计器有定义）；
S3/S4 留在 l0 基座。修正全文见证据文档 §1。

| 分块 | 基座 | 档位 | 臂 |
|---|---|---|---|
| ANCHOR | truth | 无（复现 moe38） | openloop/known/sweepcal/purerl_off/purerl_on（缓存预训练） |
| XCHECK | l0 | S3 | openloop/known（估计器无关性逐位验证 → 跨场景复用依据） |
| S3 | l0 | 结构偏差本体 | sweepcal/purerl_off/purerl_on |
| S1m3/S1p3/S1m5/S1p5 | truth | 常数 ±3%/±5% | sweepcal/purerl_off（+purerl_on@S1p5） |
| S2m07…S2p28 | truth | 倾斜 ±0.7/±1.4/±2.8 %/m/s | sweepcal/purerl_off（+purerl_on@±1.4） |
| S4p1/S4m1 | l0 | 电压标定 ±1% | sweepcal/purerl_off（+purerl_on@S4p1） |
| S5d1/S5d2/S5d5 | truth | 驻留 1/2/5 s | sweepcal/purerl_off（+purerl_on@S5d1） |
| RERUN | l0 | =S3，独立会话重跑 | 同 S3，与 S3 行逐位比对（M5） |

预注册缩减：purerl_on 跑 6 个代表档（覆盖全部场景族），全档留 Q4/M6 正式批；
openloop/known 与估计器无关（指令不读功率），只在 ANCHOR/XCHECK 各跑一次，
powerTrue 逐位一致后跨场景复用（XCHECK 幕验证）。

入口：

```matlab
cd modules/platform_link_39 && run_q1_checks        % 单元门 M1 + M5 冒烟 + 离线分解
run_q1_matrix('ANCHOR')                             % 分块批（每块独立 MATLAB 会话）
```

## 五、验证与结果（2026-09-21 批完成，详见证据目录）

- 单元门 8/8 全绿（`checks.log`）：M1 悬停/前飞一致性 ≤5e-5（门值注记见 tests_q1，计划原写 1e-9，因 P2 pwm 派生用一步延迟电压而修正并入档）；M1 前飞结构偏差 vs 就地解析分解 ≤1e-3（修正"δ 作用于扣 H3 后功率"口径后精确吻合）；油门往返 1e-12；M5 同会话两遍冒烟；openloop 估计器无关性逐位验证。
- 敏感性矩阵：19 分块（每块独立 MATLAB 会话）全部 rc=0，总耗时 2h51m；ANCHOR 逐位复现 moe38 3600s 锚点（openloop 6.2643/sweepcal 4.0241/purerl_off 0.4627/…）；M5 RERUN 39 字段逐位一致 PASS。
- **核心结论**：
  1. **L0 纯静态映射在 P2 口径下不可部署**（S3）：平台曲线谷由 H3 创造，L0 曲线无谷——sweepcal 赢面 −11.65pp（飞行点贴支撑下界 1.52 m/s），purerl_off 赢面 5.80→2.74pp、purerl_on →3.58pp；
  2. **临界倾斜 b₁\* = −2.6~−2.8 %/m/s**（S2，sweepcal 负向先破：拟合谷被推高 +1.62 m/s 后超额 6.64% > 开环 6.26%）；purerl_off/on ±2.8 全档未破（最坏剩 3.91pp）——"purerl 局部结构对全局倾斜更鲁棒"（方案 R1 缓解猜想）实测成立；
  3. **常数乘性偏差 ±5% 无害**（S1，全档磨损 ≤0.05pp，argmin 不变性实测）；
  4. **D3 电压归一化不需要**（S4：±1% 电压偏差 → ~±3% 常数性平移，margin 磨损 0.01~0.23pp）；
  5. **驻留**（S5）：P2 口径下固定驻留 ≤2s 无损、5s 因预算侵蚀（sweepcal −1.06pp）；瞬态污染主导的 t_dwell 只在实机电机动态中出现 → 接口申报"≥2s"，Q2 轨 B 复测定稿。
- **可申报误差带草案（→ Q4/M6 放行带）**：估计器残差"常数 ≤5% 且倾斜 |b₁|≤1.4 %/m/s"内，五臂赢面磨损 ≤0.9pp（< M6 门 1pp）。
- **决策**：D1 升 L1 档（气速修正）为四旋翼默认设计目标；D3 关闭（不需要）；Q4 正式批不得在 L0 口径下跑（purerl_off 磨损 3.06pp 超 M6 门）。

## 六、遗留与边界

- P2 无电机 spool 动态，S5 驻留只覆盖"慢俯仰+指令瞬态"的采样语义；实机电机动
  态带来的额外驻留需求在 Q2 轨 B（Simulink 一阶电机动态）重测；
- L0 的 H5 共轴惩罚是 X8 特有项（悬停 δ0=0.111），四旋翼（单桨）S3 将只剩
  H3+H4+aux 项——本批对四旋翼是**偏保守**的上界口径；
- 全部数字为 X8 占位管线口径（P4），不得引用为四旋翼真实节能或实飞结论。
