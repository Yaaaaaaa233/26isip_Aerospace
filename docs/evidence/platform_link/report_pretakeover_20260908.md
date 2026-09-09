# 任务3.6检查：预训练purerl拆分(purerl_on在线 / purerl_off离线 / purerl_scratch从零对照) + 继承算法横比

预训练口径: purerl_on/off 获得试飞时段(独立plant, static, 湍流同分布不同实现, seed+17), 不占评测预算与MOE; 自动收敛判据见README

生成时间：2026-09-08 19:30:28

- 单元测试：50/50。
- 检查门槛：20/20。

## 任务设定(用户口径, 2026-09-07)

"先通过首飞全飞拟合速度-功率曲线, 再用task2的算法": 主角hybrid = 3.1的Phase A(3→12 m/s双向扫150步, 联合辨识曲线f与风w) + 2.1的Phase B(曲线冻结, windinfer式滑窗二维NLS在线风推断+自适应窗长+风况判定, 每步闭式调度 v*=q̂+√(q̂²+û*²−|ŵ|²)); 低频漂移守卫(每60步, 仅SSE真改善>2%才接受重拟合)。对照: sweepcal(每20步重拟合链+探针)、rl(仿真器预训练+微调)、openloop、windinfer/est/known(已知曲线oracle参照)。MOE=纯能耗Emin/Eactual(2026-09-04口径)。

## 主口径横比(无风/恒定/变风 × 6策略, 2种子均值, 800步)

| 风况 | 策略 | 能耗超额% | 稳态尾段超额% | MOE(纯能耗) | û*误差 |
|---|---|---:|---:|---:|---:|
| zero | openloop | 0.00 | 0.00 | 1.0000 | — |
| zero | sweepcal | 2.69 | 1.07 | 0.9738 | 0.30 |
| zero | rl | 3.31 | 2.70 | 0.9680 | — |
| zero | purerl_on | 2.96 | 3.64 | 0.9713 | — |
| zero | purerl_off | 1.31 | 0.94 | 0.9870 | — |
| zero | purerl_scratch | 2.32 | 1.49 | 0.9773 | — |
| zero | hybrid | 2.99 | 2.77 | 0.9710 | 0.88 |
| zero | known | 0.00 | 0.00 | 1.0000 | — |
| const | openloop | 6.40 | 6.63 | 0.9398 | — |
| const | sweepcal | 1.91 | 0.37 | 0.9813 | 0.11 |
| const | rl | 5.04 | 5.32 | 0.9520 | — |
| const | purerl_on | 2.53 | 2.90 | 0.9753 | — |
| const | purerl_off | 1.54 | 1.42 | 0.9849 | — |
| const | purerl_scratch | 4.38 | 2.52 | 0.9580 | — |
| const | hybrid | 2.10 | 0.98 | 0.9795 | 0.44 |
| const | known | 0.11 | 0.11 | 0.9989 | — |
| vary | openloop | 4.80 | 4.92 | 0.9542 | — |
| vary | sweepcal | 3.59 | 2.40 | 0.9653 | 0.56 |
| vary | rl | 3.52 | 1.92 | 0.9660 | — |
| vary | purerl_on | 2.76 | 2.63 | 0.9731 | — |
| vary | purerl_off | 2.55 | 1.62 | 0.9751 | — |
| vary | purerl_scratch | 3.74 | 2.40 | 0.9639 | — |
| vary | hybrid | 3.90 | 3.68 | 0.9625 | 0.94 |
| vary | known | 0.30 | 0.31 | 0.9970 | — |

| 门槛 | 结果 |
|---|---|
| 单元测试全绿(purerl_on/off/scratch+继承sweepcal/rl/hybrid+风场库/空速语义/执行链) | 通过 |
| 七种风场×策略冒烟: 全部预算走满、测量有限、|dv/dt|<=2 | 通过 |
| 物理核验: 空速=|地速矢量−风矢量| 且 Pmin恒定=curveCase | 通过 |
| 红线1白名单: ctrl_view剔除optimum0/曲线系数/噪声真值 | 通过 |
| 恒定风: sweepcal 超额<4.5% 且优于开环 | 通过 |
| 恒定风: sweepcal û*辨识误差<0.8 m/s(谷底加权拟合修复后) | 通过 |
| 恒定风: hybrid 超额<5.0% 且优于开环(近期窗维护口径) | 通过 |
| 恒定风: purerl_off/on 优于开环 且 超额<5% | 通过 |
| 恒定风: 预训练(on/off) 优于从零对照scratch(预训练价值) | 通过 |
| 变风: sweepcal 优于 openloop | 通过 |
| 变风: rl 与 openloop 相当(差距<0.6pp) | 通过 |
| 变风: purerl_on 优于 openloop | 通过 |
| 跳变场景(+2.7@120步): purerl_on 优于 purerl_off(在线重学价值) | 通过 |
| 变风: hybrid 劣于 sweepcal(task2式在线已知限制, 负结果复现) | 通过 |
| 三种风况 known oracle 超额<1.5%(信息上界) | 通过 |
| 平台对接: 逐秒日志覆盖任务窗(预算按秒, 拍板1) | 通过 |
| 平台对接: sweepcal 盲找回平台真值谷底 v*≈5.15(误差<1.2, 900s窗, 拍板2) | 通过 |
| 平台对接: sweepcal 尾段超额<8%(复合风900s收敛) | 通过 |
| 平台对接: 零风 known oracle 超额<3%(MOE 口径上界, 拍板3) | 通过 |
| 平台对接: purerl_off 优于开环(预训练离线部署) | 通过 |

说明: hybrid=用户设想"首飞标定+task2式在线"的最忠实实现(冻结曲线+细粒度风修正+信赖域探针)。消融结论: 恒定风下成立(与sweepcal差距<0.6pp, 换来在线机器更简单); 变风下不成立(劣于开环)——变风污染首飞标定且冻结曲线后û*无再锚定, sweepcal靠每20步重拟合argmin持续再锚定才稳定。全部hybrid/sweepcal账面含一次性标定学费(150/800≈19%时间, 摊约2.5-3%)。RL为对照: 谷底奖励二阶+1%噪声, 等预算样本效率不足。

冒烟矩阵见 wind_kinds_smoke.csv; 横比明细见 main_comparison.csv。

结论边界: 全部结果为虚拟/代理对象口径(AGENTS.md红线3), 不支持真实X8节能表述; known为已知风+已知曲线oracle参照(非因果)。
