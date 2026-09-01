# 任务1验收：平移曲线上的瞬时跳变黑箱搜索

生成时间：2026-09-01 10:10:18

对象为代理曲线平移(非X8实测)；速度瞬时生效；任务1无噪声；每评估步 1.0 s；全程 400 步。能耗开关两档均评估："开"把寻优过程能量计入验收，"关"只看定位与稳态。

- 单元测试：16/16。
- tracker性能门槛：8/8。

## tracker 门槛明细

| 门槛 | 结果 |
|---|---|
| tracker 静态场景定位精度<=eps | 通过 |
| tracker 静态场景入带评估数<=25 | 通过 |
| tracker dx跳变恢复步数<=30 | 通过 |
| tracker dy-only不触发重搜 | 通过 |
| tracker 慢漂末段误差<=0.15 m/s | 通过 |
| tracker 稳态超额<=0.2% | 通过 |
| 开关=开: tracker 全程能耗<=1.5% | 通过 |
| 开关=关: 能耗列全部为NaN(不参与判定) | 通过 |

## 全部场景结果(诚实记录，含未达标项)

| 能耗开关 | 曲线 | 场景 | 算法 | 末段误差m/s | 入带步数 | 恢复步数 | 稳态超额% | 全程能耗% | 重搜次数 |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| 开 | cubic | static | grid | 0.100 | NaN | NaN | 0.007 | 16.916 | NaN |
| 开 | cubic | static | ternary | 0.000 | 9 | NaN | 0.000 | 0.198 | NaN |
| 开 | cubic | static | golden | 0.000 | 8 | NaN | 0.000 | 0.141 | NaN |
| 开 | cubic | static | brent | 0.001 | 6 | NaN | 0.000 | 0.043 | NaN |
| 开 | cubic | static | tracker | 0.001 | 6 | NaN | 0.030 | 0.072 | 0 |
| 开 | cubic | static | esc | 0.024 | 45 | NaN | 0.097 | 0.529 | NaN |
| 开 | cubic | jumpUp | grid | 2.800 | NaN | Inf | 3.974 | 19.693 | NaN |
| 开 | cubic | jumpUp | ternary | 2.700 | 9 | Inf | 3.750 | 2.823 | NaN |
| 开 | cubic | jumpUp | golden | 2.700 | 8 | Inf | 3.750 | 2.766 | NaN |
| 开 | cubic | jumpUp | brent | 2.701 | 6 | Inf | 3.752 | 2.669 | NaN |
| 开 | cubic | jumpUp | tracker | 0.004 | 6 | 14 | 0.030 | 0.208 | 1 |
| 开 | cubic | jumpUp | esc | 0.024 | 45 | 68 | 0.097 | 0.636 | NaN |
| 开 | cubic | jumpDown | grid | 2.200 | NaN | Inf | 4.298 | 19.920 | NaN |
| 开 | cubic | jumpDown | ternary | 2.300 | 9 | Inf | 4.739 | 3.516 | NaN |
| 开 | cubic | jumpDown | golden | 2.300 | 8 | Inf | 4.738 | 3.457 | NaN |
| 开 | cubic | jumpDown | brent | 2.299 | 6 | Inf | 4.735 | 3.357 | NaN |
| 开 | cubic | jumpDown | tracker | 0.004 | 6 | 12 | 0.030 | 0.182 | 1 |
| 开 | cubic | jumpDown | esc | 0.024 | 45 | 48 | 0.097 | 0.717 | NaN |
| 开 | cubic | offset | grid | 0.100 | NaN | Inf | 0.007 | 16.292 | NaN |
| 开 | cubic | offset | ternary | 0.000 | 9 | 0 | 0.000 | 0.191 | NaN |
| 开 | cubic | offset | golden | 0.000 | 8 | 0 | 0.000 | 0.136 | NaN |
| 开 | cubic | offset | brent | 0.001 | 6 | 0 | 0.000 | 0.041 | NaN |
| 开 | cubic | offset | tracker | 0.001 | 6 | 0 | 0.028 | 0.069 | 0 |
| 开 | cubic | offset | esc | 0.024 | 45 | 0 | 0.092 | 0.529 | NaN |
| 开 | cubic | ramp | grid | 1.800 | NaN | NaN | 1.889 | 16.878 | NaN |
| 开 | cubic | ramp | ternary | 1.700 | 9 | NaN | 1.706 | 1.314 | NaN |
| 开 | cubic | ramp | golden | 1.700 | 8 | NaN | 1.707 | 1.258 | NaN |
| 开 | cubic | ramp | brent | 1.701 | 6 | NaN | 1.708 | 1.160 | NaN |
| 开 | cubic | ramp | tracker | 0.001 | 6 | NaN | 0.027 | 0.094 | 5 |
| 开 | cubic | ramp | esc | 0.024 | 45 | NaN | 0.097 | 0.542 | NaN |
| 开 | cubic | midsearch | grid | 0.000 | 46 | 39 | 0.000 | 8.411 | NaN |
| 开 | cubic | midsearch | ternary | 0.118 | NaN | Inf | 0.010 | 0.248 | NaN |
| 开 | cubic | midsearch | golden | 2.475 | NaN | Inf | 3.257 | 3.347 | NaN |
| 开 | cubic | midsearch | brent | 2.701 | 6 | Inf | 3.752 | 3.738 | NaN |
| 开 | cubic | midsearch | tracker | 0.004 | 6 | 20 | 0.030 | 0.265 | 1 |
| 开 | cubic | midsearch | esc | 0.024 | 76 | 69 | 0.097 | 0.395 | NaN |
| 开 | debug | static | grid | 0.000 | 31 | NaN | 0.000 | 3.788 | NaN |
| 开 | debug | static | ternary | 0.001 | 18 | NaN | 0.000 | 0.060 | NaN |
| 开 | debug | static | golden | 0.001 | 10 | NaN | 0.000 | 0.041 | NaN |
| 开 | debug | static | brent | 0.000 | 4 | NaN | 0.000 | 0.016 | NaN |
| 开 | debug | static | tracker | 0.000 | 4 | NaN | 0.013 | 0.028 | 0 |
| 开 | debug | static | esc | 0.013 | 72 | NaN | 0.040 | 0.240 | NaN |
| 开 | debug | jumpUp | grid | 2.700 | 31 | Inf | 2.187 | 5.318 | NaN |
| 开 | debug | jumpUp | ternary | 2.701 | 18 | Inf | 2.189 | 1.592 | NaN |
| 开 | debug | jumpUp | golden | 2.701 | 10 | Inf | 2.189 | 1.574 | NaN |
| 开 | debug | jumpUp | brent | 2.700 | 4 | Inf | 2.187 | 1.546 | NaN |
| 开 | debug | jumpUp | tracker | 0.000 | 4 | 10 | 0.013 | 0.079 | 1 |
| 开 | debug | jumpUp | esc | 0.013 | 72 | 56 | 0.040 | 0.284 | NaN |
| 开 | debug | jumpDown | grid | 2.300 | 31 | Inf | 1.587 | 4.898 | NaN |
| 开 | debug | jumpDown | ternary | 2.299 | 18 | Inf | 1.585 | 1.170 | NaN |
| 开 | debug | jumpDown | golden | 2.299 | 10 | Inf | 1.585 | 1.151 | NaN |
| 开 | debug | jumpDown | brent | 2.300 | 4 | Inf | 1.587 | 1.126 | NaN |
| 开 | debug | jumpDown | tracker | 0.000 | 4 | 9 | 0.013 | 0.057 | 1 |
| 开 | debug | jumpDown | esc | 0.013 | 72 | 65 | 0.040 | 0.318 | NaN |
| 开 | debug | offset | grid | 0.000 | 31 | 0 | 0.000 | 3.659 | NaN |
| 开 | debug | offset | ternary | 0.001 | 18 | 0 | 0.000 | 0.058 | NaN |
| 开 | debug | offset | golden | 0.001 | 10 | 0 | 0.000 | 0.040 | NaN |
| 开 | debug | offset | brent | 0.000 | 4 | 0 | 0.000 | 0.015 | NaN |
| 开 | debug | offset | tracker | 0.000 | 4 | 0 | 0.012 | 0.027 | 0 |
| 开 | debug | offset | esc | 0.013 | 72 | 0 | 0.038 | 0.251 | NaN |
| 开 | debug | ramp | grid | 1.700 | 31 | NaN | 0.867 | 4.151 | NaN |
| 开 | debug | ramp | ternary | 1.701 | 18 | NaN | 0.868 | 0.623 | NaN |
| 开 | debug | ramp | golden | 1.701 | 10 | NaN | 0.868 | 0.605 | NaN |
| 开 | debug | ramp | brent | 1.700 | 4 | NaN | 0.867 | 0.578 | NaN |
| 开 | debug | ramp | tracker | 0.000 | 4 | NaN | 0.013 | 0.039 | 5 |
| 开 | debug | ramp | esc | 0.013 | 65 | NaN | 0.040 | 0.247 | NaN |
| 开 | debug | midsearch | grid | 0.100 | NaN | Inf | 0.003 | 2.539 | NaN |
| 开 | debug | midsearch | ternary | 0.001 | 20 | 13 | 0.000 | 0.078 | NaN |
| 开 | debug | midsearch | golden | 2.864 | NaN | Inf | 2.461 | 2.466 | NaN |
| 开 | debug | midsearch | brent | 2.700 | 4 | Inf | 2.187 | 2.170 | NaN |
| 开 | debug | midsearch | tracker | 0.000 | 4 | 16 | 0.013 | 0.112 | 1 |
| 开 | debug | midsearch | esc | 0.013 | 64 | 57 | 0.040 | 0.130 | NaN |
| 关 | cubic | static | grid | 0.100 | NaN | NaN | 0.007 | NaN | NaN |
| 关 | cubic | static | ternary | 0.000 | 9 | NaN | 0.000 | NaN | NaN |
| 关 | cubic | static | golden | 0.000 | 8 | NaN | 0.000 | NaN | NaN |
| 关 | cubic | static | brent | 0.001 | 6 | NaN | 0.000 | NaN | NaN |
| 关 | cubic | static | tracker | 0.001 | 6 | NaN | 0.030 | NaN | 0 |
| 关 | cubic | static | esc | 0.024 | 45 | NaN | 0.097 | NaN | NaN |
| 关 | cubic | jumpUp | grid | 2.800 | NaN | Inf | 3.974 | NaN | NaN |
| 关 | cubic | jumpUp | ternary | 2.700 | 9 | Inf | 3.750 | NaN | NaN |
| 关 | cubic | jumpUp | golden | 2.700 | 8 | Inf | 3.750 | NaN | NaN |
| 关 | cubic | jumpUp | brent | 2.701 | 6 | Inf | 3.752 | NaN | NaN |
| 关 | cubic | jumpUp | tracker | 0.004 | 6 | 14 | 0.030 | NaN | 1 |
| 关 | cubic | jumpUp | esc | 0.024 | 45 | 68 | 0.097 | NaN | NaN |
| 关 | cubic | jumpDown | grid | 2.200 | NaN | Inf | 4.298 | NaN | NaN |
| 关 | cubic | jumpDown | ternary | 2.300 | 9 | Inf | 4.739 | NaN | NaN |
| 关 | cubic | jumpDown | golden | 2.300 | 8 | Inf | 4.738 | NaN | NaN |
| 关 | cubic | jumpDown | brent | 2.299 | 6 | Inf | 4.735 | NaN | NaN |
| 关 | cubic | jumpDown | tracker | 0.004 | 6 | 12 | 0.030 | NaN | 1 |
| 关 | cubic | jumpDown | esc | 0.024 | 45 | 48 | 0.097 | NaN | NaN |
| 关 | cubic | offset | grid | 0.100 | NaN | Inf | 0.007 | NaN | NaN |
| 关 | cubic | offset | ternary | 0.000 | 9 | 0 | 0.000 | NaN | NaN |
| 关 | cubic | offset | golden | 0.000 | 8 | 0 | 0.000 | NaN | NaN |
| 关 | cubic | offset | brent | 0.001 | 6 | 0 | 0.000 | NaN | NaN |
| 关 | cubic | offset | tracker | 0.001 | 6 | 0 | 0.028 | NaN | 0 |
| 关 | cubic | offset | esc | 0.024 | 45 | 0 | 0.092 | NaN | NaN |
| 关 | cubic | ramp | grid | 1.800 | NaN | NaN | 1.889 | NaN | NaN |
| 关 | cubic | ramp | ternary | 1.700 | 9 | NaN | 1.706 | NaN | NaN |
| 关 | cubic | ramp | golden | 1.700 | 8 | NaN | 1.707 | NaN | NaN |
| 关 | cubic | ramp | brent | 1.701 | 6 | NaN | 1.708 | NaN | NaN |
| 关 | cubic | ramp | tracker | 0.001 | 6 | NaN | 0.027 | NaN | 5 |
| 关 | cubic | ramp | esc | 0.024 | 45 | NaN | 0.097 | NaN | NaN |
| 关 | cubic | midsearch | grid | 0.000 | 46 | 39 | 0.000 | NaN | NaN |
| 关 | cubic | midsearch | ternary | 0.118 | NaN | Inf | 0.010 | NaN | NaN |
| 关 | cubic | midsearch | golden | 2.475 | NaN | Inf | 3.257 | NaN | NaN |
| 关 | cubic | midsearch | brent | 2.701 | 6 | Inf | 3.752 | NaN | NaN |
| 关 | cubic | midsearch | tracker | 0.004 | 6 | 20 | 0.030 | NaN | 1 |
| 关 | cubic | midsearch | esc | 0.024 | 76 | 69 | 0.097 | NaN | NaN |
| 关 | debug | static | grid | 0.000 | 31 | NaN | 0.000 | NaN | NaN |
| 关 | debug | static | ternary | 0.001 | 18 | NaN | 0.000 | NaN | NaN |
| 关 | debug | static | golden | 0.001 | 10 | NaN | 0.000 | NaN | NaN |
| 关 | debug | static | brent | 0.000 | 4 | NaN | 0.000 | NaN | NaN |
| 关 | debug | static | tracker | 0.000 | 4 | NaN | 0.013 | NaN | 0 |
| 关 | debug | static | esc | 0.013 | 72 | NaN | 0.040 | NaN | NaN |
| 关 | debug | jumpUp | grid | 2.700 | 31 | Inf | 2.187 | NaN | NaN |
| 关 | debug | jumpUp | ternary | 2.701 | 18 | Inf | 2.189 | NaN | NaN |
| 关 | debug | jumpUp | golden | 2.701 | 10 | Inf | 2.189 | NaN | NaN |
| 关 | debug | jumpUp | brent | 2.700 | 4 | Inf | 2.187 | NaN | NaN |
| 关 | debug | jumpUp | tracker | 0.000 | 4 | 10 | 0.013 | NaN | 1 |
| 关 | debug | jumpUp | esc | 0.013 | 72 | 56 | 0.040 | NaN | NaN |
| 关 | debug | jumpDown | grid | 2.300 | 31 | Inf | 1.587 | NaN | NaN |
| 关 | debug | jumpDown | ternary | 2.299 | 18 | Inf | 1.585 | NaN | NaN |
| 关 | debug | jumpDown | golden | 2.299 | 10 | Inf | 1.585 | NaN | NaN |
| 关 | debug | jumpDown | brent | 2.300 | 4 | Inf | 1.587 | NaN | NaN |
| 关 | debug | jumpDown | tracker | 0.000 | 4 | 9 | 0.013 | NaN | 1 |
| 关 | debug | jumpDown | esc | 0.013 | 72 | 65 | 0.040 | NaN | NaN |
| 关 | debug | offset | grid | 0.000 | 31 | 0 | 0.000 | NaN | NaN |
| 关 | debug | offset | ternary | 0.001 | 18 | 0 | 0.000 | NaN | NaN |
| 关 | debug | offset | golden | 0.001 | 10 | 0 | 0.000 | NaN | NaN |
| 关 | debug | offset | brent | 0.000 | 4 | 0 | 0.000 | NaN | NaN |
| 关 | debug | offset | tracker | 0.000 | 4 | 0 | 0.012 | NaN | 0 |
| 关 | debug | offset | esc | 0.013 | 72 | 0 | 0.038 | NaN | NaN |
| 关 | debug | ramp | grid | 1.700 | 31 | NaN | 0.867 | NaN | NaN |
| 关 | debug | ramp | ternary | 1.701 | 18 | NaN | 0.868 | NaN | NaN |
| 关 | debug | ramp | golden | 1.701 | 10 | NaN | 0.868 | NaN | NaN |
| 关 | debug | ramp | brent | 1.700 | 4 | NaN | 0.867 | NaN | NaN |
| 关 | debug | ramp | tracker | 0.000 | 4 | NaN | 0.013 | NaN | 5 |
| 关 | debug | ramp | esc | 0.013 | 65 | NaN | 0.040 | NaN | NaN |
| 关 | debug | midsearch | grid | 0.100 | NaN | Inf | 0.003 | NaN | NaN |
| 关 | debug | midsearch | ternary | 0.001 | 20 | 13 | 0.000 | NaN | NaN |
| 关 | debug | midsearch | golden | 2.864 | NaN | Inf | 2.461 | NaN | NaN |
| 关 | debug | midsearch | brent | 2.700 | 4 | Inf | 2.187 | NaN | NaN |
| 关 | debug | midsearch | tracker | 0.000 | 4 | 16 | 0.013 | NaN | 1 |
| 关 | debug | midsearch | esc | 0.013 | 64 | 57 | 0.040 | NaN | NaN |

基线(grid/ternary/golden/brent/esc)不设门槛，仅横评。"搜索后锁定"算法在平移后不重搜属预期行为，正是tracker监测层的对照证据。
