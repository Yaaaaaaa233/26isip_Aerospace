# -*- coding: utf-8 -*-
"""
V3：环境变化与扰动（鲁棒性验证）
=================================
在 V2 一阶动态基础上逐项加入环境因素（演示界面均可调，置 0 可单项隔离）:

  1) 最优点跳变: 第 200 步 v* 从 6 → 9 m/s（模拟风场/载荷变化）
  2) 测量噪声:   代价测量叠加 2% 高斯白噪声（相对幅值）
  3) 测量延迟:   功率反馈延迟 5 步 = 0.5 s（路线图 M1 口径）
  4) 变化率限制: 已由 V2 一阶模型覆盖

验收标准: v* 跳变后重新收敛至新最优（允许误差 <0.7 m/s）；
噪声条件下不持续振荡。

运行方式:
    python v3_robust.py           # 交互式演示窗口
    python v3_robust.py --batch   # 无界面: 标准场景测试 + 存图
    python v3_robust.py --test    # 无界面: 演示界面自检截图

演示界面专项操作:
  * "跳变步"滑块调到 >500 可观察无跳变时的纯噪声行为
  * 噪声/延迟滑块置 0 可观察单项因素的影响
  * "换噪声"按钮重新抽取噪声序列
"""

import sys
import numpy as np

import esc_core as core

TAU_V_DEFAULT = 2.0        # 速度闭环时间常数 [s]
NOISE_STD_DEFAULT = 0.02   # 代价测量噪声（相对标准差）
DELAY_DEFAULT = 5          # 功率反馈延迟 [步]（M1 口径 0.5s = 5×0.1s）
JUMP_STEP_DEFAULT = 200    # v* 跳变发生的步数
N_STEPS = 500              # 总步数（含跳变）


# ============================================================
# 环境类：V3 环境变化
# ============================================================
class RobustEnvironment:
    """V2 一阶动态 + v* 跳变 + 测量噪声 + 测量延迟。
    cost_mode: "debug" 调试二次曲线 / "physics" 文献代理功率曲线
    （物理模式下跳变后的最优值 9 m/s 通过曲线整体平移实现）。"""
    def __init__(self, tau_v=TAU_V_DEFAULT, noise_std=NOISE_STD_DEFAULT,
                 delay=DELAY_DEFAULT, jump_step=JUMP_STEP_DEFAULT,
                 seed=1, cost_mode="debug"):
        self.tau_v = tau_v
        self.noise_std = noise_std
        self.delay = delay
        self.jump_step = jump_step
        self.rng = np.random.default_rng(seed)
        self.cost_mode = cost_mode
        if cost_mode == "physics":
            self.model = core.PhysicsPowerModel()
            self.v_star = self.model.v_star_ref        # 6.3
            self.P_min = float(self.model(self.model.v_star_ref))
        else:
            self.v_star = core.V_STAR_INIT             # 6.0
            self.P_min = 1.0
        self.v = None
        self.meas_buf = []               # 延迟用 FIFO

    def _cost(self, v):
        if self.cost_mode == "physics":
            return float(self.model(v, v_star_eff=self.v_star))
        return core.cost(v, self.v_star)

    def step(self, step_idx, v_ref):
        # --- 1) 最优点跳变 ---
        if step_idx == self.jump_step:
            self.v_star = core.V_STAR_JUMP
        # --- 2) 一阶速度动态（含变化率限制）---
        dv = (np.clip(v_ref, core.V_MIN, core.V_MAX) - self.v) / self.tau_v
        self.v = float(np.clip(self.v + dv * core.DT,
                               core.V_MIN, core.V_MAX))
        # 功率按实际速度 v 计算并叠加测量噪声
        J = self._cost(self.v)
        self.P_true = J               # 无噪声真实值（后悔值统计用）
        if self.noise_std > 0:
            J *= 1.0 + self.rng.normal(0.0, self.noise_std)
        # --- 3) 测量延迟（FIFO）---
        if self.delay > 0:
            self.meas_buf.append(J)
            J_m = self.meas_buf.pop(0) if len(self.meas_buf) > self.delay else J
        else:
            J_m = J
        return self.v, J_m


# 物理曲线模式推荐配置
PHYS_ESC_KW = dict(k=8.0, warmup=True, dmax=0.2)


# ============================================================
# 验收评估
# ============================================================
def evaluate(hist, jump_step=JUMP_STEP_DEFAULT):
    v_hat = hist["v_hat"]
    jumped = jump_step < len(v_hat)
    post_err = abs(v_hat[-30:].mean() - core.V_STAR_JUMP) if jumped else \
        abs(v_hat[-30:].mean() - core.V_STAR_INIT)
    ts = core.settle_steps(v_hat, core.V_STAR_JUMP, 0.7,
                           start=jump_step) if jumped else -1
    std = hist["v"][-50:].std() / core.V_STAR_JUMP
    ok = post_err < 0.7 and ts >= 0 and std < 0.05
    return post_err, ts, std, ok


# ============================================================
# 批处理模式
# ============================================================
def batch(cost_mode="debug"):
    phys = cost_mode == "physics"
    esc_kw = PHYS_ESC_KW if phys else None
    env = RobustEnvironment(cost_mode=cost_mode)
    v0 = env.v_star                       # 从当前最优值出发
    print("=== V3：环境变化"
          f"（{'文献代理功率曲线' if phys else '调试曲线'}）===")
    print(f"v*跳变：{env.v_star:.1f} → {core.V_STAR_JUMP} m/s "
          f"(t={JUMP_STEP_DEFAULT}步)")
    h = core.run_case(env, v0, N_STEPS, esc_kwargs=esc_kw)
    h["P_min"] = env.P_min
    pre = h["v_hat"][JUMP_STEP_DEFAULT-30:JUMP_STEP_DEFAULT].mean()
    post_err, ts, std, ok = evaluate(h)
    # 跳变后稳态后悔值（噪声工况 ≤3%）
    r_mean, _ = core.power_regret(h["P_true"][-100:], np.full(100, env.P_min))
    print(f"跳变前稳态 {pre:.2f} m/s；跳变后稳态误差 {post_err:.2f} m/s "
          f"(重新收敛耗时 {ts - JUMP_STEP_DEFAULT if ts >= 0 else -1} 步)")
    print(f"噪声标准差：{NOISE_STD_DEFAULT:.2f}，"
          f"稳态速度波动 {std*100:.1f}%，{'达标' if ok else '未达标'}")
    print(f"跳变后稳态功率后悔值 {r_mean:.2%} "
          f"{'[通过≤3%]' if r_mean <= 0.03 else '[未过]'}")
    _plot(h, phys)
    print(f"图像已保存: {'v3_results_phys.png' if phys else 'v3_results.png'}")


def _plot(h, phys=False):
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 2, figsize=(13, 5))
    steps = np.arange(len(h["v"]))
    vv = np.linspace(core.V_MIN, core.V_MAX, 400)
    v0_star = h["v_star"][0]

    # 图5: v* 跳变前后的速度演化
    ax = axes[0]
    ax.plot(steps, h["v"], lw=0.8, label="实际速度 v")
    ax.plot(steps, h["v_hat"], lw=1.2, label="ESC 估计 v_hat")
    ax.step(steps, h["v_star"], "r--", where="post", label="v*（真实最优）")
    ax.axvline(JUMP_STEP_DEFAULT, color="gray", ls=":")
    ax.annotate(f"v* 跳变 {v0_star:.0f}→9", xy=(JUMP_STEP_DEFAULT, 9),
                xytext=(JUMP_STEP_DEFAULT + 60, 4.5),
                arrowprops=dict(arrowstyle="->"))
    ax.set_xlabel("步数"); ax.set_ylabel("v [m/s]")
    ax.set_title("图5: v*跳变前后的速度演化（含2%噪声、0.5s延迟）")
    ax.legend(fontsize=9)

    # 双目标曲线与测量点迁移
    ax = axes[1]
    if phys:
        m = core.PhysicsPowerModel()
        ax.plot(vv, m(vv), "k-", lw=1.5, label=f"P*(v) (v*={v0_star})")
        ax.plot(vv, m(vv, v_star_eff=core.V_STAR_JUMP), "--", color="darkred",
                lw=1.5, label=f"P*(v) (v*={core.V_STAR_JUMP})")
        ax.set_ylim(0.88, 1.35); ax.set_ylabel("P / P_hover")
    else:
        ax.plot(vv, core.cost(vv, v0_star), "k-", lw=1.5,
                label=f"J_v (v*={v0_star})")
        ax.plot(vv, core.cost(vv, core.V_STAR_JUMP), "--", color="darkred",
                lw=1.5, label=f"J_v (v*={core.V_STAR_JUMP})")
        ax.set_ylim(0.95, 1.65); ax.set_ylabel("J_v")
    ax.plot(h["v"][::4], h["J"][::4], ".", color="tab:purple", ms=2)
    ax.set_xlim(0, 20)
    ax.set_xlabel("v [m/s]")
    ax.set_title("测量点从旧谷底迁移到新谷底（散布=噪声）")
    ax.legend(fontsize=9)

    fig.tight_layout()
    fig.savefig("v3_results_phys.png" if phys else "v3_results.png", dpi=130)


# ============================================================
# 交互式演示
# ============================================================
def make_demo():
    from demo_kit import EscDemo
    state = {"seed": 1}      # "换噪声"按钮递增

    def reseed():
        state["seed"] += 1

    def simulate(p):
        mode = "physics" if p.get("curve", 0.0) >= 0.5 else "debug"
        env = RobustEnvironment(tau_v=p["tau"], noise_std=p["noise"],
                                delay=int(p["delay"]),
                                jump_step=int(p["jump"]),
                                seed=state["seed"], cost_mode=mode)
        kw = dict(a=p["a"], w=p["w"], k=p["k"],
                  win=max(10, int(round(np.pi / (p["w"] * core.DT)))))
        if mode == "physics":
            kw.update(warmup=True, dmax=0.2)
        h = core.run_case(env, p["v0"], N_STEPS, esc_kwargs=kw)
        h["P_min"] = env.P_min
        return h

    def panels(d):
        phys = d.sliders["curve"].val >= 0.5
        vv = np.linspace(core.V_MIN, core.V_MAX, 400)
        # --- 面板1: 双目标曲线与轨迹 ---
        a1 = d.pax("curve", [0.245, 0.560, 0.355, 0.380])
        if phys:
            m = core.PhysicsPowerModel()
            a1.plot(vv, m(vv), "k-", lw=1.5,
                    label=f"P*(v) (v*={m.v_star_ref})")
            a1.set_ylim(0.88, 1.35); a1.set_ylabel("P / P_hover")
        else:
            a1.plot(vv, core.cost(vv, core.V_STAR_INIT), "k-", lw=1.5,
                    label=f"J_v (v*={core.V_STAR_INIT})")
            a1.set_ylim(0.95, 1.65); a1.set_ylabel("J_v")
        d.curve2, = a1.plot([], [], "--", color="darkred", lw=1.5,
                            alpha=0.0, label=f"目标曲线 (v*={core.V_STAR_JUMP})")
        d.lines["trail"], = a1.plot([], [], ".", color="tab:purple", ms=2.5)
        d.lines["point"], = a1.plot([], [], "r*", ms=14)
        a1.set_xlim(0, 20)
        a1.set_xlabel("v [m/s]")
        a1.set_title("双目标曲线与测量点（跳变后出现红虚线）", fontsize=10)
        a1.legend(fontsize=8, loc="upper center")

        # --- 面板2: 速度演化与 v* 跳变 ---
        a2 = d.pax("vel", [0.635, 0.560, 0.350, 0.380])
        d.lines["v_ref"], = a2.plot([], [], color="tab:orange", lw=0.7,
                                    alpha=0.6, label="v_ref 指令")
        d.lines["v"],     = a2.plot([], [], color="tab:blue", lw=0.9,
                                    label="v 实际")
        d.lines["v_hat"], = a2.plot([], [], color="tab:green", lw=1.2,
                                    label="v_hat 估计")
        d.lines["v_star"], = a2.plot([], [], color="r", ls="--", lw=1.2,
                                     drawstyle="steps-post",
                                     label="v* 真实最优")
        d.jump_line = int(d.sliders["jump"].val)
        a2.axvline(d.jump_line, color="gray", ls=":", lw=1)
        a2.set_xlim(0, N_STEPS); a2.set_ylim(-0.5, 20.5)
        a2.set_xlabel("步数"); a2.set_ylabel("v [m/s]")
        a2.set_title("速度演化：v* 跳变后重新跟踪", fontsize=10)
        a2.legend(fontsize=8, loc="center right")

        # --- 面板3: 代价（含噪声毛刺）---
        a3 = d.pax("cost", [0.245, 0.070, 0.355, 0.380])
        d.lines["J"], = a3.plot([], [], color="tab:blue", lw=0.8)
        a3.axvline(d.jump_line, color="gray", ls=":", lw=1)
        a3.set_xlim(0, N_STEPS)
        a3.set_ylim(0.88 if phys else 0.95, 1.75)
        a3.set_xlabel("步数"); a3.set_ylabel("J / P*")
        a3.set_title("代价测量（毛刺 = 2% 噪声）", fontsize=10)

        # --- 面板4: 估计误差 ---
        a4 = d.pax("err", [0.635, 0.070, 0.350, 0.380])
        d.lines["err"], = a4.semilogy([], [], color="tab:green", lw=1.2)
        a4.axhline(0.7, color="r", ls=":", lw=1)
        a4.text(N_STEPS - 5, 0.7 * 1.15, "容差 ±0.7", fontsize=8,
                color="r", ha="right")
        a4.set_xlim(0, N_STEPS); a4.set_ylim(1e-3, 30)
        a4.set_xlabel("步数"); a4.set_ylabel("|v_hat - v*| [m/s]")
        a4.set_title("估计误差（对数轴）", fontsize=10)

    def on_frame(d, i):
        # 跳变发生后显示新目标曲线
        if hasattr(d, "curve2"):
            vis = i >= d.jump_line
            d.curve2.set_alpha(0.7 if vis else 0.0)
            if vis:
                vv = np.linspace(core.V_MIN, core.V_MAX, 400)
                phys = d.sliders["curve"].val >= 0.5
                if phys:
                    m = core.PhysicsPowerModel()
                    d.curve2.set_data(
                        vv, m(vv, v_star_eff=core.V_STAR_JUMP))
                else:
                    d.curve2.set_data(
                        vv, core.cost(vv, core.V_STAR_JUMP))

    def report(h):
        post_err, ts, std, ok = evaluate(h, jump_step=d_jump(h))
        ts_txt = ts - d_jump(h) if ts >= 0 else -1
        p_min = h.get("P_min", 1.0)
        r_mean, _ = core.power_regret(h["P_true"][-100:],
                                      np.full(100, p_min))
        return [f"V3 验收: 跳变后误差<0.7, 无持续振荡",
                f"跳变后稳态误差 {post_err:.2f}  "
                f"{'[通过]' if post_err<0.7 else '[未过]'}",
                f"跳变后耗时 {ts_txt} 步",
                f"稳态波动 {std*100:.1f}%, 后悔值 {r_mean:.2%}  "
                f"{'[通过]' if std<0.05 and r_mean<=0.03 else '[未过]'}"]

    def d_jump(h):
        # 跳变步 = hist 中 v_star 首次变化的位置（与滑块一致）
        ch = np.where(h["v_star"] != h["v_star"][0])[0]
        return int(ch[0]) if len(ch) else len(h["v"])

    demo = EscDemo(
        "V3 环境变化 · ESC 速度寻优演示",
        sliders=[("curve", "曲线0调试/1物理", 0, 1, 0, 1),
                 ("v0", "初始速度 v0", 0.0, 20.0, 6.0),
                 ("tau", "时间常数 τ_v", 0.5, 6.0, TAU_V_DEFAULT),
                 ("noise", "噪声σ(相对)", 0.0, 0.08, NOISE_STD_DEFAULT),
                 ("delay", "测量延迟[步]", 0, 10, DELAY_DEFAULT),
                 ("jump", "跳变步(>500关)", 50, 600, JUMP_STEP_DEFAULT),
                 ("a", "扰动幅值 a", 0.1, 1.5, 0.5),
                 ("w", "扰动频率 ω", 0.2, 2.0, 0.5),
                 ("k", "学习率 k", 2.0, 60.0, 22.0),
                 ("spd", "播放速度", 1, 10, 2)],
        simulate=simulate, panels=panels, report=report,
        on_frame=on_frame, reseed_fn=reseed)

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
        snap(make_demo(), "v3_demo_test.png")
    else:
        make_demo()
        import matplotlib.pyplot as plt
        plt.show()


if __name__ == "__main__":
    main()
