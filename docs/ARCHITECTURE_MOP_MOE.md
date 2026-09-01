# 三模块架构与 MOP/MOE 评价体系（2026-09-01 定稿）

本文件是 `speed_esc_matlab/harness/` 的顶层设计说明，同时把本工程
（速度优化五任务）与 GitHub 仓库 `26isip_Aerospace` 的顶层设计对齐。

## 1. 仓库同步结果与本工程定位

`26isip_Aerospace` 已同步（本地分叉历史已 rebase 保双史并推送）。远端
顶层设计为**四层算法线 + 一条平台线**：

```text
第 1 层  转速比 ESC      modules/ratio_esc          已完成验收
第 2 层  平飞速度 ESC    modules/speed_esc          已完成验收(算法线)
第 3 层  残差速度 RL     modules/speed_rl_residual  代理对象预研
第 4 层  平台接入        models/px4_x8              M0-A/B/C、M1 完成，下一步 M2(eta分配器)
```

硬性红线（AGENTS.md，本工程同样遵守）：① 控制器/RL 观测只能接收测量
功率、实际被控量、采样时间与有效标志；② 对象升级只改
`power_map`/`plant_advance`/`measure` 侧，不动控制器因果接口；③ 结论
边界不越代理模型口径；④ 不提交 slprj/缓存。

**本工程（speed_esc_matlab）的定位**：五任务速度优化研究工作区——
在受控代理对象上快速迭代"任务定义→算法→评价"的完整闭环（任务1平移
搜索、任务2崎岖滤波寻优已完成；任务3-5风场圆周待做），成熟的方法与
验收结论按仓库红线回灌 `modules/` 各模块。它与仓库平台线互补：平台线
回答"算法能否安全接入飞控"，本工程回答"算法在系统级指标上是否够好"。

## 2. 三模块架构

```text
┌────────────────────┐   ┌────────────────────┐   ┌────────────────────┐
│  environment       │   │  aircraft 飞机模型  │   │  console 控制台     │
│  (风的模型)         │   │  速度表+功率表黑箱   │   │  (我们做的算法)     │
│  wind(t)->[wx,wy]  │──▶│  query(v,t)->P_meas │◀──│  只见双表盘读数     │
│  当前恒零风,        │   │  gauges()->两表盘   │   │  multistart/grid/  │
│  任务3-5接入风场    │   │  (瞬时执行+带噪)    │   │  esc/single/fixed  │
└────────────────────┘   └────────────────────┘   └────────────────────┘
         │                        │ 真值曲线/Pmin/v*            │
         └────────────▶ harness 评价器(对象侧) ◀──────────────┘
                        mop_moe(log, aircraft, c)
```

- **接口与红线对应**：`query` 只返回标量测量（红线1）；风场接入时只在
  aircraft 内换算空速（对象升级位置，红线2），三模块接口签名不变；
- **占位与真实**：environment 当前恒零风是任务2口径的真实占位——函数
  签名 `wind(t)` 已按任务3（恒风）/任务4（正弦风）/任务5（二维矢量风）
  的需求预留；
- **实现**：`+harness/make_environment.m`、`make_aircraft.m`、
  `make_console.m`；对象与搜索器复用 `task2_rugged/+task2`。

## 3. MOP / MOE 评价体系

概念（系统工程标准口径）：**MOE**（Measure of Effectiveness）度量任务/
作战效能，回答"任务目标达成了吗"，是指挥员视角；**MOP**（Measure of
Performance）度量系统技术性能，回答"是否按规格表现"，是工程师视角；
MOE 由若干 MOP 自上而下分解支撑。二者不可互换。

### 3.1 场景口径（用户定义）

- 任务窗 **T = 1 小时**（3600 s）；
- 评价器持有**先验理论最低功率 Pmin**（离线最优，归一化与瓦级两套）；
- 先验理论最低能耗 **Emin = Pmin × T**；
- 任务目标：最小化窗口内实际能耗 **E_actual = Σ P_true·tEval**。

### 3.2 MOE（效能）

```
MOE_energy = Emin / E_actual ∈ (0, 1]     越大越好
MOE_energy_W = (Pmin_W × T) / E_actual_W  同比值瓦级口径(实机接入口径)
```

- =1 当且仅当全程精确停在 Pmin（不可达上界：搜索/扰动必有代价）；
- `fixed` 控制台（开局即告知最优并全程锁定）作为**上界参照**参与横比，
  为所有算法标定"距理论最优还有多远"。

### 3.3 MOP（性能量，MOE 的分解）

| MOP | 定义 | 支撑关系 |
|---|---|---|
| tSearchEvals | 达到定位容差的评估步数 | 收敛速度→搜索段能耗→MOE |
| finalErr | 末段估计−全局最优 (m/s) | 定位精度→末段功率→MOE |
| regretPercent | 稳态功率超额% =100(P_tail−Pmin)/Pmin | 稳态品质→MOE |
| energyExcessPercent | 全程能量超额% =100(E−Emin)/Emin | **直接决定 MOE** |
| holdFraction | 锁定占空比 | 稳态经济性结构 |
| probeSteps / budgetUtilization | 搜索步数/预算利用率 | 评估预算占用 |

解析关系（已入单元测试）：`MOE_energy = 1/(1+energyExcess%/100)`——
这正是"MOE 由 MOP 分解"的标准结构：energyExcessPercent 是最直接的
MOP，tSearchEvals/finalErr 通过搜索代价与末段精度间接作用于 MOE。

### 3.4 首次横比结果（1小时窗，Pmin=0.9660 norm / 97 W）

| 控制台 | MOE_energy | 能耗超额% | 末误差 m/s | 稳态超额% | 锁定占空 |
|---|---:|---:|---:|---:|---:|
| fixed(上界参照) | 1.0000 | 0.00 | 0.000 | 0.000 | 1.00 |
| **multistart(推荐)** | **0.9912** | 0.88 | 0.233 | 0.403 | 0.94 |
| grid | 0.9905 | 0.96 | 0.125 | 0.119 | 0.96 |
| esc | 0.9819 | 1.85 | 0.308 | 1.561 | 0.00 |
| single_golden | 0.9226 | 8.39 | 3.925 | 8.386 | 1.00 |

解读：① MOE 一眼分出层级——掉进局部谷的 single_golden 差近 1% 能耗
（续航纪录口径下是巨大代价）；② multistart 用最少搜索代价逼近上界；
③ esc 的持续扰动使其锁定占空为 0、稳态超额 1.56%，印证任务1结论"可
终止搜索优于连续扰动"在能耗口径下依然成立；④ MOE 是**算法无关**的
统一标尺，任务3-5 的风场算法将直接在此口径下横比。

## 4. 落地文件与验证

```text
harness/
  +harness/config.m            评价窗/对象/噪声/瓦级标定参数
  +harness/make_environment.m  模块1: 风的模型(任务3-5预留 wind(t))
  +harness/make_aircraft.m     模块2: 双表盘黑箱(红线1/2对齐)
  +harness/make_console.m      模块3: 控制台调度(5种算法)
  +harness/mop_moe.m           MOE_energy / MOE_energy_W + 7项MOP
  run_mop_moe_demo.m           1小时窗五控制台横比(results/mop_moe/)
  tests_harness.m              4项单元测试(接线/因果边界/MOE定义/排序)
```

验证：4/4 单元测试通过（含 MOE 解析关系、因果边界无泄漏、fixed 上界、
multistart 优于单起点陷阱）；task2 13/13、task1 16/16、speedesc 14/14
回归不受影响。

## 5. 后续衔接

- 任务3-5：environment 接入恒风/正弦风/二维风（`wind(t)` 已预留），
  aircraft 内做空速换算，`run_mop_moe_demo` 不改结构即可横比风场算法；
- 与仓库对齐：harness 的 MOP/MOE 可作为 `26isip_Aerospace/harness/`
  （预留占位）的指标层草案；回灌时按红线2只替换对象侧；
- fixed 上界参照与"搜索能耗口径"继续沿用用户设定的续航纪录叙事。
