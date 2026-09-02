# -*- coding: utf-8 -*-
"""评估 BC(或任意 actor 检查点)策略:4 场景 × 20 未见种子。"""
import argparse
import csv
import numpy as np
import torch

from speedrl_env import Config, run_episode
from td3 import Actor, TD3
from evaluate import SCENARIOS, RESULTS as RES

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", required=True)
    ap.add_argument("--history", type=int, default=8)
    ap.add_argument("--name", default="td3_agent")
    ap.add_argument("--suffix", default="")
    args = ap.parse_args()

    ck = torch.load(args.ckpt, map_location="cpu", weights_only=False)
    actor = Actor(18 * args.history, 1)
    actor.load_state_dict(ck["actor"])
    TD3.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    actor = actor.to(TD3.device).eval()

    def policy(obs, ctx, base, c):
        with torch.no_grad():
            o = torch.as_tensor(obs, dtype=torch.float32,
                                device=TD3.device).unsqueeze(0)
            return float(actor(o).squeeze().item())

    header = ["Policy", "Seed", "MeanPowerW", "EnergyWh", "EnduranceHours",
              "MinimumGroundSpeed", "MaximumGroundSpeed", "RateViolations",
              "BoundViolations", "BlockedFraction", "RadialRms",
              "PowerCoverage", "WindMode", "WindObservation"]
    for wind, obs_mode, seeds, rand in SCENARIOS:
        rows, powers = [], {}
        c0 = Config(history=args.history, windMode=wind,
                    windObservation=obs_mode, trajectory="circle",
                    randomizeWind=rand)
        for name, strat in [("fixed", "fixed"), ("scripted", "scripted"),
                            (args.name, policy)]:
            vals = []
            for seed in seeds:
                c = Config(**{**c0.__dict__, "seed": seed})
                _, m = run_episode(c, strat)
                vals.append(m["meanPowerW"])
                rows.append([name, seed, f"{m['meanPowerW']:.6f}",
                             f"{m['energyWh']:.6f}",
                             f"{m['estimatedEnduranceHours']:.6f}",
                             f"{m['minimumGroundSpeed']:.6f}",
                             f"{m['maximumGroundSpeed']:.6f}",
                             m["rateViolations"], m["boundViolations"],
                             f"{m['meanBlockedFraction']:.6f}",
                             f"{m['radialRms']:.6f}",
                             f"{m['meanPowerCoverage']:.6f}", wind, obs_mode])
            powers[name] = np.array(vals)
        fx = powers["fixed"]
        for name, v in powers.items():
            win = int(np.sum(v - fx < -1e-12))
            print(f"[{wind}/{obs_mode}] {name:14s} mean={v.mean():8.3f}W "
                  f"({(v.mean()/fx.mean()-1)*100:+.2f}%) win={win}/{len(v)}")
        out = RES / f"bc_eval_{wind}_{obs_mode}{args.suffix}.csv"
        with open(out, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(header)
            w.writerows(rows)

if __name__ == "__main__":
    main()
