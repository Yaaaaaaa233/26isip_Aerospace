# 2026-09-07 王健祺：风场预设修复 + 任务2.1/3.1/3.2算法集精简 + 全版本梳理文档

负责人：王健祺 ｜ AI协助：ZCode ｜ 状态：已完成并回归全绿

## 本轮做了什么

### 1. 修复"七种风场里除恒定风/复合风外都无法加载"的问题（2.1/3.1/3.2 demo）

- **根因**：三个 demo 的风幅值默认 A=C=0（建 2.1 时为配合"恒定风3.5主口径"修改；
  1.10 原版是 A=2.0/C=1.5）。sin/square/triangle/sector 的风 = 幅值×波形 + 偏置，
  幅值为零全部退化为恒定偏置；turb 的湍流强度取自 windAmp，同样退化；composite 因
  turbStd 默认 0.3 独立于幅值而"看起来正常"。
- **修复**：demo 新增 `windKindChanged`/`applyWindPreset`——切换风场即自动载入该模型
  推荐参数（与 1.10 风场库 / 3×3 表口径一致；composite 用 A=1.5/B=2.5/σ=0.3），载入后
  即时预览，用户仍可手改；A/C 标签补充 "turb=σx/σy" 提示。
- **对象侧顺带修正**：turb 族湍流 y 向强度此前被静默忽略（恒用 σx=windAmp），
  三个文件夹 `scenario.m` 同步改为 σx=windAmp、σy=windAmpY（既有单测不受影响）。
- **形状核验**：七种风场×推荐参数，除 const（设计即恒定）外 std 全部非零，
  turb σy≈1.45（设定 1.5）——三个文件夹全过。

### 2. 算法集精简（task2/task3 删除 task1 遗留算法）

删除 tracker/esc/spsa/bayes/qnewton/gtrack 六个直接搜索器及其私有助手
（brent_search/search_query/gp_posterior），共 9 文件 × 3 模块。理由：它们不建模风/
曲线未知，谷底二阶信息+1%噪声下样本效率低（3.1 实测 qnewton 恒定风 6.12% vs
openloop 6.40%，几乎无增益），且干扰"风推断/曲线未知"的主线叙事。

精简后策略集：

- 2.1：windinfer（主角）/ openloop（基线）/ est（模型法对照）/ known（oracle上限）
- 3.1：sweepcal（主角）/ rl（对照）/ openloop / windinfer、est（oracle参照）/ known
- 3.2：purerl（主角）/ sweepcal、rl（对照，需150步）/ openloop / windinfer、est / known

配套：`run_algorithm` 调度器、demo 下拉、tests（策略清单与 qnewton 引用改 openloop）、
checks/smoke 策略矩阵、compare_baseline 白名单同步；config.m 删除 51 个死参数
（t1*/probe*/slope*/esc*/spsa*/bayes*/qn*/gt*/T/tol/maxSearchEval）及其断言。

### 3. 全版本梳理文档

新增 `docs/VERSION_REVIEW_20260907_wjq.md`（本地为 speed_esc_matlab/模型与算法梳理.md）：
三轮主线信息量梯度、1.1–1.9 前情提要、1.10/1.11/2.1/3.1/3.2 逐版详述
（模型设定/模型理解/算法细节/效果/问题分析/改进点）、"问题→改进→效果"速查表、
横向对比表。供分析每版问题与改进点作用时使用。

## 回归结果（2026-09-07 复跑）

| 模块 | 单元测试 | 检查门槛 | 主角策略关键数字（精简前后一致） |
|---|---|---|---|
| wind_inference_search (2.1) | 27/27 | 8/8 | 恒定风 windinfer MOE 0.9949（超额0.52%，风误差0.09 m/s） |
| curve_unknown_search (3.1) | 33/33 | 8/8 | 恒定风 sweepcal 1.91%（û*误差0.11）；变风 rl 3.52% |
| reward_only_rl (3.2) | 37/37 | 9/9 | 恒定风 purerl 3.63% vs 开环 6.40%；变风 3.51% vs 4.72% |

证据已刷新：`docs/evidence/<module>/{report.md, main_comparison.csv, wind_kinds_smoke.csv, table_3x3.md}`。

## 结论边界

全部结果为虚拟/代理对象口径（红线3），不支持真实 X8 节能表述；known 为非因果
oracle 参照；windinfer/est 在 3.x 中为已知曲线 oracle 参照。

## 下一步

- `policy.reset/step` 慢层适配器：把 sweepcal/pure_rl 接入 SIM_ALGO_INTERFACE v0.1
  的统一 harness 闭环（接口占位已在 interfaces/ 定义）。
