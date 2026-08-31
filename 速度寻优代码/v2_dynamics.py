# -*- coding: utf-8 -*-
"""
V2：加入速度响应（一阶动态）
=============================
在 V1 基础上把"速度闭环"建为一阶惯性环节:

    τ_v · dv/dt = v_ref - v,      τ_v = 2.0 s（演示界面可调）

两个关键点:
  1) 速度不能突变 —— 实际速度平滑跟踪指令（这也天然覆盖了任务书的
     参考值变化率限制: 最大 dv/dt = |v_ref - v|/τ_v，初始偏差 9 m/s
     时约 0.45 m/s/步 < 0.5 m/s/步）；
  2) 功率（代价）按实际速度 v 计算，而非指令值 v_ref —— 注入的扰动
     经过速度闭环后被衰减、延迟，梯度估计信号质量下降，收敛变慢。

仍无噪声、无环境变化。不需要再做一整套飞行 PID，一阶模型即代表
"已有速度闭环"的等效特性。

运行方式:
    python v2_dynamics.py           # 交互式演示窗口
    python v2_dynamics.py --batch   # 无界面: 三初值批量测试 + 存图
    python v2_dynamics.py --test    # 无界面: 演示界面自检截图

验收标准: 收敛 <150 步（可略长于 V1），稳态误差 <0.5 m/s。
"""

import sys
import numpy as np

import esc_core as core

TAU_V_DEFAULT = 2.0      # 速度闭环时间常数 [s]


# ============================================================
# 环境类：V2 一阶动态
# ============================================================
class FirstOrderEnvironment:
    """一阶速度闭环 + 精确代价测量。
    cost_mode: "debug" 调试二次曲线 / "physics" 文献代理功率曲线。"""
    def __init__(self, tau_v=TAU_V_DEFAULT, cost_mode="debug"):
        self.tau_v = tau_v
        self.cost_mode = cost_mode
        if cost_mode == "physics":
            self.model = core.PhysicsPowerModel()
            self.v_star = self.model.v_star_ref        # 6.3 m/s
            self.P_min = float(self.model(self.model.v_star_ref))
        else:
            self.v_star = core.V_STAR_INIT
            self.P_min = 1.0
        self.v = None

    def _cost(self, v):
        if self.cost_mode == "physics":
            return float(self.model(v))
        return core.cost(v, self.v_star)

    def step(self, step_idx, v_ref):
        # 一阶动态: dv/dt = (v_ref - v)/τ_v（隐含变化率限制）
        dv = (np.clip(v_ref, core.V_MIN, core.V_MAX) - self.v) / self.tau_v
        self.v = float(np.clip(self.v + dv * core.DT,
                               core.V_MIN, core.V_MAX))
        # 功率按实际速度 v 计算
        J = self._cost(self.v)
        self.P_true = J
        return self.v, J


# 物理曲线模式推荐配置
PHYS_ESC_KW = dict(k=8.0, warmup=True, dmax=0.2)
PHYS_N = 500


# ============================================================
# 验收评估
# ============================================================
def evaluate(hist, milestone=True):
    end = hist["v_hat"][-40:].mean()
    target = hist["v_star"][0]
    err = abs(end - target)
    ts = core.settle_steps(hist["v_hat"], target, 0.5)
    p_min = hist.get("P_min", 1.0)
    r_mean, _ = core.power_regret(hist["P_true"][-100:],
                                  np.full(100, p_min))
    ok = (err < 0.5 and 0 <= ts < 150) if milestone \
        else (r_mean <= 0.01 and err < 0.5)
    return end, err, ts, r_mean, ok


# ============================================================
# 批处理模式
# ============================================================
def batch(cost_mode="debug"):
    phys = cost_mode == "physics"
    esc_kw = PHYS_ESC_KW if phys else None
    n = PHYS_N if phys else 300
    print(f"=== V2：一阶动态（{'文献代理功率曲线' if phys else '调试曲线'}）===")
    results = {}
    for v0 in (2.0, 10.0, 15.0):
        h = core.run_case(FirstOrderEnvironment(cost_mode=cost_mode),
                          v0, n, esc_kwargs=esc_kw)
        h["P_min"] = FirstOrderEnvironment(cost_mode=cost_mode).P_min
        end, err, ts, r_mean, ok = evaluate(h, milestone=not phys)
        results[v0] = h
        print(f"初始速度 {v0:.1f} → 收敛至 {end:.2f} m/s "
              f"(稳态误差 {err:.2f}, 耗时 {ts} 步); "
              f"稳态功率后悔值 {r_mean:.3%} {'[通过]' if ok else '[未过]'}")
    _plot(results, phys)
    print(f"图像已保存: {'v2_results_phys.png' if phys else 'v2_results.png'}")


def _plot(results, phys=False):
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(2, 2, figsize=(12, 9))
    vv = np.linspace(core.V_MIN, core.V_MAX, 400)
    n = len(next(iter(results.values()))["v"])
    steps = np.arange(n)
    tgt = next(iter(results.values()))["v_star"][0]

    # (1) 目标曲线与轨迹
    ax = axes[0, 0]
    if phys:
        model = core.PhysicsPowerModel()
        ax.plot(vv, model(vv), "k-", lw=1.5, label="P*(v)/P_hover")
        ax.axhline(1.0, color="gray", ls=":", lw=1)
    else:
        ax.plot(vv, core.cost(vv, core.V_STAR_INIT), "k-", lw=1.5,
                label="J_v")
    for v0, h in results.items():
        ax.plot(h["v"][::3], h["J"][::3], ".", ms=2, label=f"v0={v0}")
    ax.axvline(tgt, color="r", ls="--", lw=1)
    ax.set_xlabel("v [m/s]"); ax.set_ylabel("J / P*")
    ax.set_title("目标曲线与收敛轨迹"); ax.legend(fontsize=8)

    # (2) 速度收敛对比
    ax = axes[0, 1]
    for v0, h in results.items():
        ax.plot(steps, h["v"], label=f"v (v0={v0})")
    ax.axhline(tgt, color="r", ls="--")
    ax.set_xlabel("步数"); ax.set_ylabel("v [m/s]")
    ax.set_title("速度收敛对比"); ax.legend(fontsize=8)

    # (3) 图4: v_ref（指令）与 v（实际）对比 —— V2 的核心图
    ax = axes[1, 0]
    h = results[15.0]
    ax.plot(steps, h["v_ref"], color="tab:orange", lw=0.8, alpha=0.8,
            label="v_ref 指令")
    ax.plot(steps, h["v"], color="tab:blue", lw=1.6, label="v 实际")
    ax.axhline(tgt, color="r", ls="--", label="v*")
    ax.set_xlim(0, min(150, n)); ax.set_xlabel("步数"); ax.set_ylabel("v [m/s]")
    ax.set_title("图4: 指令 v_ref 与实际速度 v（可见相位滞后）")
    ax.legend(fontsize=8)

    # (4) 代价 vs 时间
    ax = axes[1, 1]
    for v0, h in results.items():
        ax.plot(steps, h["J"], label=f"v0={v0}")
    ax.set_xlabel("步数"); ax.set_ylabel("J / P*")
    ax.set_title("代价 vs 时间"); ax.legend(fontsize=8)

    fig.tight_layout()
    fig.savefig("v2_results_phys.png" if phys else "v2_results.png", dpi=130)


# ============================================================
# 交互式演示
# ============================================================
def make_demo():
    from demo_kit import EscDemo

    def simulate(p):
        mode = "physics" if p.get("curve", 0.0) >= 0.5 else "debug"
        env = FirstOrderEnvironment(tau_v=p["tau"], cost_mode=mode)
        kw = dict(a=p["a"], w=p["w"], k=p["k"],
                  win=max(10, int(round(np.pi / (p["w"] * core.DT)))))
        if mode == "physics":
            kw.update(warmup=True, dmax=0.2)
        n = PHYS_N if mode == "physics" else 300
        h = core.run_case(env, p["v0"], n, esc_kwargs=kw)
        h["P_min"] = env.P_min
        return h

    def panels(d):
        n = len(d.hist["v"])
        phys = d.sliders["curve"].val >= 0.5
        vv = np.linspace(core.V_MIN, core.V_MAX, 400)
        # --- 面板1: 目标曲线与轨迹 ---
        a1 = d.pax("curve", [0.245, 0.560, 0.355, 0.380])
        if phys:
            m = core.PhysicsPowerModel()
            a1.plot(vv, m(vv), "k-", lw=1.5,
                    label=f"P*(v)（悬停=1, v*={m.v_star_ref}）")
            a1.set_ylim(0.88, 1.35)
        else:
            a1.plot(vv, core.cost(vv, core.V_STAR_INIT), "k-", lw=1.5,
                    label=f"J_v (v*={core.V_STAR_INIT})")
            a1.set_ylim(0.95, 1.65)
        a1.axvline(d.hist["v_star"][0], color="r", ls=":", lw=1)
        d.lines["trail"], = a1.plot([], [], ".", color="tab:purple", ms=2.5)
        d.lines["point"], = a1.plot([], [], "r*", ms=14)
        a1.set_xlim(0, 20)
        a1.set_xlabel("v [m/s]"); a1.set_ylabel("J / P*")
        a1.set_title("目标曲线与寻优轨迹", fontsize=10)
        a1.legend(fontsize=8, loc="upper center")

        # --- 面板2: v_ref 与 v 对比（V2 核心: 相位滞后）---
        a2 = d.pax("vel", [0.635, 0.560, 0.350, 0.380])
        d.lines["v_ref"], = a2.plot([], [], color="tab:orange", lw=0.8,
                                    alpha=0.75, label="v_ref 指令")
        d.lines["v"],     = a2.plot([], [], color="tab:blue", lw=1.4,
                                    label="v 实际")
        d.lines["v_hat"], = a2.plot([], [], color="tab:green", lw=1.0,
                                    ls="--", label="v_hat 估计")
        d.lines["v_star"], = a2.plot([], [], color="r", ls="--", lw=1.2,
                                     label="v* 真实最优")
        a2.set_xlim(0, n); a2.set_ylim(-0.5, 20.5)
        a2.set_xlabel("步数"); a2.set_ylabel("v [m/s]")
        a2.set_title("指令与实际速度对比（蓝滞后于橙 = τ_v 效应）",
                     fontsize=10)
        a2.legend(fontsize=8, loc="center right")

        # --- 面板3: 代价 vs 步数 ---
        a3 = d.pax("cost", [0.245, 0.070, 0.355, 0.380])
        d.lines["J"], = a3.plot([], [], color="tab:blue", lw=1.0)
        a3.set_xlim(0, n); a3.set_ylim(0.88, 1.75)
        a3.set_xlabel("步数"); a3.set_ylabel("J / P*")
        a3.set_title("代价 vs 步数", fontsize=10)

        # --- 面板4: 估计误差 ---
        a4 = d.pax("err", [0.635, 0.070, 0.350, 0.380])
        d.lines["err"], = a4.semilogy([], [], color="tab:green", lw=1.2)
        a4.axhline(0.5, color="r", ls=":", lw=1)
        a4.text(n - 2, 0.5 * 1.15, "容差 ±0.5", fontsize=8, color="r",
                ha="right")
        a4.set_xlim(0, n); a4.set_ylim(1e-3, 30)
        a4.set_xlabel("步数"); a4.set_ylabel("|v_hat - v*| [m/s]")
        a4.set_title("估计误差（对数轴）", fontsize=10)

    def report(h):
        phys = h.get("P_min", 1.0) < 1.0
        end, err, ts, r_mean, ok = evaluate(h, milestone=not phys)
        crit = "稳态误差<0.5, <150 步" if not phys else "后悔值≤1%"
        return [f"V2 验收({('物理曲线' if phys else '调试曲线')}): {crit}",
                f"稳态误差 {err:.2f} m/s, 入带 {ts if ts>=0 else -1} 步",
                f"稳态后悔值 {r_mean:.3%}  "
                f"{'[通过]' if r_mean <= 0.01 else '[未过]'}"]

    demo = EscDemo(
        "V2 一阶动态 · ESC 速度寻优演示",
        sliders=[("curve", "曲线0调试/1物理", 0, 1, 0, 1),
                 ("v0", "初始速度 v0", 0.0, 20.0, 2.0),
                 ("tau", "时间常数 τ_v", 0.5, 6.0, TAU_V_DEFAULT),
                 ("a", "扰动幅值 a", 0.1, 1.5, 0.5),
                 ("w", "扰动频率 ω", 0.2, 2.0, 0.5),
                 ("k", "学习率 k", 2.0, 60.0, 22.0),
                 ("spd", "播放速度", 1, 10, 2)],
        simulate=simulate, panels=panels, report=report)

    demo.sliders["curve"].on_changed(
        lambda val: demo.sliders["k"].set_val(8.0 if val >= 0.5 else 22.0))
    return demo


# ============================================================
# 入口
# ============================================================
def main():
    if "--batch" in sys.argv:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        batch("physics" if "--phys" in sys.argv else "debug")
    elif "--test" in sys.argv:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from demo_kit import snap
        snap(make_demo(), "v2_demo_test.png")
    else:
        make_demo()
        import matplotlib.pyplot as plt
        plt.show()


if __name__ == "__main__":
    main()
