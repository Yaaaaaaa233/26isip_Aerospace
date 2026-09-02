# -*- coding: utf-8 -*-
"""
7 阶段课程训练(镜像 train_curriculum.m 语义):
  calm → constant → step → circle_sine → irregular_visible →
  irregular_dropout → irregular_hidden
每阶段 episode 种子 = 阶段种子 + counter(make_env.m 的种子循环);
training=true 随机化 tau/功率因子/内阻;baseline=fixed(与仓库一致)。
用法:
  python train_curriculum.py --episodes 60 100 100 100 250 150 250
  python train_curriculum.py --benchmark 5      # 仅计时
"""
import argparse
import csv
import json
import time
from pathlib import Path

import numpy as np
import torch

from speedrl_env import Config, ResidualSpeedEnv, curriculum_stages
from td3 import TD3

ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "results"


def run_stage(agent, stage_name, c: Config, episodes, log_rows, tag):
    env = ResidualSpeedEnv(c, baseline_kind="fixed")
    counter = 0
    t0 = time.time()
    for ep in range(episodes):
        seed = (c.seed + counter) % 2**32
        counter += 1
        cc = Config(**{**c.__dict__, "training": True, "seed": seed})
        env.c = cc
        obs = env.reset(seed)
        ep_ret, ep_true, n = 0.0, [], round(cc.duration / cc.decisionPeriod)
        for k in range(n):
            act = agent.select_action(obs, explore=True)
            next_obs, rew, done, info = env.step(act)
            agent.observe_transition(obs, act, rew, next_obs, done)
            obs = next_obs
            ep_ret += rew
            ep_true.append(info["trueMeanPower"])
        log_rows.append({"tag": tag, "stage": stage_name, "episode": ep + 1,
                         "seed": seed, "reward": round(ep_ret, 3),
                         "trueMeanPowerW": round(float(np.mean(ep_true)), 3),
                         "exploreStd": round(agent.explore_std, 4),
                         "elapsed_s": round(time.time() - t0, 1)})
        if (ep + 1) % 10 == 0 or ep == episodes - 1:
            r = [x for x in log_rows if x["tag"] == tag]
            last10 = [x["trueMeanPowerW"] for x in r[-10:]]
            print(f"[{tag}:{stage_name}] ep {ep+1}/{episodes} "
                  f"reward={ep_ret:.1f} trueP={np.mean(ep_true):.1f}W "
                  f"last10={np.mean(last10):.1f}W "
                  f"sigma={agent.explore_std:.3f} "
                  f"({(time.time()-t0)/(ep+1):.2f}s/ep)", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--episodes", type=int, nargs=7,
                    default=[60, 100, 100, 100, 250, 150, 250])
    ap.add_argument("--duration", type=int, default=120)
    ap.add_argument("--benchmark", type=int, default=0,
                    help=">0 时只跑第一阶段 N 回合并退出")
    ap.add_argument("--device", default="cuda")
    args = ap.parse_args()

    RESULTS.mkdir(exist_ok=True)
    stages = curriculum_stages(args.duration)
    stages = [(name, Config(**{**c.__dict__, "duration": args.duration}))
              for name, c in stages]

    agent = TD3(obs_dim=18 * 8, act_dim=1, act_low=-3.0, act_high=3.0,
                device=args.device, seed=1000)
    print(f"device={TD3.device}, stages={[s[0] for s in stages]}")
    log_rows = []
    for idx, (name, c) in enumerate(stages):
        eps = args.benchmark if args.benchmark else args.episodes[idx]
        run_stage(agent, name, c, eps, log_rows, tag=f"s{idx+1}")
        ckpt = RESULTS / f"td3_curriculum_stage{idx+1}_{name}.pt"
        torch.save({"actor": agent.actor.state_dict(),
                    "stage": idx + 1, "stageName": name,
                    "episodes": eps, "totalSteps": agent.total_steps}, ckpt)
        print(f"saved {ckpt.name}", flush=True)
        if args.benchmark:
            break

    stamp = time.strftime("%Y%m%d_%H%M%S")
    log_csv = RESULTS / f"train_log_{stamp}.csv"
    with open(log_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(log_rows[0].keys()))
        w.writeheader()
        w.writerows(log_rows)
    final = RESULTS / f"td3_curriculum_final_{stamp}.pt"
    torch.save({"actor": agent.actor.state_dict(),
                "stageNames": [s[0] for s in stages],
                "episodes": args.episodes,
                "totalSteps": agent.total_steps}, final)
    meta = {"finalCheckpoint": str(final), "log": str(log_csv),
            "device": str(TD3.device), "episodes": args.episodes}
    (RESULTS / "last_run.json").write_text(json.dumps(meta, indent=2),
                                           encoding="utf-8")
    print(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
