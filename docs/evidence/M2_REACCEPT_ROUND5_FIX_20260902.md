# M2 第五轮复验问题修复与关闭验证（ZCode，2026-09-02）

结论：**第五轮复验问题 R5-F1 / R5-F2 / R5-F3 全部修复，第五轮报告 §7 关闭条件 1--5 逐条验证通过（针对性矩阵 39/39，manifest 绑定 + 三类负向证明 + 非有限四态契约）。**M2 核心成果维持放行（第五轮报告 §1/§7）；总验证器作为放行门的前置缺陷关闭。执行对象：[`M2_REACCEPT_ROUND5_CODEX_20260902.md`](M2_REACCEPT_ROUND5_CODEX_20260902.md)。

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：叶安
主要撰写：叶安（修复方案与关闭判定）、ZCode（契约/manifest 实现、分段验证执行与本文档代拟）
审核：待项目组审核、待指导教师确认
AI协助：ZCode（快照契约修复、manifest 机制、负向证明与本文档代拟）

## 1. 修复内容（第五轮报告 §6）

| 项 | 修复 |
|---|---|
| R5-F1（中）isfinite 过滤 | 四处入口（单元测试/试验/链/验证器）的快照条件去掉 `isfinite`——快照**exactly-as-found**，NaN/Inf 原值恢复；恢复校验改 `isequaln`；新增 `contract` 段对 4 入口 × {有限, 空, NaN, Inf} × {成功/正常返回, 错误出口} 直接测试（规则 v1.2 §3.5，注册表同步） |
| R5-F2（高）report 无新鲜度 | 新增 `init` 段：清空 staged 目录并生成 manifest（UUID run ID + `git rev-parse HEAD` + 验证器自身 SHA-256 + 各段声明行数）；每个段输出 CSV 增加 `runId` 列并写 `<stage>.done.mat`（runId + gitCommit + 完成时间）；`report` 先 `validateStaged`（manifest 存在、每段 CSV/Done 齐全、每行 runId 与 manifest 一致、done.mat 的 runId 与 git 提交一致、行数=声明）再聚合，任何旧批次/缺段/混提交证据硬失败 `air:M2Verify:StaleEvidence`；**三类负向证明**（旧批次 runId、删除 done、伪造提交）在玩具副本上实际执行 |
| R5-F3（低）巧合字面量 | C2 trials 断言改为完整 `'archive injected'`（消息必须携带归档字段+确定值），并加"消息缺路径必须失败"负向证明 |

## 2. 验证覆盖范围（针对性矩阵，39 行，每行带 runId）

| 段 | 行数 | 覆盖 |
|---|---:|---|
| c1c2stale | 6 | C1a clean、C1b stale + persistent 前向直探 + 灵敏度自检、C2 三出口 × stale |
| c2clean | 3 | C2 三出口 × clean |
| c3 | 2 | 试验独立受控失败 + 完整成功（stale 哨兵） |
| c5 | 4 | 脏会话双链 2/2、同会话哈希互等、门槛抖动容差 |
| contract | 24 | 单元入口 4 态 ×（成功+错误）；试验入口 4 态 × 正常返回；链入口 4 态 × 错误出口；验证器入口 4 态 × 错误出口；R5-F3 负向；manifest 三类负向 |

**明确未覆盖**（边界声明）：试验完整成功、链完整成功、验证器 report 正常返回在**非有限**调用者态的组合（错误出口四态已全测；正常返回的恢复机制是同一处函数帧 onCleanup，有限态版本由 c3/c5/report 覆盖）。段级声明行数写入 manifest（`declaredRows`），聚合断言 39 行与实际一致。

## 3. 关闭条件验证（第五轮报告 §7）

分段编排：`init → c1c2stale → c2clean → c3 → c5 → contract → report`，每段独立 MATLAB 进程 + 非空调用者哨兵 `{esc,0.8123,tag}`/`0.8123456789` 驱动，段后断言调用者状态逐域恢复。

| 条件 | 验证 | 结果 |
|---|---|---|
| 1 四入口统一快照语义，有限/空/NaN/±Inf × 成功与错误出口直接测试 | contract 段 20 行状态契约（单元双出口 ×4 态；试验/链/验证器 ×4 态各至少一出口）+ c3/c5/report 提供有限态正常返回；聚合 `results/round4_closure/20260902_140840/` | **PASS** |
| 2 manifest 同批次绑定，旧文件/缺段/混提交三类负向硬失败 | init 生成 manifest（runId `d2a9702e-…`，git 提交 `e2bdf3e`）；report validateStaged 逐文件校验；contract 段三类玩具副本负向证明均触发拒绝 | **PASS** |
| 3 C2 trials 真实路径检查 + 消息缺路径负向证明 | `'archive injected'` 完整断言（c1c2stale/c2clean 两段的 trials 行）+ 无路径消息负向（contract 段） | **PASS** |
| 4 重跑标准矩阵（39 行超集），双链 2/2、哈希一致、±0.015pp | c1c2stale 6 + c2clean 3 + c3 2 + c5 4 + contract 24 = 39/39；C5 双链 2/2、同会话哈希互等、门槛值在容差内 | **PASS** |
| 5 六处文档一致 | DEVELOPMENT_STATUS/路线/README/AGENTS/接口文档/模型 README 统一为五轮关闭口径 | 提交 diff |

全段（init/c1c2stale/c2clean/c3/c5/contract/report）以非空调用者哨兵进入、段后逐域恢复（`COND1B_PASS` ×7）。**39/39 PASS。**

执行记录（如实）：contract 段初版两处顺序/数据缺陷被驱动当场抓出——① 负向克隆在生成自己的 CSV 之前执行（克隆排除 contract 段并同步裁剪玩具 manifest 修复）；② 状态名 `NaN`/`Inf` 被 readtable 推断为数值列导致行丢失（改文本安全名 `NaNval`/`Infval` 修复）；report 聚合器两处变量引用错误（c5.mat 未展开、manifest 存错变量名）。均由 staged 驱动的断言发现、当场修复、全段重跑验证；contract 一次"通过后崩溃于退出期"（本机 R2022b 已知抖动，工作已落盘），重试干净通过。

## 4. 复盘

- R5-F1 是我第三次在"边界值"上翻车（骑线门槛→措辞边界→非有限值）：`isfinite` 过滤当初是为防垃圾值写的"防御"，实际成了未声明的隐式契约。规则 v1.2 把"快照=exactly-as-found，四态直接测试"写死。
- R5-F2 的本质是**证据与来源解绑**：分段模式的文件接力没有批次身份，任何旧文件都能冒充本轮证据。manifest 是最小修复（报告建议方案），三类负向证明保证校验器本身不是永真。
- 五轮的问题轨迹（协议→状态管理→脚本语义→工具自身合规→契约边界与证据绑定）说明：每轮修复引入的新基础设施自身就是下一轮的审查对象，验收基础设施的改动应当默认假设会被同强度复验。
