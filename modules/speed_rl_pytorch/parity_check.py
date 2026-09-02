# -*- coding: utf-8 -*-
"""Python 侧奇偶校验:与 parity_matlab.m 输出一一对照。"""
import numpy as np
from speedrl_env import Config, run_episode

# A/B/C: 确定性场景,应与 MATLAB 精确一致(相对误差 < 1e-9)
for tag, kw in [
    ("A none_straight_fixed", dict(windMode="none", trajectory="straight")),
    ("B constant_circle_fixed", dict(windMode="constant", trajectory="circle")),
    ("C sine_circle_fixed", dict(windMode="sine", trajectory="circle")),
]:
    c = Config(seed=7, **kw)
    _, m = run_episode(c, "fixed")
    print(f"{tag} {m['meanPowerW']:.12f} {m['energyWh']:.12f} "
          f"{m['estimatedEnduranceHours']:.12f}")

# D: 不规则风统计比对(与 MATLAB 同种子集合,但 RNG 流不同→统计比对)
fp, sp = [], []
for k in range(1, 21):
    c = Config(windMode="irregular", trajectory="circle", seed=2000 + k)
    _, mf = run_episode(c, "fixed")
    _, ms = run_episode(c, "scripted")
    fp.append(mf["meanPowerW"]); sp.append(ms["meanPowerW"])
print(f"D irregular_fixed mean {np.mean(fp):.4f} std {np.std(fp, ddof=1):.4f}")
print(f"D irregular_scripted mean {np.mean(sp):.4f} std {np.std(sp, ddof=1):.4f}")

# E: 随机恒定风统计比对
fc = []
for k in range(1, 21):
    c = Config(windMode="constant", trajectory="circle", randomizeWind=True,
               seed=3000 + k)
    _, mf = run_episode(c, "fixed")
    fc.append(mf["meanPowerW"])
print(f"E constant_random_fixed mean {np.mean(fc):.4f} std {np.std(fc, ddof=1):.4f}")
