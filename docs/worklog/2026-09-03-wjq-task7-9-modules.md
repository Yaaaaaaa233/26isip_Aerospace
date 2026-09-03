# 2026-09-03 王健祺：task7-9 三模块并入（实际约束重评估 / 曲线case标定 / 风场模型库）

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：王健祺
本次贡献：王健祺（三模块实现、验收与诊断实验；本地工作名 task7_realistic_constraints / task8_curve_cases / task9_wind_models）
审核：待项目组审核
AI协助：ZCode（对象与面板实现、测试验收脚本、诊断与消融实验）

## 本次做了什么

- 并入三个算法线模块（对象侧升级均不改控制器因果接口，红线1/2）：
  - `modules/realistic_constraints_search`：四项实际约束（转弯半径 50-150 m 物理化 ψ'=v/R、通信时延 FIFO、加速度限幅 2 m/s²、开环固定基线）+ 九策略横比 + settled_q 就位包装器 + gtrack/est/known 策略；18 测试、9 门槛全绿。
  - `modules/curve_case_calibration`：DJI Mavic Pro 参考曲线重标定（悬停 103.7 W、谷底 6.3 m/s、P(20)=134.5 W）+ 三 case（谷底=悬停的 95/90/85%）+ case 下拉与运行前三曲线预览；11 测试、5 门槛全绿。
  - `modules/wind_model_library`：七种可选风场模型库（恒定/双正弦/软边方波/三角/OU湍流/复合(推荐缺省)/扇区）+ 选中即预览 + 空速-地速语义显式化（空速=|地速矢量+风矢量|，日志新增 airspeed/windX/windY 评价列）+ 时延下限放宽至 0；18 测试、5 门槛全绿。
- 证据入库 `docs/evidence/{realistic_constraints_search,curve_case_calibration,wind_model_library}/`（本地 results 为可复现仿真输出，按 .gitignore 口径不入库）。
- 三模块 README 顶部均按项目组要求加入**有效性警示**（见下），并在模块登记表、状态页与证据索引登记，负责人王健祺。

## ⚠️ 特别标注：这部分不一定对后续工作有效

用户（王健祺）明确要求特别标注：**本批模块的方法、参数与结论不一定对后续工作有效或可复用**，原因是调试期间出现了多类问题（est 估计器发散并多次结构性返工、gtrack 交替计数缺陷、oracle 句柄快照缺陷——均已修复，但最终因果策略仍未逼近理论最优）。核心负结果：

- 真实约束口径（R=50-150 m、空速物理）下**无因果在线策略胜过开环固定基线**（开环超额约 5.2-5.6%，known oracle 0.05-0.4%）；τ=0 与 τ=0.3 几乎相同——**时延不是瓶颈，风信息缺失才是**。
- 消融归因（task6 对象 vs task9 对象，同种子同风参数）：MOE 下降主因是风→最优值摆幅从 ±0.5 m/s（task6 平移代理 windDxGain=0.12）放大到 ±3-4 m/s（空速物理 1:1），约 +4-5pp；相位节奏次之（约 +2.6pp）；执行动态可忽略（约 +0.15pp）。
- 后续工作**不应默认继承**本批模块的参数、门槛与结论；已知风 oracle 证明物理上可逼近（0.2-0.4%），改进方向（相位查表 / 风感知前馈，即"工作包2"）**尚未实现，等组内确认后再动**。

## 关键决策与理由

- 三模块以功能名入库（保留内部 +w7/+w8/+w9 包与本地 taskN 文件名可追溯性，README 标注对应关系）。
- task9 的扇区风（风随航向周期变化）与"相位查表"改进方向天然配套：扇区风下 qnewton 是唯一明显胜过开环的策略（4.65-5.92% vs 4.86-6.70%）。
- 三模块沿用局部"加号风约定"（u=|v·t̂+w|）；2026-09-03 接口字典 0.3 已统一为 `v_air=v_ground-wind`，接入统一 Environment/Plane 前必须先做 w→−w 约定适配（README 警示第4条）。

## 遗留问题 / 风险

- 有效性警示覆盖的负结果：现有因果策略库（含 est/gtrack）在真实量级风摆下不达标。
- 加号约定适配（与 `wind_field_sched` 同一批事项，见状态页 9月3日接口修订）。
- 曲线标定为 DJI 文献代理，与 X8 机型不符；风场参数为文献典型值，未实测校准。

## 下一步

- 等组内确认后再实施"工作包2"（相位查表 / 风感知前馈 / ESC 解调相位补偿），目标是把因果策略从 ~5.6% 超额逼近 oracle 的 0.2-0.4% 量级。
- 与 Environment 线（王健祺场景资产）的 PathCommand/WindTruth/WindMeasurement 拆分对接。

## 验收状态

- realistic_constraints_search：tests_task7 18/18、run_task7_acceptance 9/9（本地复跑通过）
- curve_case_calibration：tests_task8、run_task8_checks 5/5（本地复跑通过）
- wind_model_library：tests_task9 18/18、run_task9_checks 5/5（本地复跑通过）
- 全部为 proxy 等级代理口径，不支持真实 X8 节能表述（红线3）。
