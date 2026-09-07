# T1 开环验收证据（正式运行批次 20260907_173218）

- 运行入口：`models/plane/t1_acceptance_run.m`（图集 A/B/C/D + S 与指标表由该脚本从同一次批量运行导出，同源/同种子/同 commit；本目录为 evidence 权威副本，运行原始目录 `results/t1_openloop/20260907_173218_t1/`（gitignored，含 result.mat））
- 判定依据：`docs/T1_ACCEPTANCE_CHECKLIST.md` v1.0（经叶安确认）；**21/21 机器门槛 PASS，余 B2 风三角为人工核对项**（见 B 组图第二格）
- 场景预登记与口径：见 `t1_openloop_run.m` 头注与指标表口径栏（T=400s 主任务 / R=100m / W0=3 东 / Tc=0.5s / dt=0.01s / 电池窗口占位参数 / 20 种子风幅抖动 N(1,0.05)）
- 核心数：S1 nominal |Percent| 中位数 0.133%（参考带 ≤5%）；fixed 中位数 +11.679%（不适应代价，仅报告）；S2 配对差 mean +11.509% / max +12.090% / std 0.377%
- 边界：统一 Plane 代理（proxy 功率/线性 OCV 占位电池）；"电厂功率偏置"种子扰动在代理世界不适用（plant==名义模型），P2 物理化后引入；代理世界 nominal 残差含 4-迭代 rollout 截断
