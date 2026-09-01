# 2026-09-01 M0-C 速度在线 ESC 接入与验收（ZCode 会话简报）

## 背景

codex 独立复验通过 M0-B（`4c57fe8`）并放行 M0-C，同时提出三条非阻塞要求（成本窗口统一为仅 active、恢复断言入常规回归、verifyLink 校验源端口）。按用户指示"先方案文档、后实施、按文档验收"，M0-C 执行基线先落 [`../interfaces/M0C_SPEED_ESC.md`](../interfaces/M0C_SPEED_ESC.md) 并提交（`1cd3b59`），随后实施。

## 实施与结果（证据：[`../evidence/M0C_TRIALS_20260901.md`](../evidence/M0C_TRIALS_20260901.md)）

1. **算法接口封装**：`m0c_vref_esc.m` 直接复用 Git 仓库 `modules/ratio_esc` 内核（`config → controller_config 白名单 → esc_reset/esc_step`），输入仅 `[t, v, P_e, E_e, att(6), flags(8)]`、输出仅 `v_ref`；`mode='fixed'`（恒 center0）与 `'esc'`（在线寻优）共用同一模型接线，仅一个 global 参数之差，保证配对公平。不接入 eta 分配器，不做 RL。
2. **单元测试先行**（`test_m0c_esc_unit.m`）：解析碗标定 `gain=6e-3`；U1–U4 全过。
3. **安装**（`add_air_m0c_esc.m`）：Interpreted MATLAB Fcn 普通方块 + 每输入 0.05 s ZOH（绕开 logged 功率信号不可自动插速率转换的限制）；逐支路删线、保存前功能仿真、保存后磁盘重载 35 条连线断言（含源端口句柄相等，codex 意见 4.3）、失败自动恢复装前备份。
4. **回归全绿**：compare 四信号差 0；注入位 1/4/6/7 全过，power_rec 延长至 13 s 并断言"重新 active + 参考恢复 9±0.5"（codex 意见 4.2）。
5. **五组配对 + 复现组全过**（`results/air_m0c_trials/20260901_121516/`）：三组名义 esc 均收敛（4/4/8 s），扰动对如实报告窗口受限；`R_esc` 与 `T2_esc` 逐样本差 **0**；无饱和（PWM [1499,1501]）、无硬标志、无回退；ΔE ≈ −0.12%/−0.36%（窗口掩码伪差，P 均值 251 W 逐位一致——平坦功率面预判成立，**无可宣称的节能改善**）。
6. 快照 `air_m0c.slx` 已另存（SHA256 `f9be88df…`，与验收时 air_spare 一致；air_m0b.slx 未触碰）。

## 新增工程经验（后续并入接口文档 §4 类目）

- **Interpreted MATLAB Fcn 会在编译期被调用一次做维度推断**：持久状态型适配器必须把该"编译期探针调用"与真实仿真区分开（块显式采样时间 + 复位条件 `k <= lastK`），否则首场景以默认参数运行、global 配置失效。
- 多速率混入 Mux 时，logged 信号（M0A 功率 chart 输出）不能自动插速率转换——所有输入先过显式 ZOH 统一采样率。
- 模块 `limit_reference` 的 `rateLimit` 单位是 m/s²（每步增量 = rateLimit·Ts），误配一个量级会把 dither 削成三角波、梯度归零。
- 稳定窗口口径（codex 4.1）：成本仅取 status==2 且位 5 静默样本；engaged（{1,2}）只作接管诊断。selector 对移动目标的 2↔1 抖动（~0.05 s 周期）是精确相等判据的固有现象，selector 本体零改动。

## 会话交接

- 本地新增脚本：`models/px4_x8/{m0c_vref_esc,add_air_m0c_esc,test_m0c_esc_unit,run_air_m0c_trials}.m`（另存诊断脚本 `diag_m0c_*.m` 4 个），已与仓库同步。
- 下一步按路线图进入 M1（扰动、噪声与时延鲁棒性）；任何结构变更后重跑 compare + 注入回归；M1 前建议先清理 Att Demux 空支路告警（非阻塞）。
