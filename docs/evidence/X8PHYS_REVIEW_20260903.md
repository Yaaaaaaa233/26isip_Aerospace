# X8PHYS 代码审核与验收证据（2026-09-03）

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：待组内确认
本次贡献：周航正（数据与审核要求）；Codex（代码审核、修复、数据复核和验收）
审核：待项目组审核、待指导教师确认
AI协助：Codex

## 审核对象与等级

- 目标基线：`origin/main` 的 `e5d57456559d148783544eb9c936c0e92c23d2a6` 加本次待提交分支；下表平台补充回归在 rebase 前的 `f75b77e` 同一 `.slx` 上执行。
- 对象：`models/px4_x8/+x8phys`、`models/plane` 及对应适配器、测试和权威文档。
- 证据等级：`proxy/estimated`。不支持真实 X8 节能、续航、飞行安全或已标定电池结论。

## P0 数据复核

- 三份主目录源文件只读复核并比对 SHA-256；已用精确根路径加入 `.gitignore`，不得进入 Git。
- 静推表含 18/21/24/27/30 V 五档 129 个有效转速点；按 `T>=100 gf` 使用 126 点。
- 五档 `T=k*n^2` 最小 `R^2=0.99986`，`k` 全距/均值 1.18%，通过 `R^2>=0.995`、离散度 `<=2%`。
- 汇总拟合 `T=0.08643*n^2`、`P_e=0.34467*n+0.0289367*n^3`、`KV=76.64 rpm/(V*throttle)`；详细清洗记录见 `models/px4_x8/data/X8PHYS_DATA.md`。
- 电芯报告直接支持 0.2C 平均容量 24.0 Ah、建议 2.8--4.2 V、2C 容量保持率大于 97% 和 3C/300 s 温度 60/61 摄氏度。7S1P 与内阻查表仍是待确认 proxy。

## 审核修复

- 区分请求 PWM 与限幅/截止后的实际施加 PWM；平台样本只输出施加值。
- 修复 Thevenin 功率越限时 `V*I` 与输出功率不一致，以及低 SOC 截止后端电压可能高于 OCV 的问题。
- 补充配置、初始状态、测量有限性和平台阈值校验；适配器字段白名单继续阻止对象 truth 混入测量上下文。
- 将 X8PHYS 门槛改为同状态风对比，并增加功率单调、`dt=0`、四元数、能量、SOC、功率平衡、限幅、截止和错误输入断言。
- 修复统一 Plane 误用测量风驱动物理对象、PathCommand 混入 WindSample、风速重复相减、时间常数未生效、圆周径向漂移、功率越限不守恒和 SOC 测试恒真的问题；实现接口字典 0.3 的 Path/Wind/Control 分离并补 `power_model_id`。

## 2026-09-03 实跑结果

| 入口 | 结果 | 关键值/说明 |
|---|---|---|
| `run_x8phys_acceptance` | PASS | 同状态 800 rpm：零风 597.490 W，20 m/s 风 961.047 W；能量误差 0；功率平衡误差 `2.01e-16` |
| `run_plane_acceptance` | PASS | 零风/5 m/s 风 323.574/273.664 W；能量与受限功率平衡误差 0；整周相位/半径闭合 |
| `test_m0c_esc_unit` | PASS | 四组单元门槛通过 |
| `test_m0c_installer_dirty_guard` | PASS | `air_spare.slx` 哈希保持 `d2bd8d11...03a2ef` |
| `test_m2_eta_esc_unit` | PASS | 分配器、ESC、失效保持和全局量恢复通过 |
| `run_air_m0a_baseline_compare` | PASS | `pwm_cmd`、真实 `Ve`、`quat` 最大逐样本差 0；35 维日志检查通过 |
| `run_air_m0c_trials` | PASS 后退出清理异常 | 九组场景、四组配对和复现断言均打印 PASS；随后 R2022b 退出清理停滞，人工中断 |
| `verify_m2_round4_closure('c3')` | PASS | 受控失败 + 完整 `run_air_m2_trials`；S1/S2/S3 为 -0.26262%/-0.29380%/-0.21465%，复现差 0 |
| `run_air_m0b_safety_injection` | 未完成 | 三次均在首个 `pwm_edge` 的模型 update/sim 阶段停滞；约 34.7 s CPU 后不再增长，人工中断 |
| `run_air_m1_robustness` | 未完成 | R0 fixed/esc 通过；`WN1_fixed` 注入阶段约 59.6 s CPU 后停滞，人工中断 |
| `tools/check_repo_governance.ps1`（`pwsh`） | PASS | 15 个登记模块、27 份活动 Markdown |

## ADR-003 四层判定

- 功能实现层：**VALIDATED（E0/E1 proxy/estimated 范围）**。X8PHYS README 的 P0 静推拟合门槛和 P1--P4 独立对象/适配器契约满足；Path/Wind/Control 因果边界通过测试。
- 验收基础设施层：**VALIDATED（新对象入口）/PARTIAL（补充平台当次回归）**。`run_x8phys_acceptance`、`run_plane_acceptance` 均为函数、返回机器结果并硬断言；M0-A/M0-C/M2 补充回归完成，M0-B/M1 当次矩阵未完成。
- 环境层：**OPEN LIMITATION**。本机 R2022b 在 M0-B/M1 内存注入场景可复现停滞；没有出现功能 FAIL 断言，也不据此倒推已冻结平台核心失败。
- 文档证据层：**COMPLETE（本次范围）**。数据哈希、清洗规则、门槛、实跑值、失败边界和不可外推结论均已登记。

本次没有修改 `.slx`，旁路逐样本差为 0。完整平台回归未全绿，不能宣称“全平台当次验收完成”；按已采纳 ADR-003，已登记且未指向对象回归的环境限制不倒推 X8PHYS/Plane 功能层失败。本证据支持提交独立对象/适配器分支，但整机 S/P、动态桨效应、阻力和温度仍未校准，不能提升证据等级。
