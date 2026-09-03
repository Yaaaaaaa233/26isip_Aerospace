# 2026-09-03 修正WPC技术路线与接口

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：周航正
本次贡献：周航正（梳理Environment-无人机-算法接口草图，提出功率图已知性、在线寻优对象和RL位置问题）
审核：待项目组审核、待指导教师确认
AI协助：Codex（GitHub现状复核、问题收敛、接口与路线文档修订）

## 本次做了什么

- 对照最新仓库，确认 `speed_esc` 的黑箱未知曲线假设与 `wind_field_sched` 的已知名义曲线假设尚未统一。
- 新增ADR-003，将 `P_nom`、`P_hidden` 和 `P_meas` 分层，并规定四类策略的信息可见范围。
- 修正用户接口草图：Scenario输出路径，Environment输出风，Plane输出实际航向/地速/空速/功率，Control输出参考。
- 将公共接口升级为0.3建议版，新增PathCommand与MeasuredContext，并明确 `v_ref` 是沿轨迹切向地速参考。
- 在执行路线中拆分算法、Plane、Environment和集成工作包，增加R0-R5汇合门槛。
- 明确RL位于Control慢层策略插槽，以残差修正 `v_base`，继续受ADR-002准入约束。

## 关键决策与理由

- 无风仿真功率图可以已知，但只能代表公开名义模型；在线意义来自运行对象偏差、因果风信息、执行动态和双变量耦合。
- 真风解析策略是Oracle评价上界；正式在线策略只能使用当前/历史测量。
- Environment不计算空速和功率，避免风场模块与Plane各自维护一套物理公式。
- 实际地速不能由慢层直接设定；慢层输出 `v_ref`，快层和Plane产生实际响应。

## 遗留问题 / 风险

- ADR-001与ADR-003仍待组内和老师确认，接口0.3尚未冻结为1.0。
- `wind_field_sched` 当前使用局部 `u=v*t+w` 约定，接公共接口时需要把局部量重命名/换号并补契约测试。
- 统一Plane、PathCommand、WindMeasurement、MeasurementAdapter和WPC Harness尚未实现。
- 当前所有功率优化证据仍是代理或未校准估算，不能支持真实X8节能结论。

## 下一步

- 先完成R0评审，然后三条开发线同时针对接口0.3提供Mock和契约测试。
- Plane线优先交付最小 `reset/step`、空地速符号测试和名义/隐藏功率对象。
- Environment线优先交付PathCommand、统一NE风与风测量退化；算法线先适配固定/名义调度/ESC。
- 三者在R2/R3汇合后再做M3；R0-R4完成后才复审RL训练。

## 验收状态

- `tools/check_repo_governance.ps1`：通过。
- `git diff --check`：通过。
- MATLAB/Simulink验收：未运行；本次只修改架构、接口、路线与状态文档。
