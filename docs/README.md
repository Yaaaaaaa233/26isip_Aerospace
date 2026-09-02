# 项目文档导航与权威关系

版本：1.0
日期：2026-09-02

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：周航正
主要撰写：Codex
技术贡献：周航正（提出项目结构与治理方式整理需求）
审核：待项目组审核
AI协助：Codex（仓库审查、结构设计和成文）

## 先看哪几份

| 场景 | 先读 | 原因 |
|---|---|---|
| 第一次进入仓库 | 根目录 [`README.md`](../README.md) → [`DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) | 先知道项目是什么，再看当前状态 |
| 准备领取任务 | [`PROJECT_EXECUTION_ROADMAP.md`](PROJECT_EXECUTION_ROADMAP.md) → [`../modules/README.md`](../modules/README.md) | 确认阶段依赖、模块入口和负责人 |
| 修改公共接口 | [`architecture/04_interface_dictionary.md`](architecture/04_interface_dictionary.md) → 对应 `interfaces/M*.md` | 先遵守跨组件字段，再看阶段接线 |
| 修改算法或对象 | [`COLLABORATION.md`](COLLABORATION.md) → 模块 README | 确认因果边界、API和验收入口 |
| 准备引用结果 | [`DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) → `evidence/` | 状态页给结论边界，证据目录给事实依据 |

## 权威来源

| 信息类型 | 权威文档 | 其他文档怎样使用 |
|---|---|---|
| 项目目标、系统边界和成功条件 | [`architecture/01_problem_definition.md`](architecture/01_problem_definition.md) | 路线图引用，不重复定义另一套目标 |
| 重大技术决策 | [`decisions/`](decisions/) 中的 ADR | 已接受 ADR 保留历史；变化时追加复审或新 ADR |
| Wind-Plane-Control 公共字段 | [`architecture/04_interface_dictionary.md`](architecture/04_interface_dictionary.md) | `COLLABORATION` 解释用法，阶段接口只能细化映射 |
| 项目阶段、依赖和放行门槛 | [`PROJECT_EXECUTION_ROADMAP.md`](PROJECT_EXECUTION_ROADMAP.md) | 状态页报告进展，不另立阶段顺序 |
| 当前完成情况、局限和近期优先级 | [`DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) | README 和 AGENTS 只链接，不复制动态清单 |
| 某阶段的模型接线与验收协议 | [`interfaces/`](interfaces/) 中对应的 `M*.md` | 不能覆盖公共接口语义或路线图阶段目标 |
| 算法适配方式与因果边界 | [`COLLABORATION.md`](COLLABORATION.md) | 不承担当前进度和跨组件字段的权威定义 |
| 模块清单、分类、入口和生命周期 | [`../modules/README.md`](../modules/README.md) | 根 README 和 AGENTS 不维护模块计数 |
| 已核验数值和结论证据 | [`evidence/`](evidence/) | worklog 不作为最终结论依据 |
| 会话交接和历史过程 | [`worklog/`](worklog/) | 只追加，不替代当前状态 |

## 目录说明

```text
architecture/  稳定的问题、场景、组件、接口和追溯结构
decisions/     架构决策记录；保留当时背景和理由
interfaces/    平台阶段的冻结接口、接线和验收协议
evidence/      精选且可追溯的验收报告、CSV和图表
worklog/       按日期追加的协作交接记录
archive/       未来用于存放不再代表当前状态的历史盘点
```

根目录下的治理文件暂不搬动，避免打断已有链接。通过本索引完成逻辑分层即可。

## 什么时候更新什么

| 发生的事情 | 必须更新 |
|---|---|
| 新增、合并、冻结或废弃模块 | 模块 README、[`../modules/README.md`](../modules/README.md)、worklog；若影响结论再更新状态页 |
| 阶段开始、通过或退回 | 路线图、开发状态、阶段接口、证据、worklog |
| 公共字段或语义改变 | 接口字典、受影响阶段接口、适配器测试；必要时新增 ADR |
| 目标函数或主场景改变 | 问题定义、ADR、路线图、追溯文档 |
| 一般实现或排错会话 | 模块 README（确有变化时）和 worklog；不要求机械修改状态页 |

## 文档状态词

- `建议/Proposed`：尚未确认，可以讨论，不能作为放行依据。
- `已接受/Accepted`：决策有效，但背景描述保留当时状态。
- `实施中`：已有执行基线，尚未通过全部门槛。
- `已验证/Validated`：在文档注明的对象、场景和证据范围内通过。
- `历史/Archived`：只用于回溯，不能代表当前状态。

任何“已完成”“已验证”“优于”等表述必须能链接到 `evidence/` 中的证据，并同时写清代理、校准仿真、SITL/回放或实测等级。
