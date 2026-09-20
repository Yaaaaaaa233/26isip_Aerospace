# worklog 2026-09-21：ZCode（叶安）——Q1 估计器敏感性批执行

对应方案：[`QUAD_MIGRATION_PLAN_20260921.md`](../QUAD_MIGRATION_PLAN_20260921.md) §4-Q1 / §5-M1·M5。
上游：同日 stage0（Q0 立项，commit dd9ff2a）。下游：Q2（四旋翼对象）按方案继续。

## 做了什么

1. **模块落地** `modules/platform_link_39/`（D4 命名，Q3 的估计链接入位）：
   - `+q39/est_l0.m` / `n_of_pwm.m` / `p_coef.m`：L0 静态台架估计器（P̂=Σ P_bench(n̂(pwm),V̂)，
     不含 H3/H5/H4/aux/动态；正向式 = `plane.step` L128 的 PWM 派生式的逆）；
   - `+q39/make_platform_plant_l0.m`：38 号 `make_platform_plant`（滑动电压参照+真相位句柄，moe38
     权威口径）副本，唯一语义差异 = `q()` 返回口径（真值→L0）+ S5 驻留制；真值口径日志列与
     基底逐位一致；新增 powerEstN/voltV 诊断列；预训练域一致性：L0 场景一律在线预训练于同一
     估计口径 plant（`pretrainCache=false`），ANCHOR 保留缓存复现 moe38；
   - `+q39/run_algorithm.m`：38 号调度器副本，plant 构造换 q39，臂函数仍调 `w36.*` 原实现；
   - `+q39/q1_opt.m`（矩阵预注册单一事实源）、`run_q1_chunk.m`（增量 CSV + 幂等重跑 + M5 逐位
     比对）、`q1_metrics.m`（双口径指标）、`trim_curve.m`（S3 离线解析分解 + S2 解析谷移表）、
     `tests_q1.m`（单元门 8 项）、`run_q1_checks.m` / `run_q1_matrix.m` 入口。
2. **预注册修正两则（开批前，均入档）**：
   - 修正 #1：trim_curve 实测 P2 平台曲线谷（5.15 m/s，k=9.56 W/(m/s)²）由 H3 前飞诱导项创造，
     L0 静态映射曲线无谷（argmin 在 0，谷区结构偏差 ~+21%）→ S1/S2/S5 移到 truth 口径+合成标定
     残差上测（b₁* 只对"已抓住曲线形状"的估计器有定义），S3/S4 留 l0 基座；
   - 修正 #2：M1 植物级一致性门 1e-9 → 5e-5（P2 的 pwm 派生用上一步端电压，因果次序产物；
     公式级严格性由往返测试 1e-12 保证）。
3. **调试中抓到并修复的实现错**（都在开批前）：nce 单位 RPM vs 台架 krpm（÷1000）；
   `struct('arms',{})` 生成 0x0 空结构体陷阱（4 处默认 opt）；`switch upper()` 与混合大小写
   档位名冲突；分解式"δ 作用于扣 H3 后功率"口径（与植物 `(bench−sav)(1+δ)` 对齐，差 4·sav·δ）；
   批处理脚本 cd 层级与 $PWD 传 MATLAB 的路径问题。
4. **正式批**：19 分块 × 独立 MATLAB 会话（R6 缓解），02:19–05:11 全部 rc=0，总 2h51m。

## 结果速览（详见证据文档）

- ANCHOR 逐位复现 moe38 3600s（openloop 6.2643/sweepcal 4.0241/purerl_off 0.4627/…）；
- M5：RERUN 独立会话 39 字段 `==` 逐位一致 PASS；单元门 8/8；
- S3：L0 不可部署（sweepcal −11.65pp 灾难、purerl_off 磨损 3.06pp）；S2：b₁*=−2.6~−2.8 %/m/s
  （sweepcal 负向先破），purerl ±2.8 未破；S1：常数 ±5% 无害；S4：电压归一化不需要（D3 关闭）；
  S5：≤2s 无损，实机 t_dwell 留 Q2 轨 B；
- 决策输入：D1 升 L1 档；误差带草案"常数 ≤5% + 倾斜 ≤1.4 %/m/s → 磨损 ≤0.9pp"（< M6 门 1pp）。

## 边界与备注

- 全部数字为 X8 P2 管线敏感性口径（P4），不得引用为四旋翼真实节能/实飞结论；
- 解释边界：P2 未建实机螺旋桨前飞转速下降（n 效应），L0"灾难性"结论为保守上界，Q2 轨 B 复核；
- 冻结边界零触碰：`models/plane`、`modules/platform_link{,_37,_38}`、全部 `.slx`、既有证据；
  X8 52/52 回归不受影响（本批零改动冻结路径，M8 全量回归留 Q3/Q4 收口）；
- `launch_3_6_demo.m` 的 3600s UI 修复按叶安指示仍留工作树未提交（H1 依赖项，另行走流程）；
- 附带观察（平台线，未处理）：委托制基线的 q() 采样含首秒瞬态分量（S5d1 对比可见量级），
  值得平台线后续单独量化；`launch_3_6_demo.m` 检查脚本产生的 debug1/debug2 留在 results/
  （gitignored）作为调试痕迹。
