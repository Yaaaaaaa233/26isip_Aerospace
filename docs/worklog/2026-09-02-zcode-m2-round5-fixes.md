# Worklog：M2 第五轮复验修复——状态契约边界与证据绑定（ZCode，2026-09-02）

项目组：周航正、霍奕茗、于跃、叶安、王健祺
记录人：叶安（委托执行）、ZCode（执行与成文）
性质：只增不改的执行记录；对应第五轮复验报告 `docs/evidence/M2_REACCEPT_ROUND5_CODEX_20260902.md`（R5-F1/F2/F3 与 §7 关闭条件）

## 修复

1. **R5-F1（中）isfinite 过滤把 NaN/Inf 调用者状态悄悄降级为空**：四处入口快照条件去掉 isfinite（exactly-as-found），恢复校验改 isequaln；新增 `contract` 段：4 入口 × {有限,空,NaN,Inf} × {成功/正常返回, 错误出口} 直接测试（未覆盖组合显式声明：非有限态的完整成功/链成功/report 返回，机制同源已由有限态覆盖）。
2. **R5-F2（高）report 可复用旧/混批 stage 证据假绿**：新增 `init` 段（清目录 + manifest：UUID runId + git 提交 + 验证器 SHA-256 + 各段声明行数）；每段输出带 runId 列 + done.mat（runId+gitCommit）；`report` 先 `validateStaged` 逐文件校验再聚合，旧批次/缺段/混提交硬失败；contract 段在玩具副本上对三类场景做负向证明（真实 staged 目录不动）。
3. **R5-F3（低）归档路径断言依赖巧合字面量**：改为完整 `'archive injected'` 断言 + 无路径消息负向证明。
4. 规则升 **v1.2**（§2.4 manifest 绑定、§3.5 非有限契约、§6 自检清单 +2 项）；全局量注册表 `M2_ETA_APPLIED` 契约同步。

## 过程记录

- 批量 python 补丁多次因 bash heredoc 转义（`\n` 折叠/三引号）半途失败——按原子性设计（断言失败即不写入）没有产生半改状态，改为 Write 工具落补丁文件执行；两处 fprintf 的 `\n` 转义漏网由 checkcode 当场抓出修正。
- 分段序列含每段一次重试额度（上一轮的经验：本机 R2022b 偶发进程退出期堆损坏，工作已完成但 rc=127）。

## 验证

39 行针对性矩阵（每行带 runId）+ 每段非空调用者恢复断言；结果回填 `docs/evidence/M2_REACCEPT_ROUND5_FIX_20260902.md` §3。
