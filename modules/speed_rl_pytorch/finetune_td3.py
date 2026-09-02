# -*- coding: utf-8 -*-
"""
TD3 从 BC 热启动微调(v1):只在三个不规则风阶段微调,小探索噪声、低学习率。
"""
import argparse
import csv
import json
import time
from pathlib import Path

import torch

from speedrl_env import Config, curriculum_stages
from td3 import TD3
from train_curriculum import run_stage, RESULTS


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bc", default="results/bc_actor_h8.pt")
    ap.add_argument("--history", type=int, default=8)
    ap.add_argument("--episodes", type=int, nargs=3, default=[150, 100, 150])
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--sigma", type=float, default=0.12)
    ap.add_argument("--seed", type=int, default=3000)
    args = ap.parse_args()

    stages = [c for name, c in curriculum_stages(120)][4:]  # 后三阶段
    agent = TD3(obs_dim=18 * args.history, act_dim=1, act_low=-3, act_high=3,
                device="cuda", lr=args.lr, explore_start=args.sigma,
                explore_min=0.03, explore_decay=1e-6, warmup=200,
                seed=args.seed)
    ck = torch.load(args.bc, map_location="cpu", weights_only=False)
    agent.actor.load_state_dict(ck["actor"])
    agent.actor_target.load_state_dict(ck["actor"])
    print(f"BC warm start from {args.bc} (h={args.history}), "
          f"lr={args.lr}, sigma={args.sigma}")

    log_rows = []
    names = ["irregular_visible", "irregular_dropout", "irregular_hidden"]
    for idx, (c, name) in enumerate(zip(stages, names)):
        cc = Config(**{**c.__dict__, "history": args.history})
        run_stage(agent, name, cc, args.episodes[idx], log_rows,
                  tag=f"ft{idx+1}")
        torch.save({"actor": agent.actor.state_dict(),
                    "history": args.history, "stage": name},
                   RESULTS / f"td3_ft_stage{idx+1}_{name}.pt")

    stamp = time.strftime("%Y%m%d_%H%M%S")
    final = RESULTS / f"td3_ft_final_{stamp}.pt"
    torch.save({"actor": agent.actor.state_dict(), "history": args.history,
                "init": args.bc, "episodes": args.episodes}, final)
    log = RESULTS / f"ft_log_{stamp}.csv"
    with open(log, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(log_rows[0].keys()))
        w.writeheader()
        w.writerows(log_rows)
    (RESULTS / "last_ft.json").write_text(
        json.dumps({"finalCheckpoint": str(final), "log": str(log),
                    "history": args.history}, indent=2), encoding="utf-8")
    print(f"saved {final}")


if __name__ == "__main__":
    main()
