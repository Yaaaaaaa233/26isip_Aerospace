# 平飞速度ESC整合版：实际验收记录

生成时间：2026-08-31 18:56:44

全部为代理模型，不是X8实测。功能通过与性能达标分开记录。

- MATLAB单元测试：14/14。
- 原Python复现：1，14组。
- MATLAB/Simulink一致性：1，6组。
- RL环境/完整回合：1，未训练策略。
- 默认回归算法功率指标：74/74；速度均值误差指标：63/74。

## 口径

无噪声V1/V2功率超额阈值1%，V3为3%；实际速度末段均值误差V1/V2为0.5 m/s、V3为0.7 m/s。末段为最后20秒，包含微扰代价。

V3种子11–20未用于前期窗口选择；不同工况/算法使用同种子噪声。固定基线与优化器使用相同初始速度、执行响应和参考限速。

收敛时刻是后向12.6秒实际速度均值进入容差并连续保持5秒后的确认时刻，不回填为较早样本，也不保证之后永不离开；NaN表示观察期内未确认。

| 曲线 | 阶段/场景 | 方法 | 种子 | 初速 | 功率超额% | 速度误差m/s | 功率通过 | 速度通过 |
|---|---|---|---:|---:|---:|---:|---|---|
| debug | V1/clean | regression | 1 | 2.0 | 0.0356 | 0.1018 | 1 | 1 |
| debug | V1/clean | regression | 1 | 10.0 | 0.0355 | 0.0855 | 1 | 1 |
| debug | V1/clean | regression | 1 | 15.0 | 0.0359 | 0.0779 | 1 | 1 |
| debug | V2/clean | regression | 1 | 2.0 | 0.0238 | 0.0088 | 1 | 1 |
| debug | V2/clean | regression | 1 | 10.0 | 0.0220 | 0.0858 | 1 | 1 |
| debug | V2/clean | regression | 1 | 15.0 | 0.0432 | 0.2538 | 1 | 1 |
| debug | V3/noise | regression | 11 | 10.0 | 0.1911 | 0.6362 | 1 | 1 |
| debug | V3/noise | regression | 12 | 10.0 | 0.3972 | 1.0249 | 1 | 0 |
| debug | V3/noise | regression | 13 | 10.0 | 0.0494 | 0.0323 | 1 | 1 |
| debug | V3/noise | regression | 14 | 10.0 | 0.0593 | 0.1136 | 1 | 1 |
| debug | V3/noise | regression | 15 | 10.0 | 0.2179 | 0.4745 | 1 | 1 |
| debug | V3/noise | regression | 16 | 10.0 | 0.3987 | 0.6415 | 1 | 1 |
| debug | V3/noise | regression | 17 | 10.0 | 0.1754 | 0.5663 | 1 | 1 |
| debug | V3/noise | regression | 18 | 10.0 | 0.3289 | 0.9749 | 1 | 0 |
| debug | V3/noise | regression | 19 | 10.0 | 0.1574 | 0.4009 | 1 | 1 |
| debug | V3/noise | regression | 20 | 10.0 | 0.1905 | 0.2300 | 1 | 1 |
| debug | V3/delay | regression | 11 | 10.0 | 0.0293 | 0.1641 | 1 | 1 |
| debug | V3/combined | regression | 11 | 10.0 | 0.1993 | 0.5873 | 1 | 1 |
| debug | V3/combined | regression | 12 | 10.0 | 0.5488 | 1.2752 | 1 | 0 |
| debug | V3/combined | regression | 13 | 10.0 | 0.0945 | 0.0786 | 1 | 1 |
| debug | V3/combined | regression | 14 | 10.0 | 0.1007 | 0.4233 | 1 | 1 |
| debug | V3/combined | regression | 15 | 10.0 | 0.4358 | 1.0294 | 1 | 0 |
| debug | V3/combined | regression | 16 | 10.0 | 0.2187 | 0.5277 | 1 | 1 |
| debug | V3/combined | regression | 17 | 10.0 | 0.2288 | 0.6812 | 1 | 1 |
| debug | V3/combined | regression | 18 | 10.0 | 0.4019 | 1.0986 | 1 | 0 |
| debug | V3/combined | regression | 19 | 10.0 | 0.2455 | 0.8257 | 1 | 0 |
| debug | V3/combined | regression | 20 | 10.0 | 0.1582 | 0.1272 | 1 | 1 |
| debug | V3/shift | regression | 11 | 10.0 | 0.2058 | 0.6075 | 1 | 1 |
| debug | V3/shift | regression | 12 | 10.0 | 0.1874 | 0.6172 | 1 | 1 |
| debug | V3/shift | regression | 13 | 10.0 | 0.0523 | 0.3445 | 1 | 1 |
| debug | V3/shift | regression | 14 | 10.0 | 0.0318 | 0.1066 | 1 | 1 |
| debug | V3/shift | regression | 15 | 10.0 | 0.1962 | 0.6244 | 1 | 1 |
| debug | V3/shift | regression | 16 | 10.0 | 0.0598 | 0.1732 | 1 | 1 |
| debug | V3/shift | regression | 17 | 10.0 | 0.2580 | 0.6609 | 1 | 1 |
| debug | V3/shift | regression | 18 | 10.0 | 0.3793 | 0.1239 | 1 | 1 |
| debug | V3/shift | regression | 19 | 10.0 | 0.1996 | 0.7175 | 1 | 0 |
| debug | V3/shift | regression | 20 | 10.0 | 0.4261 | 0.7765 | 1 | 0 |
| cubic | V1/clean | regression | 1 | 2.0 | 0.0852 | 0.0871 | 1 | 1 |
| cubic | V1/clean | regression | 1 | 10.0 | 0.0853 | 0.0882 | 1 | 1 |
| cubic | V1/clean | regression | 1 | 15.0 | 0.0845 | 0.0885 | 1 | 1 |
| cubic | V2/clean | regression | 1 | 2.0 | 0.0470 | 0.0684 | 1 | 1 |
| cubic | V2/clean | regression | 1 | 10.0 | 0.0479 | 0.0726 | 1 | 1 |
| cubic | V2/clean | regression | 1 | 15.0 | 0.0504 | 0.0651 | 1 | 1 |
| cubic | V3/noise | regression | 11 | 10.0 | 0.1499 | 0.3088 | 1 | 1 |
| cubic | V3/noise | regression | 12 | 10.0 | 0.4228 | 0.6727 | 1 | 1 |
| cubic | V3/noise | regression | 13 | 10.0 | 0.1003 | 0.1364 | 1 | 1 |
| cubic | V3/noise | regression | 14 | 10.0 | 0.0676 | 0.1105 | 1 | 1 |
| cubic | V3/noise | regression | 15 | 10.0 | 0.1311 | 0.2082 | 1 | 1 |
| cubic | V3/noise | regression | 16 | 10.0 | 0.0573 | 0.0933 | 1 | 1 |
| cubic | V3/noise | regression | 17 | 10.0 | 0.1269 | 0.3168 | 1 | 1 |
| cubic | V3/noise | regression | 18 | 10.0 | 0.2937 | 0.5318 | 1 | 1 |
| cubic | V3/noise | regression | 19 | 10.0 | 0.1096 | 0.2106 | 1 | 1 |
| cubic | V3/noise | regression | 20 | 10.0 | 0.2056 | 0.1072 | 1 | 1 |
| cubic | V3/delay | regression | 11 | 10.0 | 0.0503 | 0.0827 | 1 | 1 |
| cubic | V3/combined | regression | 11 | 10.0 | 0.1868 | 0.3763 | 1 | 1 |
| cubic | V3/combined | regression | 12 | 10.0 | 0.4674 | 0.7113 | 1 | 0 |
| cubic | V3/combined | regression | 13 | 10.0 | 0.1301 | 0.0875 | 1 | 1 |
| cubic | V3/combined | regression | 14 | 10.0 | 0.0689 | 0.1437 | 1 | 1 |
| cubic | V3/combined | regression | 15 | 10.0 | 0.1517 | 0.2362 | 1 | 1 |
| cubic | V3/combined | regression | 16 | 10.0 | 0.0585 | 0.0254 | 1 | 1 |
| cubic | V3/combined | regression | 17 | 10.0 | 0.1405 | 0.3425 | 1 | 1 |
| cubic | V3/combined | regression | 18 | 10.0 | 0.3093 | 0.5460 | 1 | 1 |
| cubic | V3/combined | regression | 19 | 10.0 | 0.1118 | 0.2157 | 1 | 1 |
| cubic | V3/combined | regression | 20 | 10.0 | 0.2216 | 0.1385 | 1 | 1 |
| cubic | V3/shift | regression | 11 | 10.0 | 0.0388 | 0.0177 | 1 | 1 |
| cubic | V3/shift | regression | 12 | 10.0 | 0.2264 | 0.6694 | 1 | 1 |
| cubic | V3/shift | regression | 13 | 10.0 | 0.0653 | 0.1560 | 1 | 1 |
| cubic | V3/shift | regression | 14 | 10.0 | 0.0490 | 0.2976 | 1 | 1 |
| cubic | V3/shift | regression | 15 | 10.0 | 0.3048 | 0.8799 | 1 | 0 |
| cubic | V3/shift | regression | 16 | 10.0 | 0.4469 | 1.1171 | 1 | 0 |
| cubic | V3/shift | regression | 17 | 10.0 | 0.0728 | 0.2793 | 1 | 1 |
| cubic | V3/shift | regression | 18 | 10.0 | 0.0920 | 0.0452 | 1 | 1 |
| cubic | V3/shift | regression | 19 | 10.0 | 0.0270 | 0.1284 | 1 | 1 |
| cubic | V3/shift | regression | 20 | 10.0 | 0.0973 | 0.1669 | 1 | 1 |
| debug | V1/demod_comparison | demod | 11 | 10.0 | 0.0570 | 0.2727 | 1 | 1 |
| debug | V3/demod_comparison | demod | 11 | 10.0 | 0.0405 | 0.2455 | 1 | 1 |
| cubic | V1/demod_comparison | demod | 11 | 10.0 | 0.1036 | 0.2064 | 1 | 1 |
| cubic | V3/demod_comparison | demod | 11 | 10.0 | 0.5580 | 1.3041 | 1 | 0 |

0表示未达标，1表示达标。经典解调为独立参数的对照案例，不据少量测试宣称任一方法普遍更优。
