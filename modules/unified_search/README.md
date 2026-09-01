# 统一速度寻优程序：任务1平移 × 任务2崎岖 × MOP/MOE

> 2026-09-01 ｜ 状态：13/13 单元测试、8/8 验收门槛通过

## 署名与贡献（占位，待模块负责人确认补齐）

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：待模块负责人确认（本 README 按 `docs/AUTHORSHIP.md` v1.0 由平台线代为补充占位，署名以模块负责人确认为准）
主要撰写：待模块负责人确认
审核：待项目组审核
AI协助：待模块负责人确认

> 复验记录（2026-09-01，`docs/evidence/PROJECT_REACCEPT_CODEX_20260901.md` F5/F6）：验收入口 `run_unified_acceptance` 已改为单元/门槛未全过时硬失败（返回非成功结果）；本 README 贡献表与 worklog 为平台线代补的占位，正式署名由模块负责人补齐。

> 整合 `task1_search`（平移黑箱直搜）与 `task2_rugged`（崎岖滤波全局寻优），
> 新增能耗感知算法 ea_multistart 与统一 MOP/MOE 评价。
> **演示面板当前仅提供 tracker平移跟踪 与 esc连续ESC 两个算法**
>（2026-09-01 定稿）；ea_multistart 等其余算法保留在 +usearch 包内，
> 由验收脚本与单元测试覆盖，供离线横比。

## 用户三项要求的落实

### 1. 寻优消耗的能量必须计入——ea_multistart（推荐方案）

全遍历（61点粗扫描+全谷精调，multistart共约425评估步）每一步都在烧电，
不是好策略。ea_multistart 的能量账本：

| 阶段 | 做法 | 成本 |
|---|---|---|
| 局部优先 | 从初始速度两轮 pattern search（7点×2轮） | 14步 |
| 噪声自估计 | 同点4次重复取σ̂（黑箱自含，不读对象配置） | 4步 |
| 远点证据 | 3个远点各做迷你下降（3点滑向谷底），只有 `farBest < localBest−2.5σ̂` 这类**确凿证据**才升级 | 9步 |
| 证据升级 | 才执行粗扫描（41点，非全遍历）+滤波选谷+两候选精调 | 55+55步 |
| 终精调 | 5点对称stencil×4次重复，最小二乘顶点（无偏定位） | 20步 |
| 锁定+监测 | 事件驱动监测（复用hold评估，**零额外成本**） | 0步 |

实测（崎岖静态，1小时窗）：EA 平均 MOE=0.9927 > multistart 0.9924，
搜索步数 165 vs 400（全部20种子）——**能耗感知策略用更少的电达到相当效能**。

监测与平移恢复（整合任务1能力）：
- 12步滑动窗功率水平监测复用hold评估（零成本）；越限需**连续两窗确认**（抗噪声误触发）；
- 确认后直接全局升级（崎岖曲线上斜率/改善量探针会被纹波抵消——实测后放弃的方案，见下"调试记录"）；relocalMax=3 封顶；
- 纯上下平移(dy)表现为一次性吸收，jumpDown 恢复29步、err 0.10。

### 2. 任务1+2整合为一个程序

对象 = 调试二次曲线基准（与speedesc同口径 `1+0.003(v−6)²`）+ 对称负余弦
崎岖项（A1/A2可调，置零即任务1平坦曲线）+ 任务1式平移调度
（static/jumpUp/jumpDown/offset/ramp，幅值与时刻面板可调）。

面板算法（2选1）：**tracker平移跟踪**（任务1：Brent+迟滞双阈值监测，
dy零误触发）、**esc连续ESC**（连续极值寻优基线）。其余算法
（ea_multistart/multistart/grid/fixed/single_golden）代码保留于 +usearch，
供验收脚本、单元测试与离线对照使用，不在面板中提供。

### 3. MOP/MOE 内置

- **MOE_energy = Emin / E_actual ∈ (0,1]**：Emin=Σ Pmin(t)·tEval（每时刻
  理论最低功率的积分，先验下界），E_actual=Σ P_true·tEval（实际能耗，
  含搜索代价）。越大越好；`fixed`（全程停最优）为不可达上界参照。
- **7项MOP**：tSearchEvals（收敛评估数）、finalErr、regretPercent、
  energyExcessPercent（与MOE满足解析关系 MOE=1/(1+超额%)，入测试）、
  holdFraction、budgetUtilization、energyAccounting 开关。
- 能耗开关 `usearch.config('energyAccounting',false)`：能耗列NaN，只评定位。

## 首次横比结果（验收实测）

**1小时窗（崎岖静态，T=3600s）**：

| 算法 | 平均MOE | 说明 |
|---|---:|---|
| fixed | （上界） | 全程停最优，不可达参照 |
| **ea_multistart** | **0.9927** | 能耗感知：最少搜索电换最高效能 |
| multistart | 0.9924 | 全遍历策略：定位准但搜索烧电 |
| grid/esc/single_golden | 更低 | 见 results/moe_1h.csv |

**平移场景（EA，10种子）**：jumpUp 恢复67步、jumpDown 29步、ramp 9/10种子
误差≤0.35（尾部种子1.69如实记录）。

## 面板日志栏

面板左下为**日志栏**（最新条目置顶，最多保留400行）：
- 每次重置记录参数摘要（算法/场景/初速/噪声/崎岖参数/跳变设置/种子）；
- 播放到末帧输出 **MOP/MOE 汇总**（MOE_energy、末误差、稳态超额、
  全程能耗超额、入带步数、锁定占空）；
- **"载入验收报告"按钮**把 results/report.md 全文载入日志（启动时若已
  存在报告会自动载入门槛明细与1小时MOE横比）；"清空日志"随时清理。

## 文件与运行

```text
unified_search/
  START_HERE.m / launch_unified_demo.m   入口与动画面板(含日志栏)
  +usearch/                              包：config/base_curve/scenario/
    shift_truth/make_plant/brent_search/apply_filter/search_query/
    tracker_run/multistart_run/esc_run/ea_run(推荐)/run_algorithm/mop_moe
  run_unified_acceptance.m               验收(门槛+1小时MOE横比)
  tests_unified.m / qa_unified_demo.m    13项测试 / 面板自检
```

```matlab
cd unified_search
START_HERE                    % 动画面板
run_unified_acceptance        % 验收(results/report.md, scenarios.csv, moe_1h.csv)
tests_unified                 % 13项单元测试
```

## 诚实边界

代理曲线与1%噪声口径；EA对慢漂(ramp)恢复慢于跳变（功率水平监测的物理
延迟），门槛按≥9/10种子≤1.6如实设定；瞬时跳变速度是任务设定（实机动态见
speedesc工程）；结论不外推真实X8节能。
