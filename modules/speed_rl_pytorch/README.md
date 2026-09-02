# speed_rl_pytorch — 残差速度 RL 的 Python 训练线(环境对拍 + 课程/BC/TD3)

> 2026-09-02 ｜ 状态:环境与 MATLAB 逐行对拍一致(确定性场景 12 位小数相同);
> 已产出 v0 课程 TD3、BC 热启动(h8/h32)、BC+TD3 微调四个候选与
> 4 场景 × 20 未见种子评估(证据见 `docs/evidence/speed_rl_pytorch/`)。

## 定位与动机

本模块是 `modules/speed_rl_residual` 的**算法线预研扩展**,不接入平台线:

- 把该模块的合成适配器(不规则 OU+阵风、圆周轨迹、可观测性三档、guard、
  14 字段契约语义)逐行移植为 Python/PyTorch,使其可在无 MATLAB RL 工具箱的
  机器上用 GPU 训练;
- 移植正确性经对拍验证:`parity_check.py` + `parity_matlab.m`
  (确定性场景公式级一致;随机场景统计一致,MATLAB 侧复现仓库证据值
  480.255/474.229 W);
- 本地训练运行输出(`results/`)不进版本库;精选证据与最优策略检查点
  入 `docs/evidence/speed_rl_pytorch/`(沿用"TD3 候选作例外"的入库先例)。

## 结论速览(平均真实代理功率,相对固定 6.3 m/s;20 未见种子/场景;零违规)

| 场景 | 解析残差 | TD3 课程 v0 | BC h8 | BC h32 | BC+TD3 微调 |
|---|---|---|---|---|---|
| 不规则·可观测 | -1.71% | +4.55% | **-1.91%(20/20)** | **-1.97%** | +4.16% |
| 恒定·可观测 | -1.75% | +7.71% | -1.77% | **-1.86%** | +4.58% |
| 不规则·缺测 | -0.95% | +4.12% | **-1.45%(20/20)** | -1.35% | +4.74% |
| 不规则·隐藏 | =固定 | +4.72% | +0.78% | +0.39% | +2.23% |

1. **BC 热启动(教师=真值风解析最优残差,仅用于生成监督数据)超过解析残差**,
   缺测场景优势最大(解析式缺测窗口回退,学习策略动作连续);
2. 从零 TD3(1730 回合课程)退化为与风无关的固定偏置——奖励信号仅占总回报
   ~2%,价值估计误差淹没真实信号;BC 之上 TD3 微调亦劣化,失败锁定在 RL
   优化环节而非策略表达能力;
3. 隐藏风是信息层面硬问题(8→32 帧仅边际改善;最优空速处功率对风一阶
   敏感度为零,与平台线 ESC 需主动激励同源)。

## 文件

| 文件 | 说明 |
|---|---|
| `speedrl_env.py` | 环境逐行移植(config/适配器/guard/context/observe/baseline/回合/课程) |
| `td3.py` | TD3(超参镜像 `+speedrl/make_agent.m`:128 隐层×2、batch 128、γ=0.995、探索 σ=0.72→0.06) |
| `train_curriculum.py` | 7 阶段课程训练(v0) |
| `bc_train.py` | BC 热启动(`--history 8/32` 消融) |
| `finetune_td3.py` | BC 初始化 + TD3 微调(v1) |
| `evaluate.py` / `eval_bc.py` | 多场景未见种子评估(CSV 列与 MATLAB `evaluate_policies` 一致) |
| `parity_check.py` / `parity_matlab.m` | Python↔MATLAB 对拍(后者无需 RL 工具箱) |
| `make_final_figures.py` | 综合图与报告生成 |
| `checkpoints/` | 四个候选的 actor 检查点(v0 课程、BC h8/h32、微调) |

## 运行

依赖:Python≥3.10、numpy、pandas、matplotlib、torch(CUDA 可选);
对拍另需 MATLAB(基础版即可)。

```bash
python parity_check.py                                  # 环境自检
matlab -batch "parity_matlab"                           # MATLAB 对拍(路径自动相对)
python train_curriculum.py --episodes 100 150 150 150 450 280 450   # v0,约40min@4060
python bc_train.py --history 8 --episodes 1200                      # BC,约3min
python finetune_td3.py --bc results/bc_actor_h8.pt                  # v1,约15min
python evaluate.py && python eval_bc.py --ckpt checkpoints/bc_actor_h8.pt \
  --history 8 --name bc_agent && python make_final_figures.py
```

评估种子与训练种子零重叠(训练 1000+/30000+,评估 2001-2020/3001-3020/
4001-4020/5001-5020)。

## 边界

- 虚拟代理对象、Python 对拍环境口径;不外推真实 X8,不构成飞行结论;
- 教师用真值风只发生在监督数据生成阶段,评估与部署只用测量(因果红线);
- 三套代理功率模型(ratio_esc/speed_esc/speed_rl_residual)与本 Python 移植
  之间,仅同一引擎内可直接横比;
- 遵守 ADR-002:不得宣称"RL 已解决不规则风优化/优于 ESC/真实节能"。

## 署名

| 姓名 | 角色 | 主要文件/功能 | 日期 |
|---|---|---|---|
| 待项目组确认 | 模块负责人(需求提出与技术判断) | 训练路线决策、结果审定 | 2026-09-02 |
| (同上,待确认) | 执行 | 环境移植对拍、TD3/BC 训练与评估 | 2026-09-02 |

AI 协助:ZCode(环境逐行移植、训练/评估脚本、图表与报告整理);
上游模块 `speed_rl_residual` 的原有成果归属该模块 README 记录。
