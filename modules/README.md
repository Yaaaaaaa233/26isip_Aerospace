# 模块登记表

版本：1.0
日期：2026-09-02

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：周航正
主要撰写：Codex
技术贡献：项目组现有模块负责人（各模块实现、验收和结论以模块 README 为准）
审核：待项目组审核
AI协助：Codex（模块盘点、分类和入口整理）

本文件是模块名称、用途、生命周期、运行入口和证据位置的权威登记表。这里的“已验证”只表示在模块 README 说明的代理对象和测试场景内通过，不代表实机结论。

## 核心在线算法

| 模块 | 状态 | 主要入口 | 证据 | 负责人登记 |
|---|---|---|---|---|
| [`ratio_esc`](ratio_esc/) | 代理对象已验证 | `START_HERE.m`、`run_acceptance.m` | [`docs/evidence/acceptance-report.md`](../docs/evidence/acceptance-report.md) | 待项目组确认 |
| [`speed_esc`](speed_esc/) | 代理对象已验证；速度定位并非全场景通过 | `START_HERE.m`、`run_speed_acceptance.m` | [`docs/evidence/speed_esc/`](../docs/evidence/speed_esc/) | 待项目组确认 |

## 搜索与场景研究

| 模块 | 状态 | 主要入口 | 证据 | 负责人登记 |
|---|---|---|---|---|
| [`speed_shift_search`](speed_shift_search/) | 任务1代理验收通过 | `START_HERE.m`、`run_task1_acceptance.m` | [`docs/evidence/speed_shift_search/`](../docs/evidence/speed_shift_search/) | 待项目组确认 |
| [`speed_rugged_search`](speed_rugged_search/) | 任务2代理验收通过 | `START_HERE.m`、`run_task2_acceptance.m` | [`docs/evidence/speed_rugged_search/`](../docs/evidence/speed_rugged_search/) | 待项目组确认 |
| [`wind_circle_search`](wind_circle_search/) | 任务3曲线平移代理验收通过 | `START_HERE.m`、`run_task3_acceptance.m` | [`docs/evidence/wind_circle_search/`](../docs/evidence/wind_circle_search/) | 待项目组确认 |
| [`sin_wind_search`](sin_wind_search/) | 任务4曲线平移代理验收通过 | `START_HERE.m`、`run_task4_modules_acceptance.m` | [`docs/evidence/sin_wind_search/`](../docs/evidence/sin_wind_search/) | 待项目组确认 |
| [`ortho_wind_search`](ortho_wind_search/) | 任务5曲线平移代理验收通过 | `START_HERE.m`、`run_task5_modules_acceptance.m` | [`docs/evidence/ortho_wind_search/`](../docs/evidence/ortho_wind_search/) | 待项目组确认 |
| [`adaptive_search`](adaptive_search/) | 任务6代理验收通过 | `START_HERE.m`、`run_task6_acceptance.m` | [`docs/evidence/adaptive_search/`](../docs/evidence/adaptive_search/) | 王健祺 |
| [`wind_field_sched`](wind_field_sched/) | 空速物理代理验收通过 | `START_HERE.m`、`run_wind_acceptance.m` | [`docs/evidence/wind_field_sched/`](../docs/evidence/wind_field_sched/) | 王健祺 |
| [`unified_search`](unified_search/) | 任务1+2组合代理验收通过 | `START_HERE.m`、`run_unified_acceptance.m` | [`docs/evidence/unified_search/`](../docs/evidence/unified_search/) | 待项目组确认 |

`wind_circle_search`、`sin_wind_search` 和 `ortho_wind_search` 使用风致功率曲线平移代理；`wind_field_sched` 才是当前路线中空速矢量关系、解析调度和信息结构的物理代理实现。两类结果不能直接混称。

## 强化学习预研

| 模块 | 状态 | 主要入口 | 证据 | 负责人登记 |
|---|---|---|---|---|
| [`speed_rl_residual`](speed_rl_residual/) | MATLAB 残差接口与候选策略预研 | `START_HERE.m`、`run_checks.m` | [`docs/evidence/speed_rl_residual/`](../docs/evidence/speed_rl_residual/) | 待项目组确认 |
| [`speed_rl_pytorch`](speed_rl_pytorch/) | Python 对拍、TD3/BC 训练与未见种子评估完成一轮 | `parity_check.py`、`evaluate.py` | [`docs/evidence/speed_rl_pytorch/`](../docs/evidence/speed_rl_pytorch/) | 待项目组确认 |

这两项尚未接入统一 Plane/PX4 闭环，不支持“RL 已优于 ESC”或真实飞行结论。

## 平台、评价与接入

| 目录 | 状态 | 作用 | 负责人登记 |
|---|---|---|---|
| [`../models/px4_x8`](../models/px4_x8/) | M2 已放行，下一步 M3 | Control、X8 分配、6DOF、日志和安全回退 | 叶安 |
| [`../harness`](../harness/) | 代理指标层可运行 | 场景、MOP/MOE与公平横评；统一WPC接入未完成 | 待项目组确认 |
| [`../integration/air_esc`](../integration/air_esc/) | 预留 | 算法、Plane与Control适配 | 待项目组确认 |
| `../models/plane` | 路线已定义，目录尚未创建 | P0--P4统一Plane物理对象 | 建议霍奕茗，待组内确认 |

## 登记规则

新增模块时必须同时提供：

1. 模块 README，说明问题、对象、入口、验收、局限和署名；
2. 至少一个机器可执行的测试或验收入口；
3. 在本表登记分类、状态和证据位置；
4. 在 `docs/worklog/` 记录本次新增；
5. 只有项目状态或可引用结论改变时，才更新 `docs/DEVELOPMENT_STATUS.md`。

模块目录暂不按分类移动。MATLAB 包路径、相对链接和既有证据依赖较多，当前先通过登记表完成逻辑分层；以后只有在重复代码已经造成维护问题且具备完整回归时，才讨论物理迁移或公共库抽取。
