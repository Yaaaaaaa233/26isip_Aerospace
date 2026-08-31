# -*- coding: utf-8 -*-
"""
通用 ESC 演示界面框架
======================
三个版本（v1/v2/v3）的交互界面共用此框架，各自只提供:
  * sliders   滑块定义        [(key, 标签, 下限, 上限, 初值), ...]
  * simulate  仿真函数        fn(params) -> hist（run_case 的返回格式）
  * panels    面板构建函数    fn(demo) —— 用 demo.pax(key, rect) 取子图轴，
                               向 demo.lines 写入标准命名的 Line2D
  * report    验收结论函数    fn(hist) -> [str, ...]
  * on_frame  每帧额外回调    fn(i)（可选，如 V3 跳变后显示新曲线）

标准线条命名（update 按名字自动喂数据，缺哪个就不画哪个）:
  trail  J-v 平面上的历史测量点     point  当前测量点（红星）
  v / v_ref / v_hat / v_star        速度演化各曲线
  J     代价随步数曲线              err   |v_hat - v*| 对数误差曲线
  P_true / P_opt                    真实功率与离线最优功率曲线
  regret  功率后悔值 (P_true-P_opt)/P_opt 对数曲线

默认打开交互窗口；配合 --test 参数可无界面渲染若干帧存图自检。
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from matplotlib.widgets import Button, Slider


class EscDemo:
    def __init__(self, title, sliders, simulate, panels, report,
                 on_frame=None, reseed_fn=None):
        self.simulate = simulate
        self.panels_fn = panels
        self.report_fn = report
        self.on_frame = on_frame
        self.reseed_fn = reseed_fn          # "换噪声"按钮回调
        self.playing = True
        self.i = 0
        self.total = 0
        self._drawn = -1
        self._axes_cache = {}               # 面板轴缓存（rect -> Axes）
        self.lines = {}                     # 标准命名线条，panels 负责创建

        self.fig = plt.figure(title, figsize=(14, 8))
        self._build_controls(sliders)
        self.recompute()
        self.anim = FuncAnimation(self.fig, self.update,
                                  frames=self._frame_gen, interval=30,
                                  cache_frame_data=False)

    # ------------------------------------------------------------
    # 控制面板（左列）
    # ------------------------------------------------------------
    def _build_controls(self, sliders):
        # 顶部留白给标题；滑块自上而下排布，间距随数量自适应
        n = len(sliders)
        y_top, y_bot = 0.795, 0.505
        step = (y_top - y_bot) / max(n - 1, 1) if n > 1 else 0
        self.sliders = {}
        for idx, spec in enumerate(sliders):
            key, label, lo, hi, init = spec[:5]
            valstep = spec[5] if len(spec) > 5 else None   # 可选离散步进
            y = y_top - idx * step
            ax = self.fig.add_axes([0.050, y, 0.150, 0.018])
            s = Slider(ax, label, lo, hi, valinit=init, valstep=valstep)
            if key != "spd":                # 播放速度以外的滑块改动即重算
                s.on_changed(lambda _v: self.recompute())
            self.sliders[key] = s

        y_btn1 = y_bot - 0.075
        y_btn2 = y_bot - 0.145
        self.btn_run = self._button(0.030, y_btn1, 0.080, "暂停", self._on_run)
        self.btn_rst = self._button(0.120, y_btn1, 0.075, "重置", self._on_reset)
        self.btn_end = self._button(0.030, y_btn2, 0.080, "至末尾", self._on_end)
        if self.reseed_fn is not None:
            self._button(0.120, y_btn2, 0.075, "换噪声", self._on_reseed)

        self.ax_status = self.fig.add_axes([0.015, 0.030, 0.19, y_btn2 - 0.07])
        self.ax_status.axis("off")

    def _button(self, x, y, w, label, cb):
        ax = self.fig.add_axes([x, y, w, 0.045])
        btn = Button(ax, label)
        btn.label.set_fontsize(9)
        btn.on_clicked(cb)
        return btn

    def pax(self, key, rect):
        """取（或首次创建）子图轴并清空内容 —— panels 构建器专用。"""
        if key not in self._axes_cache:
            self._axes_cache[key] = self.fig.add_axes(rect)
        ax = self._axes_cache[key]
        ax.clear()
        return ax

    # ------------------------------------------------------------
    # 事件回调
    # ------------------------------------------------------------
    def _on_run(self, _e):
        self.playing = not self.playing
        self.btn_run.label.set_text("暂停" if self.playing else "运行")

    def _on_reset(self, _e):
        self.i = 0
        self.update(0, force=True)

    def _on_end(self, _e):
        self.i = self.total
        self.update(self.total, force=True)

    def _on_reseed(self, _e):
        self.reseed_fn()
        self.recompute()

    def _frame_gen(self):
        while True:
            s = self.sliders.get("spd")
            spd = max(1, int(s.val)) if s is not None else 2
            if self.playing and self.i < self.total:
                self.i = min(self.i + spd, self.total)
            yield self.i

    # ------------------------------------------------------------
    # 重算与逐帧绘制
    # ------------------------------------------------------------
    def recompute(self):
        params = {k: s.val for k, s in self.sliders.items()}
        self.hist = self.simulate(params)
        self.total = len(self.hist["v"]) - 1
        self.i = 0
        self.lines = {}
        self.panels_fn(self)                 # 重建面板内容与线条
        self._report = self.report_fn(self.hist)
        self.update(0, force=True)

    def update(self, i=None, force=False):
        if i is None:
            i = self.i
        if not force and i == self._drawn:
            return
        self._drawn = i
        h = self.hist
        x = np.arange(len(h["v"]))
        sl = slice(0, i + 1)
        err = np.maximum(np.abs(h["v_hat"] - h["v_star"]), 1e-3)
        regret = None
        if "P_opt" in h:
            with np.errstate(divide="ignore", invalid="ignore"):
                regret = np.maximum(
                    np.abs(h.get("P_true", h["J"]) - h["P_opt"])
                    / np.maximum(h["P_opt"], 1e-9), 1e-4)

        for name, ln in self.lines.items():
            if name == "trail":
                ln.set_data(h["v"][sl], h["J"][sl])
            elif name == "point":
                ln.set_data([h["v"][i]], [h["J"][i]])
            elif name == "v":
                ln.set_data(x[sl], h["v"][sl])
            elif name == "v_ref":
                ln.set_data(x[sl], h["v_ref"][sl])
            elif name == "v_hat":
                ln.set_data(x[sl], h["v_hat"][sl])
            elif name == "v_star":
                ln.set_data(x[sl], h["v_star"][sl])
            elif name == "J":
                ln.set_data(x[sl], h["J"][sl])
            elif name == "err":
                ln.set_data(x[sl], err[sl])
            elif name == "P_true":
                ln.set_data(x[sl], h.get("P_true", h["J"])[sl])
            elif name == "P_opt":
                ln.set_data(x[sl], h["P_opt"][sl])
            elif name == "regret" and regret is not None:
                ln.set_data(x[sl], regret[sl])

        if self.on_frame is not None:
            self.on_frame(self, i)

        tail = "  | 已播放完" if i >= self.total else ""
        live = (f"步数 {i}/{self.total}{tail}\n"
                f"v = {h['v'][i]:.2f}  v_hat = {h['v_hat'][i]:.2f}\n"
                f"J = {h['J'][i]:.4f}")
        if self.ax_status.texts:
            self.ax_status.texts[0].remove()
        self.ax_status.text(0, 1, "【实时】\n" + live + "\n\n【验收】\n"
                            + "\n".join(self._report),
                            va="top", fontsize=8.5,
                            transform=self.ax_status.transAxes)


# ============================================================
# 批处理模式公共工具
# ============================================================
def use_agg():
    """无界面模式（--batch / --test）下切换到 Agg 后端。"""
    plt.switch_backend("Agg")


def snap(demo, fname, frames=(0, None, None)):
    """无界面自检：跳到若干关键帧渲染并保存截图（None=末帧）。"""
    picks = []
    for f in frames:
        picks.append(demo.total if f is None else f)
    for f in picks:
        demo.i = f
        demo.update(f, force=True)
    demo.fig.savefig(fname, dpi=110)
    print(f"demo 自检截图 -> {fname}")
