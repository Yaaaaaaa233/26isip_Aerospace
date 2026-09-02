# 2026-09-03 ZCode：M2 第九轮发现修复（R9-F1 manifest 合同 / R9-F2 日志编码）

## 做了什么

- 评估并逐项核实第九轮验收报告（`M2_REACCEPT_ROUND9_CODEX_20260903.md`）：48/48 数据、双链哈希、marker 探针恢复、乱码计数全部属实；R9-F1（manifest 协同篡改，P1）在代码层面确认——`validateStaged` 第 874 行只断言 `maxAttempts>=1`、按 staged manifest 自身迭代 stages/declaredRows，源码固定合同从不参与 report 校验。
- `951d7a3`（R9-F1）：验证器新增 `expectedManifestContract()` 单一合同源 + `assertManifestContract()`（上限等值、阶段名单/数量/顺序/唯一全等、声明行数逐字段全等，错误 ID `air:M2Verify:ManifestContract`）；init 从合同写入，段入口/`validateStaged`/`writeAggregate` 三处等值断言；`runContract` 新增 manbound/manstagecut/manstageadd/manrows 四行负向（man* 必须在合同检查本身报错），矩阵 48→52；`cloneStaged` 改为合成完整五段一致 toy（含合成 contract.csv/done/marker），否则新增言断言会把既有 11 个篡改负向全部短路成"在合同检查处抛错"的空转证明。顺带修正文件头陈旧的 42/27 计数（R8 漏更新）。
- `2c3c6c3`（R9-F2）：驱动新增 `Invoke-LoggedNative`——显式按系统 ANSI 代码页解码原生命令输出、写 UTF-8 日志、恢复控制台编码；驱动测试增至 9 场景（S8：ANSI 页 CJK 字节经 `cmd /c type` 走同一捕获路径，断言含原文且零 U+FFFD）。
- `3d3fa51`：规则文档升 v1.6（规则 8 manifest 是证据不是权威 + 四类协同篡改负向；规则 9 日志编码无损 + 跨机器原始字节探针复核；§6 清单两条）。
- 正式批次（`3d3fa51`，入库驱动）：**52/52 PASS**，runId `78281368-0a5f-449f-82ce-26827f44924f`，批次日志 `results/batch_runs/20260903_004644/`，归档 `results/round4_closure/20260903_011133/`；门槛值与登记值 12 位小数逐位一致；双链 SHA-256 第 7 次跨批复现；8 份日志零 U+FFFD。
- 证据 `M2_REACCEPT_ROUND9_FIX_20260903.md` + 本 worklog + 四处状态同步（DEVELOPMENT_STATUS、models/px4_x8/README、M2_ETA_ALLOCATOR、evidence/README）。

## 关键决策与发现

- **编码探针三轮才拿到地基数据**：第一轮脚本字面量含中文路径，被 PS 5.1 按 ANSI 误读（实证同根坑），三臂结论出现"UTF-8 臂干净"的假象；第三轮改为 MATLAB 内部 `char()` 造中文 + `cmd /c` 重定向取**原始字节**——MATLAB -batch 管道输出是 GBK（ANSI 页），按 ANSI 页解码完美往返（含本地化"警告"标签），按 UTF-8 解码才是 U+FFFD 之源。修复方向因此是"按实际输出页解码、写 UTF-8"，与直觉相反。
- **cloneStaged 短路陷阱**：合同等值断言若配"裁剪成 4 阶段的 toy manifest"，所有既有负向证明都会在合同检查处抛错而各自篡改原因永不执行——负向证明空转。合成第五段（fabricateContractStage）是本次修复正确性的关键配套。
- **正式批次自然发生崩溃—重试—成功**：c2clean 第 1 次尝试 `0xC0000374` 堆损坏、零证据产出，驱动按 v1.5(a) 完整重执行，第 2 次成功，`done.attempts=2` 如实入档——R8 登记遗留项"正式批次内自然崩溃—重试—成功组合"（此前只有受控击杀代理）关闭。
- 第九轮报告 §7 第 6 条（done stamp 内嵌合同摘要）**未采用**：摘要复算同样依赖 staged manifest 字段，等值断言才是根；已作为实施方取舍写入证据文档待验收方复核。
- 拒绝探针双备份设计：原始证据与重绑基线分离，避免把伪造绑定的基线留在 staged 冒充原始证据（首版设计的自查发现）。

## 遗留（非阻塞）

- report 段（归档写入路径）的崩溃注入未执行；全量 9 场景同会话双链仍为环境限制未覆盖组合。
- MATLAB 输出编码属机器/区域设置：跨机器复跑按规则 v1.6 第 9 条以原始字节探针复核（本机 ANSI=cp936）。
- pwsh 7 本机不可用，驱动测试仅 WinPS 5.1 单 shell 验证（延续 R8 记录）。
- 验证器文件头的矩阵计数曾有 R8 漏更新（42/27），本轮修正为 52/37；后续扩行时同步头声明。

## 验收状态

R9-F1/R9-F2 修复并关闭；R8-F1 随之完全关闭；52/52 @ `3d3fa51`；规则 v1.6。等待下一轮独立复验（建议按第九轮报告 §8 清单 + v1.6 两条新自检项）。
