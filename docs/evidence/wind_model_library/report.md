# 任务9检查：七种可选风场模型库 × 空速-地速语义

生成时间：2026-09-03 12:23:43

- 单元测试：18/18。
- 检查门槛：5/5。

## 风场模型库(wind_field.m)

const恒定 / sin双正弦(任务4-8原口径) / square软边方波 / triangle三角 / turb OU湍流 / composite复合(慢变+湍流, 最贴近实际) / sector扇区(随航向)。
湍流序列以独立种子流(seed+917)预生成, 确定性可复现。

## 速度语义(用户口径)

空速=地速+风速(矢量和); 功率由空速决定 → 空速-功率标定曲线不随风移动, 地速-功率曲线随风平移; 仪表盘显示地速; 日志新增 airspeed/windX/windY 评价列。

## 主口径横比(3风场×3策略×3case, 3种子均值超额%)

| 风场 | 策略 | case95% | case90% | case85% |
|---|---|---:|---:|---:|
| sin | openloop | 4.92 | 5.87 | 6.93 |
| sin | qnewton | 4.97 | 6.45 | 7.62 |
| sin | known | 0.17 | 0.18 | 0.19 |
| composite | openloop | 4.85 | 5.79 | 6.84 |
| composite | qnewton | 4.87 | 6.10 | 7.41 |
| composite | known | 0.34 | 0.37 | 0.40 |
| sector | openloop | 4.86 | 5.73 | 6.70 |
| sector | qnewton | 4.65 | 4.93 | 5.92 |
| sector | known | 0.22 | 0.23 | 0.25 |

| 门槛 | 结果 |
|---|---|
| 单元测试全绿(风场模型库/空速语义/case锚点/执行链回归) | 通过 |
| 七种风场×九策略冒烟: 全部预算走满、测量有限、|dv/dt|<=2 | 通过 |
| 空速语义核验: 日志空速=|地速矢量+风矢量|(max差<1e-9) | 通过 |
| sin/composite/sector 下 known oracle 超额<1.5%(信息上界) | 通过 |
| 三种风场下 known 较 openloop 信息价值>2pp | 通过 |

冒烟矩阵见 wind_kinds_smoke.csv; 横比明细见 kinds_comparison.csv。

结论边界: 全部结果为虚拟/代理对象口径(AGENTS.md红线3), 不支持真实X8节能表述; known为已知风oracle参照(非因果), 不参与黑箱横比。
