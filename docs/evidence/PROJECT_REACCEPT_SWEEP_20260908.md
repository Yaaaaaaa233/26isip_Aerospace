# 全项目重新验收扫描（2026-09-08，ZCode / 平台线，叶安指示）

范围：当前 HEAD 对仓库内全部可执行验收入口做一次 fresh 实跑扫描（平台线全量 + 算法线 sweep + 共享基础设施），如实记录判定与发现。**本扫描是修复方/平台线侧自验性质，不替代任何独立复验**；M3 放行仍以独立复验为准。

扫描基线：`949eb50`（干净树；P2 WP1–WP4 于 `0d5f60c` 落地后的首个复验提交）。

## 1 结果总表

| # | 入口 | 结果 | 关键数字 |
|---|---|---|---|
| 1 | 治理检查 `tools/check_repo_governance.ps1` | **PASS** | 19 模块登记 / 29 文档 |
| 2 | Plane P0–P4 契约 `run_plane_acceptance` | **PASS** | P0=489.8 W，energyErr=0 |
| 3 | P2 链检查 `run_p2_chain_check`（21 门，含本轮新增 G-U） | **FAIL（1 门）** | 20 门 PASS；**G-U U 形存在性 FAIL**（v\*=0，见 §2.1） |
| 4 | 适配器检查 `run_plane_adapter_check` | **PASS** | G1–G5 全过，t63=2.840 s（声明主极点 1/kp=2.857 s） |
| 5 | harness 单元测试 `run_harness('tests')` | **PASS** | 4/4 |
| 6 | T1 入口@HEAD 演示 `t1_acceptance_run` | **18/21（预期口径切换签名，见 §2.2）** | A3=3.48 s、A4=0.334、S1 nominal=+77.1%；B/C/D 组全过 |
| 7 | x8phys `run_x8phys_acceptance` | **PASS** | 597.490/961.047 W、balanceErr=2.01e-16（与登记值逐位一致） |
| 8 | M3 协调单测 `test_m3_coordination_unit` | **PASS** | B1–B8 |
| 9 | M3 驱动测试 `test_m3_batch_driver.ps1` | **PASS** | 9 场景（时序修复后稳定，见 §2.3） |
| 10 | M2 驱动测试 `test_m2_batch_driver.ps1` | **PASS**（修复后） | 9 场景 ×3 连跑稳定 |
| 11 | M3 正式批次（init→s5→aggregate→vunit→vnegative→vaggregate→vreport） | **PASS** | batchId `000f024f…` @ `949eb50`，**11 阶段全 attempt 1**，14 臂复核、恢复矩阵 28 行、配对 −0.29102%（与第三轮独立口径一致） |
| 12–28 | 算法线 sweep（17 个 MATLAB 入口） | **17/17 OK** | ratio_esc/speed_esc/speed_rl_residual/speed_shift/speed_rugged/wind_circle/sin_wind/ortho_wind/adaptive/wind_field_sched/curve_case_calibration/wind_model_library/wind_semantics_correction/wind_inference/curve_unknown/reward_only_rl/unified_search |

未跑（登记说明）：`speed_rl_pytorch`（Python/torch 训练评估线，非 MATLAB 入口，owner 线）；`realistic_constraints_search`（任务 7 验收入口脚本未入库——状态页既有登记）；M2 52 行链（见 §2.4）；M0/M1 Simulink 套件（冻结证据制，其模型链在 M3 正式批次的 14×240 s 仿真中被实际行使）。

补扫（2026-09-08 晚，rebase 后 HEAD `3bcdd6e`）：扫描期间王健祺上库两个新模块（`8b04df7`：unified_four_algos 3.4 / curve_calib_windinfer 3.3），其验收入口在整合后补跑——**curve_calib_windinfer 11/11 门槛、unified_four_algos 13/13 门槛全过**；治理复检 PASS（登记模块 21）。

## 2 发现与处置

### 2.1 【开放 P1】P2 合成功率无 U 形左支（H3 未接入）——G-U 门 FAIL

- 现象：`run_p2_chain_check` 新增 G-U 门（本轮把 T2 清单 §2 D6"谷底形态"机器化）：稳态 P(v) 扫描 v∈{0,2,…,14}，实测 **v\*=0、P(v*)=P(0)=487.3 W**，功率自悬停单调上升——**无左支、无内点谷底**。
- 根因：WP2 每电机合成用台架**静态** P(n)（v_air=0 数据），桨诱导功率不随前飞衰减；06 §3 已登记"静态台架给左支"需 H3 前进比修正，但 P2 构建未实现，且原 20 门无 U 形存在性检查（检查盲区——本轮已补门堵住）。
- 影响：V\*=0 使在线寻优退化为"尽量慢飞"，T2 名义调度/风致摆动/省能叙事全部失去意义。**此状态不得启动 T2 正式跑批**。
- 处置建议（待叶安拍板，2026-09-08 已提出）：动量理论诱导修正缺省（vi(v)=√((v/2)²+T/2ρA)−v/2，输入=台架拟合+桨盘面积），作为 H3 缺省形式补登 06 并附敏感性带；修复后 G-U 门转绿、清单 v1.1 登记正式门槛。

### 2.2 T1 入口@HEAD：18/21，3 项 FAIL 全部为模型更换的预期签名（非缺陷）

`t1_acceptance_run` 在 HEAD 实跑（该入口已登记为冻结证据的历史复现入口，T2 用新入口）：A3 t63=3.48 s（旧门槛 0.9–1.1 s 是 τ=1 代理口径；P2 内核声明主极点 1/kp≈2.86 s，待 §9.4 重预登记）；A4 静默窗跟踪 0.334 m/s（内核变慢的物理后果）；S1 nominal Percent=+77.1%（plant 已是 P2 物理链 ≈500 W，E_pred 分母仍为 proxy 公式 ≈280 W——**拍板 4"proxy 退役、T2 重建 E_pred"的量化体现**）。B/C/D 组物理门（风恒等式 1.78e-15、ZOH、测量链 0.200 s、电池窗、能量对账 0）在 P2 plant 上全部照过——P2 对象在 T1 场景 harness 内契约符合。

### 2.3 【已修复】M2/M3 驱动测试时序竞态（测试层，非驱动回归）

首跑 M2 驱动测试 FAIL（S5+S7），复跑 FAIL 集合变为 S2×2+S5——**失败集合随运行变化 = 时序抖动**。根因：mock 在 t0 同一时钟刻度内写新鲜标记，`LastWriteTime -gt T0` 严格比较随机落空（后台仿真占 CPU 时放大）。驱动生产代码自 `2c3c6c3`（登记 9/9 之前）未动，且真实 MATLAB 阶段耗时秒—分钟级、不存在亚毫秒窗口。处置：两个测试文件的 marker-writing mock 在 t0 后垫 15 ms（不弱化任何断言），修复后 4 连跑全过（`949eb50`）。中途一次修复尝试把中文注释写进无 BOM 的 ps1 被 PS5.1 按 ANSI 误读破坏语法——已改 ASCII 注释（教训登记：ps1 注释一律 ASCII）。

### 2.4 【登记开放项】M2 52 行链在 HEAD 未重跑（m2_eta_esc 冻结后被 M3 改动）

M2 第十轮证据绑定 `71acd56`；其后 M3 开发（`e5d5745`/`93b1b68`）修改了共享文件 `m2_eta_esc.m`（M3 仲裁模式扩展）。改动路径已被 M3 全套件（含本扫描 §1 #11 正式批次）覆盖，但 **M2 数值门槛（S1/S2/S3）在 HEAD 无重跑证据**。是否触发 M2 52 行复跑由项目组决定（属 M2 独立验收制度，本扫描不代跑）。

### 2.5 【登记】算法线 sweep 副作用：两个验收入口重存 .slx，另有一个入口写 modules/results

`ratio_esc`/`speed_esc` 的 `run_acceptance`/`run_speed_acceptance` 运行后把各自 `models/*_closed_loop.slx` 重存（tracked 二进制变更）。本次已恢复原状（`git checkout`）；请模块 owner 关注入口的非幂等性（建议入口不落盘或落 gitignored 路径）。另 `speed_rugged_search` 入口在 `modules/results/` 留下相对路径输出（触发治理检查未注册模块 FAIL，已清理再生性产物后恢复 PASS）——同属入口工作目录副作用。

## 3 结论

- **绿**：治理、Plane 契约、P2 链 20/21 门、适配器、harness、x8phys、M3 全链（含 HEAD 正式批次 11 阶段 attempt-1）、M2/M3 驱动与协调单测（修复后）、算法线 17 入口。
- **红（1 项 P1 开放）**：P2 U 形左支缺失（§2.1）——**T2 正式跑批在此之前不得启动**；修复方案待叶安拍板。
- 预期签名（非缺陷）：T1@HEAD 18/21（§2.2）。
- 登记开放：M2 链 HEAD 复跑决定权（§2.4）、算法线入口 .slx 副作用（§2.5）、speed_rl_pytorch/任务 7 入口缺位（既有登记）。

全部结论锁 V1 桌面仿真等级；本扫描不构成 M3 放行（独立复验另行）。
