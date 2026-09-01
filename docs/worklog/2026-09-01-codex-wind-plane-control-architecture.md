# Wind-Plane-Control架构与问题定义

日期：2026-09-01
执行者：Codex（依据周航正提出的架构任务）

## 本次完成

- 新增项目问题定义，区分最长续航、固定航程能量和最大航程 `P/v` 三种口径。
- 提议以“固定高度圆周盘旋等待下的在线平均功率最小化”为最终主任务，状态保持待指导教师确认。
- 定义直线/圆周、无风/规则风/不规则风的递进场景和公平配对原则。
- 建立Wind、Plane、Control和Evaluation逻辑边界、运行顺序、回退状态及仓库映射。
- 建立 `ScenarioConfig`、`WindSample`、`PlaneState`、`ControlCommand` 和 `EvaluationRecord` 接口字典。
- 建立需求-MoE-MoP-信号-场景-证据等级追溯矩阵。
- 新增两项ADR：目标选择待教师确认；正式RL开发暂缓并设置九项准入门槛。

## 结论边界

- 本次只新增架构与决策文档，没有修改MATLAB、Simulink模型或既有验收结果。
- 盘旋等待主任务是建议方案，不表述为教师已确认。
- RL暂缓不等于删除现有预研模块；其接口、测试和负结果继续保留。
- 平台执行顺序不变，下一阶段仍为M2上下桨转速比和受约束X8分配器。

## 后续入口

1. 与指导教师逐项确认 `docs/decisions/ADR-001-objective-selection.md` 的五项选择。
2. 根据确认结果将接口字典从0.1冻结到1.0。
3. 由各工作包使用Mock并行实现Wind、Plane、Control、Data和Harness适配器。
4. 通过Gate A后再建立顶层 `run_wpc_scenario` 可运行骨架。
