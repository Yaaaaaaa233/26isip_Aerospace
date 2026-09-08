# 任务3.5：预训练 purerl 拆分（purerl_on 在线 / purerl_off 离线 / purerl_scratch 从零对照）

> 第四轮（3.x）任务（2026-09-08）。其余算法**原样继承 3.4**（sweepcal / rl / hybrid /
> openloop / windinfer / est / known，含全部既有修复），**只有 purerl 被调整**：
> 3.4 的 purerl 从零在线学习，前段无数据效果差、随时间缓慢变好（评估窗内学习曲线
> 拖累 MOE）。本任务给 purerl 增加**试飞预训练时段**，并把部署拆成在线/离线两种。

## 一、预训练时段（试飞时段，不占评测预算）

- purerl_on / purerl_off 在正式 600 步任务窗**开始前**获得一段试飞时段：独立 plant
  实例、static 场景、湍流为同分布**不同实现**（scenario seed+17，不泄漏评测段真值）；
  预训练步**不计入评测预算、不进评价表/MOE**。
- 预训练机制与 purerl 同构（对偶交替探索 + 分航向桶基线 + 邻域共享核 REINFORCE），
  σ 从 1.2 退火到 0.5（即部署探索幅值，评估期无需重新退火）。
- **自动收敛判据**（"当你认为模型学习好了"）：每 200 步一块，块均|策略更新|<0.02 且
  块均功率相对改善<0.05% → 判定收敛；最少 400 步起判，上限 `plWarmMax=2400` 步。

## 二、两种部署 + 一个对照

| 算法 | 评估期行为 | 定位 |
|---|---|---|
| `purerl_on` 预训练在线 | 预训练初始化策略/基线，继续小幅在线修正（lr=1/4、σ=0.5、瞬态不更新） | 干扰漂移下持续适应 |
| `purerl_off` 预训练离线 | 冻结策略纯贪心执行，零探索零学习（同种子逐位可复现） | 确定性部署、无探索能耗 |
| `purerl_scratch` 从零对照 | = 3.4 原 purerl（无预训练） | 量化预训练价值 |

**信息预算口径（如实标注，红线3）**：purerl_on/off 获得试飞预训练步（不占评测预算但属
额外信息预算，类比任务窗前的试飞时段）；sweepcal/rl 的 150 步标定**占**评测预算。两类
预算口径不同，横比结论必须带此标注。

## 三、效果（2026-09-08，2种子800步主口径 + 单测）

见 `results/report.md` 与 `run_task35_checks`。预期结论（门槛亦如此设定）：
- 恒定风：purerl_off/on 优于开环且超额 <5%，**均优于 purerl_scratch**（预训练消除前段
  学习劣势）；
- 漂移干扰（composite）：purerl_on 优于 openloop 且**优于 purerl_off**（在线学习的价值）；
- 继承算法门槛全部保留（sweepcal/hybrid/rl/known 等），确保"其余算法不变"。

## 四、运行

```matlab
cd 3.5_purerl_pretrain_split; addpath(pwd);
tests_task35           % 单元测试
run_task35_checks      % 门槛 + 证据报告(results/report.md)
table_3x3              % 3×3 验证表
launch_3_5_demo        % demo 面板(默认 purerl_off)
```

## 五、边界与红线

- 预训练/评估均只拿带噪功率+自身指令（红线1）；对象接口 plant.q/amendEstimate/count
  不变（红线2）；结论为 proxy 等级，不支持真实机型节能表述（红线3）；
- 预训练场景固定为 static：若评估场景为跳变类（jumpUp 等），预训练段看到的是跳变前
  形状，purerl_off 不适应跳变（purerl_on 可在线适应）——如需覆盖请扩展预训练场景；
- 其余算法与 3.4 逐字节同源（包前缀 w34→w35），其结论直接继承 3.4。
