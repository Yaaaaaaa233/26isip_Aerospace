# -*- coding: utf-8 -*-
"""
V1：静态对象上的 ESC 在线寻优（基础验证）
=========================================
对象模型（人为设计的调试曲线，非 X8 实测）:
    J_v(v) = 1 + 0.3·((v - v*)/10)²,  v ∈ [0, 20] m/s,  v* = 6 m/s
    v* 只存在于环境内部，ESC 算法不可见。

对象特性: 静态 —— 指令 v_ref 即时生效（v ≡ v_ref），无动态、无噪声、
无延迟。本版本回答的唯一问题: "ESC 这套机制能不能找到谷底？"
若 V1 不收敛，问题必在算法实现本身，与后面版本无关。

运行方式:
    python v1_static.py           # 交互式演示窗口
    python v1_static.py --batch   # 无界面: 三初值批量测试 + 控制台统计 + 存图
    python v1_static.py --test    # 无界面: 演示界面自检截图

验收标准: 从 v0 = 2 / 10 / 15 m/s 启动均收敛至 6±0.5 m/s，且 <100 步。
"""

import sys
import numpy as np

import esc_core as core


# ============================================================
# 环境类：V1 静态对象
# ============================================================
class StaticEnvironment:
    """静态对象: 速度即时跟踪指令，代价精确可测。

    cost_mode:
      "debug"   调试二次曲线 J_v = 1+0.3((v-6)/10)²（任务书 M0 口径）
      "physics" 文献式代理功率曲线 PhysicsPowerModel（悬停=1，最低
                0.913 @6.3 m/s），验证"换曲线不重写优化器"
    """
    def __init__(self, cost_mode="debug"):
        self.cost_mode = cost_mode
        if cost_mode == "physics":
            self.model = core.PhysicsPowerModel()
            self.v_star = self.model.v_star_ref        # 6.3 m/s
            self.P_min = float(self.model(self.model.v_star_ref))  # 0.913
        else:
            self.v_star = core.V_STAR_INIT             # 6 m/s
            self.P_min = 1.0
        self.v = None                    # 实际速度（run_case 负责初始化）

    def step(self, step_idx, v_ref):
        self.v = float(np.clip(v_ref, core.V_MIN, core.V_MAX))
        if self.cost_mode == "physics":
            J = float(self.model(self.v))
        else:
            J = core.cost(self.v, self.v_star)
        self.P_true = J
        return self.v, J


# 物理曲线模式的推荐配置（曲线更陡: 学习率减小 + 开启预热/限幅保护）
PHYS_ESC_KW = dict(k=8.0, warmup=True, dmax=0.2)
PHYS_N = 500


# ============================================================
# 验收评估
# ============================================================
def evaluate(hist, milestone=True):
    """返回 (末段均值, 入带步数, 后悔值, 是否达标)。
    milestone=True 用 M0 口径(<100步)；物理曲线模式用后悔值口径(≤1%)。"""
    end = hist["v_hat"][-40:].mean()
    target = hist["v_star"][0]
    ts = core.settle_steps(hist["v_hat"], target, 0.5)
    p_min = hist.get("P_min", 1.0)
    r_mean, _ = core.power_regret(hist["P_true"][-100:],
                                  np.full(100, p_min))
    ok = (ts < 100 and abs(end - target) < 0.5) if milestone \
        else (r_mean <= 0.01 and abs(end - target) < 0.5)
    return end, ts, r_mean, ok


# ============================================================
# 批处理模式
# ============================================================
def batch(cost_mode="debug"):
    phys = cost_mode == "physics"
    esc_kw = PHYS_ESC_KW if phys else None
    n = PHYS_N if phys else 300
    print(f"=== V1：静态对象（{'文献代理功率曲线' if phys else '调试曲线'}）===")
    results = {}
    for v0 in (2.0, 10.0, 15.0):
        h = core.run_case(StaticEnvironment(cost_mode), v0, n,
                          esc_kwargs=esc_kw)
        h["P_min"] = StaticEnvironment(cost_mode).P_min
        end, ts, r_mean, ok = evaluate(h, milestone=not phys)
        results[v0] = h
        print(f"初始速度 {v0:.1f} → 收敛至 {end:.2f} m/s (目标 "
              f"{h['v_star'][0]:.1f}, 入带 {ts if ts>=0 else -1} 步); "
              f"稳态功率后悔值 {r_mean:.3%} "
              f"{'[通过]' if ok else '[未过]'}")
    _plot(results, phys)
    print(f"图像已保存: {'v1_results_phys.png' if phys else 'v1_results.png'}")


def _plot(results, phys=False):
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 3, figsize=(16, 4.5))
    n = len(next(iter(results.values()))["v"])
    steps = np.arange(n)
    vv = np.linspace(core.V_MIN, core.V_MAX, 400)
    tgt = next(iter(results.values()))["v_star"][0]

    # 图1: 完整曲线 + 三条收敛轨迹
    if phys:
        model = core.PhysicsPowerModel()
        axes[0].plot(vv, model(vv), "k-", lw=1.5, label="P*(v)/P_hover")
        axes[0].axhline(1.0, color="gray", ls=":", lw=1, label="悬停基准")
    else:
        axes[0].plot(vv, core.cost(vv, core.V_STAR_INIT), "k-", lw=1.5,
                     label="J_v")
    for v0, h in results.items():
        axes[0].plot(h["v"][::3], h["J"][::3], ".", ms=2, label=f"v0={v0}")
        axes[0].plot(h["v"][0], h["J"][0], "*", ms=14)    # 起点
        axes[0].plot(h["v"][-1], h["J"][-1], "s", ms=9)   # 终点
    axes[0].axvline(tgt, color="r", ls="--", lw=1)
    axes[0].set_xlabel("v [m/s]"); axes[0].set_ylabel("J / P*")
    axes[0].set_title("图1: 目标曲线与三条收敛轨迹"); axes[0].legend(fontsize=8)

    # 图2: 速度 vs 时间
    for v0, h in results.items():
        axes[1].plot(steps, h["v"], label=f"v0={v0}")
    axes[1].axhline(tgt, color="r", ls="--")
    axes[1].set_xlabel("步数"); axes[1].set_ylabel("v [m/s]")
    axes[1].set_title("图2: 速度 vs 时间"); axes[1].legend()

    # 图3: 代价 vs 时间
    for v0, h in results.items():
        axes[2].plot(steps, h["J"], label=f"v0={v0}")
    axes[2].set_xlabel("步数"); axes[2].set_ylabel("J / P*")
    axes[2].set_title("图3: 代价 vs 时间"); axes[2].legend()

    fig.tight_layout()
    fig.savefig("v1_results_phys.png" if phys else "v1_results.png", dpi=130)


# ============================================================
# 交互式演示
# ============================================================
def make_demo():
    from demo_kit import EscDemo

    def simulate(p):
        mode = "physics" if p.get("curve", 0.0) >= 0.5 else "debug"
        env = StaticEnvironment(mode)
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
        mode = "physics" if d.sliders["curve"].val >= 0.5 else "debug"
        vv = np.linspace(core.V_MIN, core.V_MAX, 400)
        # --- 面板1: 目标曲线与轨迹 ---
        a1 = d.pax("curve", [0.245, 0.560, 0.355, 0.380])
        if mode == "physics":
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
        a1.set_title("目标曲线与寻优轨迹（紫点=测量值，红星=当前）",
                     fontsize=10)
        a1.legend(fontsize=8, loc="upper center")

        # --- 面板2: 速度演化（静态对象 v ≡ v_ref，故只画 v）---
        a2 = d.pax("vel", [0.635, 0.560, 0.350, 0.380])
        d.lines["v"],     = a2.plot([], [], color="tab:blue", lw=1.2,
                                    label="v (≡ v_ref, 静态对象)")
        d.lines["v_hat"], = a2.plot([], [], color="tab:green", lw=1.2,
                                    ls="--", label="v_hat 估计")
        d.lines["v_star"], = a2.plot([], [], color="r", ls="--", lw=1.2,
                                     label="v* 真实最优")
        a2.set_xlim(0, n); a2.set_ylim(-0.5, 20.5)
        a2.set_xlabel("步数"); a2.set_ylabel("v [m/s]")
        a2.set_title("速度演化", fontsize=10)
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
        end, ts, r_mean, ok = evaluate(h, milestone=not phys)
        crit = "收敛至 6±0.5, <100 步" if not phys else "后悔值≤1%"
        res = [f"V1 验收({('物理曲线' if phys else '调试曲线')}): {crit}",
               f"终值均值 {end:.2f} (目标 {h['v_star'][0]:.1f})",
               f"入带耗时 {ts if ts>=0 else -1} 步",
               f"稳态后悔值 {r_mean:.3%}  "
               f"{'[通过]' if r_mean <= 0.01 else '[未过]'}"]
        return res

    demo = EscDemo(
        "V1 静态对象 · ESC 速度寻优演示",
        sliders=[("curve", "曲线0调试/1物理", 0, 1, 0, 1),
                 ("v0", "初始速度 v0", 0.0, 20.0, 2.0),
                 ("a", "扰动幅值 a", 0.1, 1.5, 0.5),
                 ("w", "扰动频率 ω", 0.2, 2.0, 0.5),
                 ("k", "学习率 k", 2.0, 60.0, 22.0),
                 ("spd", "播放速度", 1, 10, 2)],
        simulate=simulate, panels=panels, report=report)

    # 切换曲线时自动把学习率切到该曲线的推荐值（22 ↔ 10）
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
        snap(make_demo(), "v1_demo_test.png")
    else:
        make_demo()
        import matplotlib.pyplot as plt
        plt.show()


if __name__ == "__main__":
    main()
