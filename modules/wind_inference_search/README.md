# 风速推断寻优模块：u\* 固定已知，风未知由功率反推（第二轮 2.x 起点）

> **2026-09-07 更新**：算法集精简为 windinfer（主角）/openloop/est/known（删除 task1 遗留
> 直接搜索器 tracker/esc/spsa/bayes/qnewton/gtrack——不建模风、与 2.1 主题无关、样本效率低）；
> demo 修复风场预设（切换风场自动载入推荐参数，此前幅值默认0导致五种风场退化平线）；
> turb 族湍流 σy 改用 windAmpY。精简后复跑 27/27 单测 + 8/8 门槛全绿；
> 横比明细与 3×3 表见 docs/evidence/wind_inference_search/（2026-09-07 刷新）。
> 全版本梳理见 [VERSION_REVIEW_20260907_wjq.md](../docs/VERSION_REVIEW_20260907_wjq.md)。


本地编号：**2.1**（第二轮第一个任务，本地文件夹 `speed_esc_matlab/2.1_wind_inference`，内部包 `+w21`）。
对象物理与 wind_semantics_correction（1.11）一致：空速 = 地速 − 风、风不影响运动、
实际约束动力学（物理转弯半径/通信时延/加速度限幅）。

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：王健祺
主要撰写：王健祺
AI协助：ZCode（对象实现、windinfer 算法、测试检查验证脚本、实验矩阵）
审核：待项目组审核

## 1. 任务设定（用户口径 2026-09-05）

- 速度-功率曲线先验已知（无风标定：空速=地速），**空速-功率曲线严格固定** →
  功率最低点对应的**空速最优点 u\* 固定且已知**（u\*=6.3 m/s，Pmin=curveCase 恒定）；
- 转圈飞行，地速方向由轨迹确定，**地速大小是唯一决策变量**；
- **风对控制器未知**（大小/方向/是否变化都未知），只通过空速影响功率；
- 控制器只知道：u\*、先验曲线 J0、轨迹几何 R、采样时间 + 两个仪表盘（地速、带噪功率）。

## 2. windinfer 策略（`+w21/windinfer_run.m`，纯因果）

转圈时航向扫过风场，功率被调制 P(ψ)=J0(|v·t̂−w|)：

- **规整周期波动 → 判恒定风**（波动源于转圈方向变化）；**毛糙/前后窗解不一致 → 判变风**；
- 滑动窗内二维非线性最小二乘反演 w=(wx,wy)（多起点 Gauss-Newton，8方向×3幅值网格）；
- 窗长自适应：半窗解一致性（3σ 显著性+失配地板）→ 加长窗提精度 / 分歧 → 缩窗提跟踪；
- 每步闭式调度 `v_cmd = q̂ + sqrt(q̂² + u\*² − |ŵ|²)`，q̂=t̂·ŵ（顺风为正）；
- **全程零探针 dither**——激励来自转圈本身的航向扫描；锁定后任何风估计误差都会重新
  引入功率调制被观测到，构成负反馈自校正。

与第一轮负结果的关系：第一轮发现"谷底测量几乎不含风信息（一阶导为零）"是**探针类**
方法的信息瓶颈；本模块的激励来自航向扫描（圆周各处空速不同），绕开了该瓶颈——
这不是算法更聪明，而是**信息结构变了**（问题从"盲搜移动最优"变成"估 2 个风参数+闭式解算"）。

## 3. 验证结果（MOE = 纯能耗 Emin/Eactual，2026-09-04 口径）

600 s ≈ 6 整圈，2 种子均值（详见 [`../docs/evidence/wind_inference_search/main_comparison.csv`](../docs/evidence/wind_inference_search/main_comparison.csv)）：

| 风况 | openloop | est(EKF对照) | **windinfer** | known(上限) |
|---|---:|---:|---:|---:|
| 无风 | 1.0000 | 0.9143 | **0.9993** | 1.0000 |
| 恒定风 3.5@40° | 0.9399 | 0.9380 | **0.9945**（风估计误差 0.15 m/s） | 0.9988 |
| 变风 composite | 0.9533 | 0.9298 | **0.9633** | 0.9967 |
| 强风 5.5@200° | 0.9323 | 0.9629 | **0.9890** | 0.9987 |

**因果性三重核验**（详见 [`../docs/evidence/wind_inference_search/wind_inference_check.md`](../docs/evidence/wind_inference_search/wind_inference_check.md)）：

- A1 结构：`windinfer_run(plant,p,n)` 不接收场景真值 scn；
- A2 行为（假 config 试验）：对象真风 3.5@40° 不变、算法手里的 config 改为假风 8@170°，
  最终估计距真风 0.09 m/s、距假风 10.68 m/s → 风信息只来自功率测量；
- A3 源码：对风真值字段（windBias/windKind/windAmp/ω/turb…）引用数为 0——
  算法也不知道风怎么变，变风靠残差一致性事后发现。

**猜测精度**：恒定风 10 组方向×幅值，幅值误差均值 0.11 m/s（最差 0.22）、方向误差 ≤3°、
约 0.4 圈收敛；变风稳态逐点 RMSE 2.17 m/s（估计跟住均值与慢趋势，快振荡受滑窗分辨力
限制衰减跟随——信息滞后的物理边界，B3 对照：风变化周期短于一圈时误差≈风变化幅值本身）。

3×3 验证表见 [`../docs/evidence/wind_inference_search/table_3x3.md`](../docs/evidence/wind_inference_search/table_3x3.md)。

## 4. ⚠️ 有效性边界（如实标注）

- **依赖曲线先验**（u\* 已知）：2.2 曲线未知后，闭式调度不可用，本模块结论**不直接外推**；
- **变风受限**：风变化快于推断窗分辨能力时只剩均值/慢趋势跟踪，剩余误差是信息滞后；
- est 对照带 dither，无风时反而最差（9.4% 超额）——探针类方法的成本在这组实验里如实可见；
- 曲线/风场参数未实测校准；全部结论为 proxy 等级代理口径，不支持真实 X8 节能表述（红线3）。

## 5. 运行

```matlab
cd wind_inference_search; addpath(pwd);
tests_task21              % 27 项单元测试
run_task21_checks         % 8 项门槛 + 证据报告
table_3x3                 % 3×3 验证表 → docs/table_3x3.md
verify_wind_inference     % 因果性+精度双重验证 → docs/wind_inference_check.md
launch_2_1_demo           % 三模块动态演示面板(策略默认 windinfer)
```
