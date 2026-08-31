# -*- coding: utf-8 -*-
"""
ESC 速度寻优 —— 共享算法内核
============================
三个版本（v1_static / v2_dynamics / v3_robust）共用的算法与仿真机制：
滤波器、ESC 控制器、仿真运行器、收敛判定、目标函数。

各版本仅自定义自己的 Environment 类（对象模型），本模块不含任何
"版本差异"逻辑。

关于任务书参数的必要偏离（调试结论，详见 README）:
  * 学习率: 任务书 k=0.3 → 实取 22。J_v 梯度量级极小（J''≈0.006/m/s²），
    k=0.3 在 300 步内位移不足 0.5 m/s，无法满足"<100 步收敛"。
  * 低通截止: 任务书 0.1 → 实取 2.0 rad/s。0.1 rad/s 引入约 10 s 环路
    滞后，与收敛速度矛盾（产生发散极限环）。
  * 梯度估计采用"半周期窗口最小二乘回归"而非经典"高通→sin解调→低通"：
    经典方案在工作点移动时受高通瞬态偏置（∝ v̇）污染，在本任务的平坦
    代价曲线上会产生系统性偏差与极限环；回归对直流、移动、延迟免疫。
    高通滤波器仍保留在 ESC 类中，用于代价直流分量的诊断监视。
"""

import numpy as np
import matplotlib
import matplotlib.pyplot as plt

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei"]  # 中文支持
plt.rcParams["axes.unicode_minus"] = False

# ============================================================
# 关键参数（集中定义）
# ============================================================
DT           = 0.1          # 时间步长 [s]
V_MIN, V_MAX = 0.0, 20.0    # 速度边界 [m/s]
V_STAR_INIT  = 6.0          # 初始最优速度 v* [m/s]（ESC 不可见）
V_STAR_JUMP  = 9.0          # V3 跳变后的最优速度 [m/s]

# --- ESC 参数 ---
ESC_A    = 0.5      # 扰动幅值 a [m/s]
ESC_W    = 0.5      # 扰动频率 ω [rad/s]
ESC_K    = 22.0     # 学习率（梯度下降步长，乘以 dt 使用）
ESC_HP_W = 0.1      # 高通滤波器截止频率 [rad/s]（直流监视用，见文件头说明）
ESC_LP_W = 2.0      # 低通滤波器截止频率 [rad/s]（平滑梯度估计）
ESC_WIN  = int(round(np.pi / (ESC_W * DT)))   # 回归窗口 = 半个扰动周期(63步)


def cost(v, v_star):
    """调试用目标函数 J_v(v) = 1 + 0.3·((v-v*)/10)²（人为设计曲线，
    非 X8 实测）。换成文献代理曲线时只需替换本函数。"""
    return 1.0 + 0.3 * ((v - v_star) / 10.0) ** 2


# ============================================================
# 文献式代理功率模型（目标1：续航记录 / 目标2：耦合优化的对象曲线）
# ============================================================
class PhysicsPowerModel:
    """归一化前飞功率代理曲线  P*(v) = P(v)/P_hover。

    形式: P*(v) = 1 + a·x² + b·x³,  x = v/v_star_ref
    由两个标定点唯一确定: 最低点 (v_star_ref, p_min_ratio)。
    默认 (6.3 m/s, 0.913) 对应"悬停 104W、最优 95W"的续航估算文献
    量级 —— 仅为算法链路验证代理（口径见路线图风险表），非本项目
    X8 实机结论；拿到实测/标定数据后只需改这两个参数，优化器不动。

    物理含义: −x² 项来自前飞解除诱导功率（速度增加初期功率下降），
    +x³ 项来自废阻力功率（高速段主导），故曲线呈 U 形且最优为
    低速前飞而非定点悬停 —— 这是"最长悬停时间应飞最优前飞速度"
    这一续航策略的依据。"""
    def __init__(self, v_star_ref=6.3, p_min_ratio=0.913):
        self.v_star_ref = float(v_star_ref)
        self.b = 2.0 * (1.0 - p_min_ratio)     # 由 P(v*)=p_min 反解
        self.a = -1.5 * self.b                 # 由 P'(v*)=0 反解

    def __call__(self, v, v_star_eff=None):
        """归一化功率。v_star_eff>0 时把最低点平移到该速度
        （用于模拟电量衰减导致最优点漂移）。"""
        vs = self.v_star_ref if v_star_eff is None else v_star_eff
        x = np.asarray(v, dtype=float) / vs
        return 1.0 + self.a * x**2 + self.b * x**3


def power_regret(P_true, P_opt):
    """功率后悔值 = (实际功率 − 离线最优功率)/离线最优功率（路线图
    表7 验收口径: 无噪声 ≤1%、噪声工况 ≤3%）。返回 (均值, 最大值)。"""
    P_true = np.asarray(P_true, dtype=float)
    P_opt = np.asarray(P_opt, dtype=float)
    r = (P_true - P_opt) / P_opt
    return float(r.mean()), float(r.max())


# ============================================================
# 滤波器
# ============================================================
class FirstOrderHP:
    """一阶高通滤波器（IIR），截止角频率 wc。
    y[k] = α·y[k-1] + α·(x[k]-x[k-1]),  α = (2-wc·dt)/(2+wc·dt)
    物理意义：去除代价信号的直流（均值）分量，仅保留扰动引起的波动。
    注：首帧用当前输入初始化 x_prev，避免启动阶跃瞬态。"""
    def __init__(self, wc, dt):
        self.alpha = (2.0 - wc*dt) / (2.0 + wc*dt)
        self.y_prev = 0.0
        self.x_prev = None

    def step(self, x):
        if self.x_prev is None:
            self.x_prev = x
            return 0.0
        y = self.alpha * self.y_prev + self.alpha * (x - self.x_prev)
        self.x_prev, self.y_prev = x, y
        return y


class FirstOrderLP:
    """一阶低通滤波器（IIR），截止角频率 wc。
    y[k] = α·y[k-1] + (1-α)·x[k],  α = (2-wc·dt)/(2+wc·dt)
    物理意义：滤除梯度估计中的扰动纹波与测量噪声。"""
    def __init__(self, wc, dt):
        self.alpha = (2.0 - wc*dt) / (2.0 + wc*dt)
        self.y_prev = 0.0

    def step(self, x):
        y = self.alpha * self.y_prev + (1.0 - self.alpha) * x
        self.y_prev = y
        return y


# ============================================================
# ESC 控制器
# ============================================================
class ESC:
    """正弦扰动型 ESC（窗口回归梯度估计，可选预热与步长限幅）。

    每步算法流程:
      1) 记录代价测量 J 与实际速度 v（扰动已在其中）；
      2) 在最近 W 步窗口内做 J 对 v 的最小二乘回归（双边去均值），
         斜率 g ≈ ∂J/∂v，即局部梯度估计；
      3) 低通滤波平滑 g；
      4) 梯度下降更新估计值：v_hat ← v_hat - k·g·dt，限幅到速度边界；
      5) 注入正弦扰动输出：v_ref = v_hat + a·sin(ωt)。

    两个可选鲁棒性机制（默认均关闭，保证调试曲线场景的已验收结果
    逐位不变；陡峭/强噪对象建议开启，见各版本 --phys 模式）:
      * warmup 估计器预热: 窗口未填满前不更新。防止"速度闭环尚未建立
        扰动纹波 + 测量噪声"阶段回归分母过小产生巨大伪梯度（在陡峭
        功率曲线上会把估计值一脚踹飞并触发延迟配位正反馈）。
        代价是启动延迟约一个窗口长度（~63步），平坦调试曲线上不必需。
      * dmax 步长限幅（信任域）: 每步 |Δv_hat| ≤ dmax [m/s]，兜底
        限制任何残余异常梯度的破坏速度。
    """
    def __init__(self, v0, a=ESC_A, w=ESC_W, k=ESC_K,
                 v_min=V_MIN, v_max=V_MAX, dt=DT,
                 hp_w=ESC_HP_W, lp_w=ESC_LP_W, win=ESC_WIN,
                 warmup=False, dmax=None):
        self.v_hat = float(v0)     # 最优速度估计
        self.a, self.w, self.k = a, w, k
        self.v_min, self.v_max, self.dt = v_min, v_max, dt
        self.hp = FirstOrderHP(hp_w, dt)   # 代价直流分量监视（诊断用）
        self.lp = FirstOrderLP(lp_w, dt)   # 梯度估计平滑
        self.win = win
        self.warmup = warmup
        self.dmax = dmax
        self.J_buf = []            # 窗口内代价样本
        self.v_buf = []            # 窗口内实际速度样本
        self.t = 0.0

    def step(self, J_meas, v_meas):
        """输入代价测量值与实际速度，返回下一步速度指令 v_ref。"""
        self.hp.step(J_meas)                            # 直流监视（不进入梯度）
        self.J_buf.append(J_meas)
        self.v_buf.append(v_meas)
        if len(self.J_buf) > self.win:                  # 维护定长窗口
            self.J_buf.pop(0)
            self.v_buf.pop(0)
        # --- 窗口最小二乘斜率（梯度估计）---
        Jw = np.asarray(self.J_buf); Vw = np.asarray(self.v_buf)
        Jc = Jw - Jw.mean(); Vc = Vw - Vw.mean()
        den = float(np.dot(Vc, Vc))
        if self.warmup and len(Jw) < self.win:
            g = 0.0                 # 预热期: 激励样本不足，不更新
        else:
            g = float(np.dot(Jc, Vc)) / den if den > 1e-9 else 0.0
        g = self.lp.step(g)                             # 平滑
        # --- 梯度下降（可选信任域）+ 边界限幅 ---
        d = -self.k * g * self.dt
        if self.dmax is not None:
            d = float(np.clip(d, -self.dmax, self.dmax))
        self.v_hat = float(np.clip(self.v_hat + d,
                                   self.v_min, self.v_max))
        # --- 扰动注入 ---
        self.t += self.dt
        return self.v_hat + self.a * np.sin(self.w * self.t)


# ============================================================
# 仿真运行器
# ============================================================
def run_case(env, v0, n_steps, esc_kwargs=None):
    """运行一次 ESC 仿真。

    env 需满足的协议（三个版本各自实现）:
      env.v          实际速度（本函数负责初始化为 v0）
      env.v_star     当前真实最优值（每步记录，用于对比评估）
      env.step(k, v_ref) -> (实际速度 v, 代价测量 J_m)
    esc_kwargs 可覆盖 ESC 构造参数（供演示界面调参用）。
    返回历史 dict: v_ref / v / v_hat / J / v_star 皆为长度 n_steps 数组。
    """
    esc = ESC(v0, **(esc_kwargs or {}))
    env.v = v0
    hist = dict(v_ref=[], v=[], v_hat=[], J=[], v_star=[], P_true=[])
    v_cmd = esc.v_hat                        # 初始指令（相位 0，扰动项为 0）
    for k in range(n_steps):
        v, J = env.step(k, v_cmd)            # 环境前进一步
        hist["v_ref"].append(v_cmd)
        hist["v"].append(v)
        hist["v_hat"].append(esc.v_hat)
        hist["J"].append(J)
        hist["v_star"].append(env.v_star)
        # 无噪声真实功率（env 未提供时退化为测量值 J），供后悔值统计
        hist["P_true"].append(getattr(env, "P_true", J))
        v_cmd = esc.step(J, v)               # ESC 更新并给出下一步指令
    return {key: np.array(val) for key, val in hist.items()}


def settle_steps(v_hist, v_star, tol, start=0, window=20, hold=30):
    """平滑后速度（window 步滑动平均，滤除扰动纹波）首次进入 v_star 的
    tol 邻域并保持 hold 步的时刻；不满足返回 -1。"""
    h = np.asarray(v_hist, dtype=float)
    if len(h) - start < window + hold:
        return -1
    hs = np.convolve(h[start:], np.ones(window)/window, mode="valid")
    ok = (np.abs(hs - v_star) < tol).astype(int)
    run = 0
    for i, o in enumerate(ok):
        run = run + 1 if o else 0
        if run >= hold:
            return start + i - hold + window // 2
    return -1
