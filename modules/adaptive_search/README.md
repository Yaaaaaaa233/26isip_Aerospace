# 任务6·自适应算法库 + 双层MOP/MOE：控制台(console) × 飞机模型(aircraft) × 环境模型(environment)

> 本文件夹 = 任务6程序。在任务5(双正交正弦风×圆周盘旋)的场景与三模块面板基础上，
> 双层MOP/MOE分层口径与 `docs/ARCHITECTURE_MOP_MOE.md`（MOE=任务效能/MOP=性能量分解）一致。
> 新增三件事：**适用于该风场情景的新算法**、**结果卡片上移**、**双层MOP/MOE评价体系**。
> 任务5及之前的文件一律未改动(本文件夹为独立副本)。

## 1. 新增算法(左侧"搜索算法"下拉)

| 算法 | 一句话设计 | 验收表现(风场静态20种子/1h窗) |
|---|---|---|
| `spsa` 随机同步扰动寻优 | Spall SPSA + **占空比调度**：每8步一对±1.5探针(间隔3与λ1=6,λ2=2整倍对齐→涟漪斜率差分相消)，其余步停在信念；增益不衰减(持续跟踪时变最优)，梯度EWMA压噪 | 尾段误差0.433(tracker 0.805)；**跳变恢复10~18步**(ea口径≤260)；1h MOE 0.978 |
| `bayes` 贝叶斯代理寻优 | GP回归(SE核) + 置信下界LCB采集 + 滑窗36(陈旧观测自动老化) + 核长边际似然在线选择 + 占空比hold | **全局定位最快settle 8~18步**(全算法第一)；时变尾段跟踪非其专长(如实横评) |
| `qnewton` 牛顿拟合寻优(新推荐) | **两相制**：宽stencil(±1.5)全局下降防涟漪局部谷 → 小stencil(±0.25)牛顿精调(探针停在谷内，单步能耗≈0.5% vs 宽stencil≈4%)；曲率由割线关系自校正(b_sec=(ĝ新−ĝ旧)/(2s))，收敛后冻结；宽监测每20步发现漂出谷自动重入相位1 | **尾段误差0.272**(全算法最低)；**1h MOE 0.987**(超任务5推荐ea 0.975)；可用率0.72~0.77；跳变恢复31~63步 |

**推荐结论**：`qnewton` 在"更准/更省"上全面超越既有方案(面板默认已设为qnewton)；
`spsa` 在"更快恢复"上独占优势；`bayes` 适合冷启动全局定位。
黑箱因果红线不变：算法只见 `plant.q(v,tag)` 带噪测量。

## 2. MOP/MOE评价结果卡片(界面调整)

原位于整个demo最下方的MOE/末误差汇总，已移至**左侧日志栏正上方**的红色
"★ MOP/MOE 评价结果(任务窗终点)"卡片，显著展示：

- 第1行大字：**MOE 综合效能 overall**(≥0.99绿 / ≥0.97橙 / 其余红)
- 续航能效 MOE_energy(含能耗超额) / 瞬时能效 instant(含稳态超额)
- 入带步数 / 任务可用率 / 搜索步数 / 稳态波动σ

卡片在每次"末帧/播放结束"时随 `report()` 刷新，数值与 `wsearch.mop_moe` 一致。

## 3. 双层MOP/MOE评价体系(评价口径完善)

| 层 | 指标 | 含义 |
|---|---|---|
| **MOP 性能度量**(系统做得好不好) | finalErr / settleSteps / steadyFluct / searchSteps / inBandRate / recoverySteps | 末误差 / 首次入带步数 / 尾段估计波动 / 搜索代价 / 全程入带率 / dx平移后恢复步数(风场振荡自动判别不误记) |
| **MOE 任务效能**(任务完成了多少) | energy / instant / availability / **overall** | 续航能效Emin/Eactual / 尾段瞬时能效mean(Pmin/Ptrue) / 最优带可用率 / 综合=0.5·energy+0.3·instant+0.2·availability |

能耗开关=关时能耗类(energy/instant/overall)记NaN、可用率保留；顶层旧字段
(MOE_energy/finalErr/regretPercent/...)全部保留，任务1~5口径向后兼容。

## 4. 验收(10/10门槛, 28/28测试)

```
run_task6_acceptance      % results/report.md + scenarios.csv + moe_1h.csv
tests_task6               % 28个单元测试
qa_task6_demo             % 面板自检(算法切换/结果卡片/开关不改变日志/导出)
```

门槛要点(报告内有明细)：
- qnewton 风场尾段≤0.5 ≥18/20种子；MOE≥0.975 ≥18/20
- spsa与qnewton尾段均值均 < tracker迟滞口径
- spsa跳变恢复≤60步 ≥9/10(ea口径≤260)；qnewton≤120步 ≥9/10
- 1h窗：spsa与qnewton MOE > esc；qnewton ≥ ea(新推荐超越旧推荐)
- bayes settle≤40 ≥16/20(定位专长)；tracker能耗优势来自平坦无噪设计点(如实标注)
- 风速=0退化fixed MOE=1；能耗开关关档NaN列

## 5. 文件清单

```
+wsearch/            算法包(任务5全部 + spsa_run/bayes_run/qnewton_run/gp_posterior/新mop_moe)
launch_task6_demo.m  三模块面板(算法库下拉 + 结果卡片 + 新算法探针图层'search')
tests_task6.m        28个测试(任务5的19个 + 新算法/MOP-MOE/GP后验9个)
run_task6_acceptance.m  验收脚本
qa_task6_demo.m      面板自检
START_HERE.m         入口说明
results/             报告与横评CSV(可由脚本重建)
```

## 6. 署名与贡献记录

项目组：周航正、霍奕茗、于跃、叶安、王健祺

| 姓名 | 角色 | 主要文件/功能 | 日期 |
|---|---|---|---|
| 王健祺 | 模块负责人 | 任务定义、算法选型、验收口径与结论把关 | 2026-09-02 |
| ZCode (AI) | 协助 | spsa/bayes/qnewton 实现、双层MOP/MOE扩展、三模块面板与文档整理 | 2026-09-02 |

审核：待项目组审核。AI仅列为协助工具，需求提出、技术判断与最终责任归项目成员。

## 7. 与前序任务的关系

- 场景/风模型/三模块面板 = 任务5口径(未改动)；
- unified_search(任务1+2) 的 ea_multistart/multistart 等继续保留横评；
- 风参数全0 即退化回任务1+2静态口径(全部向后兼容)。
