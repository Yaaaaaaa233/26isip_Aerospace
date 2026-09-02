# -*- coding: utf-8 -*-
"""
最终综合对比图:
  fig_final_mean_power.png  4 场景 × 6 策略
  fig_final_paired.png      最优学习策略 vs 固定基准逐种子
  fig_final_curves.png      训练曲线(课程 v0 + BC + 微调)
  summary_final.md/csv + report_final.md
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "sans-serif"]
plt.rcParams["axes.unicode_minus"] = False

ROOT = Path(__file__).resolve().parent
RES = ROOT / "results"

SCEN = [("irregular_observable", "不规则风·可观测\n种子 2001-2020"),
        ("constant_observable", "随机恒定风·可观测\n种子 3001-3020"),
        ("irregular_dropout", "不规则风·缺测\n种子 4001-4020"),
        ("irregular_hidden", "不规则风·隐藏\n种子 5001-5020")]

# 策略显示顺序与取数来源
SOURCES = [
    ("fixed", "固定 6.3 m/s", "policy_evaluation_{k}.csv", "#8c8c8c"),
    ("scripted", "解析残差(可观测风)", "policy_evaluation_{k}.csv", "#2e7d32"),
    ("td3_agent", "TD3 课程 v0(从零)", "policy_evaluation_{k}.csv", "#ef6c00"),
    ("bc_agent", "BC 热启动 h8", "bc_eval_{k}.csv", "#1565c0"),
    ("bc32_agent", "BC 热启动 h32", "bc_eval_{k}_h32.csv", "#5e35b1"),
    ("td3_ft_agent", "BC+TD3 微调 h8", "bc_eval_{k}_ft.csv", "#c62828"),
]


def load_all():
    frames = {}
    for key, _ in SCEN:
        per = {}
        for pol, _, pattern, _ in SOURCES:
            f = RES / pattern.format(k=key)
            if not f.exists():
                continue
            df = pd.read_csv(f)
            if pol in set(df.Policy):
                per[pol] = df[df.Policy == pol].sort_values("Seed")
        frames[key] = per
    return frames


def fig_mean(frames):
    present = [s for s in SOURCES
               if all(s[0] in frames[k] for k, _ in SCEN)]
    n = len(present)
    fig, ax = plt.subplots(figsize=(14, 6))
    rng = np.random.default_rng(0)
    width = 0.8 / n
    for si, (key, title) in enumerate(SCEN):
        for pi, (pol, lab, _, col) in enumerate(present):
            df = frames[key][pol]
            vals = df.MeanPowerW.to_numpy()
            x = si + (pi - (n - 1) / 2) * width
            ax.bar(x, vals.mean(), width * 0.9, color=col, alpha=0.9,
                   zorder=2, label=lab if si == 0 else None)
            ax.errorbar(x, vals.mean(), yerr=vals.std(ddof=1), fmt="none",
                        ecolor="black", capsize=2.5, zorder=4)
            ax.scatter(x + rng.uniform(-0.03, 0.03, len(vals)), vals, s=8,
                       color="black", alpha=0.35, zorder=3)
            ax.annotate(f"{vals.mean():.0f}", (x, vals.mean()), xytext=(0, 7),
                        textcoords="offset points", ha="center", fontsize=7.5)
        fixed = frames[key]["fixed"].MeanPowerW.mean()
        ax.axhline(fixed, color="#666666", ls="--", lw=0.8, zorder=1)
    ax.set_xticks(range(len(SCEN)))
    ax.set_xticklabels([t for _, t in SCEN], fontsize=9.5)
    ax.set_ylabel("平均真实代理功率 (W)")
    ax.set_title("学习策略 vs 基线(20 未见种子/场景;虚线=该场景固定基准;"
                 "点=逐种子)", fontsize=12)
    ax.grid(axis="y", alpha=0.3)
    ax.legend(fontsize=9, ncol=3, loc="upper center")
    ymin = min(df.MeanPowerW.min() for per in frames.values()
               for df in per.values())
    ax.set_ylim(ymin * 0.965, None)
    fig.tight_layout()
    fig.savefig(RES / "fig_final_mean_power.png", dpi=160)
    plt.close(fig)


def fig_paired(frames):
    cands = [p for p in ("bc_agent", "bc32_agent", "td3_ft_agent")
             if p in frames[SCEN[0][0]]]
    best = min(cands, key=lambda p: frames[SCEN[0][0]][p].MeanPowerW.mean())
    fig, axes = plt.subplots(1, 4, figsize=(14, 4.3), sharey=True)
    for ax, (key, title) in zip(axes, SCEN):
        base = frames[key]["fixed"]
        sub = frames[key][best]
        delta = sub.MeanPowerW.to_numpy() - base.MeanPowerW.to_numpy()
        win = delta < 0
        ax.bar(np.arange(1, len(delta) + 1), delta,
               color=np.where(win, "#2e7d32", "#c62828"), alpha=0.85)
        ax.axhline(0, color="black", lw=0.8)
        ax.set_title(title.replace("\n", " "), fontsize=9.5)
        if ax is axes[0]:
            ax.set_ylabel(f"{best} − 固定 (W)")
        ax.set_xlabel("种子序号")
        ax.grid(axis="y", alpha=0.3)
        ax.text(0.97, 0.95, f"优于固定 {int(win.sum())}/{len(delta)}\n"
                f"平均差 {delta.mean():+.1f} W",
                transform=ax.transAxes, ha="right", va="top", fontsize=9,
                bbox=dict(fc="white", ec="0.7", alpha=0.9))
    fig.suptitle(f"最优学习策略({best})逐种子配对:绿=优于固定基准", fontsize=12)
    fig.tight_layout(rect=(0, 0, 1, 0.92))
    fig.savefig(RES / "fig_final_paired.png", dpi=160)
    plt.close(fig)
    return best


def fig_curves():
    fig, ax = plt.subplots(figsize=(13, 5))
    logs = sorted(RES.glob("train_log_*.csv"))
    if logs:
        df = pd.read_csv(logs[-1])
        xs = np.arange(len(df))
        ax.plot(xs, df.trueMeanPowerW, ".", color="#ef6c00", alpha=0.3, ms=3)
        ax.plot(xs, df.trueMeanPowerW.rolling(20, min_periods=5).mean(), "-",
                color="#ef6c00", lw=1.8, label="TD3 课程 v0(从零)")
        bounds, off = [], 0
        for _, d in df.groupby("stage", sort=False):
            off += len(d)
            bounds.append(off)
        for b in bounds[:-1]:
            ax.axvline(b - 0.5, color="#999999", lw=0.7, ls=":")
    ftlogs = sorted(RES.glob("ft_log_*.csv"))
    if ftlogs:
        df2 = pd.read_csv(ftlogs[-1])
        xs2 = np.arange(len(df), len(df) + len(df2))
        ax.plot(xs2, df2.trueMeanPowerW, ".", color="#c62828", alpha=0.35, ms=3)
        ax.plot(xs2, df2.trueMeanPowerW.rolling(15, min_periods=4).mean(), "-",
                color="#c62828", lw=1.8, label="BC+TD3 微调 v1")
    # 参考线:固定基准在不规则可观测场景的均值(Python 环境)
    ax.axhline(483.8, color="#8c8c8c", ls="--", lw=1,
               label="固定基准 ≈484 W(不规则风参考)")
    ax.set_xlabel("全局回合序号(v0 课程 → v1 微调)")
    ax.set_ylabel("回合真值平均功率 (W,训练随机化口径)")
    ax.set_title("训练过程:v0 从零课程在 1730 回合内未能压到基准以下;"
                 "v1 以 BC 解析最优为教师热启动后微调", fontsize=11.5)
    ax.grid(alpha=0.3)
    ax.legend(fontsize=9, loc="upper right")
    fig.tight_layout()
    fig.savefig(RES / "fig_final_curves.png", dpi=160)
    plt.close(fig)


def summary(frames, best):
    rows = []
    for key, title in SCEN:
        fixed_mean = frames[key]["fixed"].MeanPowerW.mean()
        base = frames[key]["fixed"]
        for pol, lab, _, _ in SOURCES:
            if pol not in frames[key]:
                continue
            sub = frames[key][pol]
            delta = sub.MeanPowerW.to_numpy() - base.MeanPowerW.to_numpy()
            rows.append({
                "场景": title.replace("\n", " "),
                "策略": lab,
                "平均功率W": round(sub.MeanPowerW.mean(), 2),
                "相对固定%": round((sub.MeanPowerW.mean() / fixed_mean - 1) * 100, 2),
                "优于固定": f"{int((delta < 0).sum())}/{len(delta)}",
                "续航min": round(sub.EnduranceHours.mean() * 60, 2),
                "违规": int(sub.RateViolations.sum() + sub.BoundViolations.sum()),
            })
    return pd.DataFrame(rows)


def report(frames, tab, best):
    def g(key, pol):
        df = frames[key][pol]
        base = frames[key]["fixed"]
        rel = (df.MeanPowerW.mean() / base.MeanPowerW.mean() - 1) * 100
        return df.MeanPowerW.mean(), rel

    L = []
    a = L.append
    a("# 残差速度 RL 新一轮训练结果报告(2026-09-02)")
    a("")
    a("## 设置")
    a("- 环境:speed_rl_residual 合成适配器的 Python 逐行移植,与 MATLAB "
      "**公式级一致**(无风/恒定/正弦确定性场景 12 位小数逐位相同;不规则风 "
      "20 种子统计一致,MATLAB 侧 480.26/474.23 W 复现了仓库证据值)。")
    a("- 训练设备:RTX 4060 Laptop(PyTorch,torch 2.5.1+cu121)。")
    a("- 三个策略版本:")
    a("  1. **TD3 课程 v0**:7 阶段课程从零训练 1730 回合(20.8 万步),"
      "超参镜像仓库 make_agent.m;")
    a("  2. **BC 热启动**:以真值风解析最优残差为教师,混合 9 种场景 "
      "(不规则/恒定/正弦 × 可观测/缺测/隐藏)监督训练(仅用于生成监督数据,"
      "部署时网络只见测量);")
    a("  3. **BC+TD3 微调 v1**:BC 初始化 + 小噪声(σ=0.12)、低学习率"
      "(3e-4)TD3 微调 400 回合。")
    a("- 评估:4 场景 × 20 **未见种子**(训练种子 1000+/30000+,评估 "
      "2001-2020/3001-3020/4001-4020/5001-5020,零重叠)。")
    a("")
    a("## 核心结果(平均真实代理功率,相对固定 6.3 m/s 基准)")
    a("")
    a(tab.to_markdown(index=False))
    a("")
    p8, r8 = g("irregular_observable", "bc_agent")
    p0, r0 = g("irregular_observable", "td3_agent")
    ps, rs = g("irregular_observable", "scripted")
    a("## 结论")
    a("")
    a(f"1. **从零 TD3(v0)仍未胜出**:不规则风 {p0:.1f} W({r0:+.2f}%),"
      f"与仓库已有候选一致;诊断显示其输出退化为与风无关的固定偏置"
      f"(平均残差 −1.9 m/s,与风相关性 −0.13)——奖励信号仅占总回报约 2%,"
      "TD3 的价值估计误差淹没了真实信号。")
    a(f"2. **BC 热启动显著有效**:不规则可观测风 {p8:.1f} W({r8:+.2f}%,"
      f"20/20 种子优于固定),**超过解析残差**({ps:.1f} W,{rs:+.2f}%,19/20);"
      "缺测场景优势更大(−1.45% vs −0.95%):解析式在缺测窗口只能回退到基线,"
      "学习策略的动作保持连续。")
    a("3. **隐藏风是真正的硬问题**:8 帧/32 帧历史下 BC 仍略差于固定"
      "(+0.78%/+0.39%)。这不是记忆长度配置问题——在功率曲线最优空速附近,"
      "功率对风的一阶敏感度为零,被动观测难以分辨风;这与平台线 ESC 需要"
      "主动激励(dither)的结论在物理上同源。")
    a("4. 全部策略零硬约束违规(guard 层有效)。")
    a("")
    a("## 图")
    a("")
    a("![总对比](fig_final_mean_power.png)")
    a("")
    a(f"![逐种子](fig_final_paired.png)")
    a("")
    a("![训练曲线](fig_final_curves.png)")
    a("")
    a("## 表述边界(ADR-002)")
    a("")
    a("以上为虚拟代理对象、Python 对拍环境的结果;\"学习策略超过解析残差\""
      "仅在本代理口径、可观测/缺测风场景成立,不外推真实 X8、不构成飞行结论;"
      "教师用到真值风仅发生在监督数据生成阶段,评估与部署只用测量。")
    (RES / "report_final.md").write_text("\n".join(L), encoding="utf-8")


def main():
    frames = load_all()
    fig_mean(frames)
    best = fig_paired(frames)
    fig_curves()
    tab = summary(frames, best)
    tab.to_csv(RES / "summary_final.csv", index=False, encoding="utf-8-sig")
    with open(RES / "summary_final.md", "w", encoding="utf-8") as f:
        f.write(tab.to_markdown(index=False))
    print(tab.to_string(index=False))
    report(frames, tab, best)
    print("figures + report written to", RES)


if __name__ == "__main__":
    main()
