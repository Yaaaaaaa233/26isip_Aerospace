# -*- coding: utf-8 -*-
"""
模仿学习(BC)热启动:
  教师 = 真值风解析最优残差(数据生成专用,部署时网络只能看观测);
  在不规则/恒定/正弦 × 可观测/缺测/隐藏 × 圆周 的混合场景上采集 (obs, delta*),
  监督训练 actor,随后可接 TD3 微调。
  关键科学问题:风隐藏时,8 帧历史是否足以从功率/速度推断风?
用法:
  python bc_train.py --history 8 --episodes 1500
  python bc_train.py --history 32 --episodes 1500   # 信息量消融
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from speedrl_env import Config, ResidualSpeedEnv, curriculum_stages
from td3 import Actor, TD3

ROOT = Path(__file__).resolve().parent
RES = ROOT / "results"


def teacher_delta(env):
    """用真值风算解析最优残差(教师;仅用于生成监督数据)。"""
    c = env.c
    sample = env._s["sample"]
    tw = sample.evaluator["true_wind_ne_mps"]
    tangent = sample.path_tangent_ne
    along = float(np.dot(tw, tangent))
    normal = float(np.dot(tw, np.array([-tangent[1], tangent[0]])))
    desired = along + math.sqrt(max(c.optimumAirSpeed ** 2 - normal ** 2, 0))
    desired = min(max(desired, c.speedBounds[0]), c.speedBounds[1])
    return min(max(desired - c.baselineSpeed, c.deltaBounds[0]), c.deltaBounds[1])


def collect(history, episodes, seed0=30_000):
    """混合场景采集;执行教师动作(状态分布与教师一致)。"""
    obs_dim = 18 * history
    xs = np.zeros((episodes * 120, obs_dim), dtype=np.float32)
    ys = np.zeros(episodes * 120, dtype=np.float32)
    scen_cycle = []
    for wind in ("irregular", "constant", "sine"):
        for obs_mode in ("observable", "dropout", "hidden"):
            scen_cycle.append((wind, obs_mode))
    n = 0
    for ep in range(episodes):
        wind, obs_mode = scen_cycle[ep % len(scen_cycle)]
        c = Config(history=history, windMode=wind, windObservation=obs_mode,
                   trajectory="circle" if ep % 3 else "straight",
                   randomizeWind=True, training=True, seed=seed0 + ep)
        env = ResidualSpeedEnv(c)
        obs = env.reset(c.seed)
        for k in range(120):
            d = teacher_delta(env)
            xs[n] = obs
            ys[n] = d
            n += 1
            obs, _, done, _ = env.step(d)
    return xs[:n], ys[:n]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--history", type=int, default=8)
    ap.add_argument("--episodes", type=int, default=1500)
    ap.add_argument("--epochs", type=int, default=40)
    ap.add_argument("--batch", type=int, default=512)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--seed", type=int, default=2000)
    args = ap.parse_args()

    RES.mkdir(exist_ok=True)
    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    torch.manual_seed(args.seed)

    print(f"collecting BC data: history={args.history}, "
          f"episodes={args.episodes} ...", flush=True)
    xs, ys = collect(args.history, args.episodes)
    print(f"dataset: {xs.shape[0]} samples")

    x = torch.as_tensor(xs, device=dev)
    y = torch.as_tensor(ys, device=dev).unsqueeze(1)
    n = x.shape[0]
    actor = Actor(18 * args.history, 1).to(dev)
    opt = torch.optim.Adam(actor.parameters(), lr=args.lr)
    lossf = nn.MSELoss()
    rng = np.random.default_rng(args.seed)
    for epoch in range(args.epochs):
        perm = rng.permutation(n)
        tot = 0.0
        for i in range(0, n, args.batch):
            idx = torch.as_tensor(perm[i:i + args.batch], device=dev)
            pred = actor(x[idx])
            loss = lossf(pred, y[idx])
            opt.zero_grad()
            loss.backward()
            opt.step()
            tot += float(loss) * len(idx)
        if (epoch + 1) % 5 == 0 or epoch == 0:
            with torch.no_grad():
                rmse = float(torch.sqrt(lossf(actor(x), y)))
            print(f"epoch {epoch+1}/{args.epochs} train MSE {tot/n:.5f} "
                  f"RMSE {rmse:.4f} m/s", flush=True)
    out = RES / f"bc_actor_h{args.history}.pt"
    torch.save({"actor": actor.state_dict(), "history": args.history,
                "samples": int(n), "teacher": "true_wind_analytic"}, out)
    print(f"saved {out}")


if __name__ == "__main__":
    main()
