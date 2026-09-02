# -*- coding: utf-8 -*-
"""
训练后评估(口径对齐 evaluate_policies.m):
fixed / baseline / scripted / td3 四策略 × 未见种子,同种子同环境对比;
输出与 MATLAB 相同列结构的 policy_evaluation_<windMode>_<windObservation>.csv。
场景(全部圆周轨迹):
  irregular+observable 2001-2020 | constant(随机化) 3001-3020
  irregular+dropout    4001-4020 | irregular+hidden   5001-5020
"""
import csv
import json
from pathlib import Path

import numpy as np
import torch

from speedrl_env import Config, run_episode
from td3 import Actor, TD3

ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "results"

SCENARIOS = [
    ("irregular", "observable", range(2001, 2021), False),
    ("constant", "observable", range(3001, 3021), True),
    ("irregular", "dropout", range(4001, 4021), False),
    ("irregular", "hidden", range(5001, 5021), False),
]


def make_agent_policy(ckpt_path, device):
    ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    actor = Actor(18 * 8, 1)
    actor.load_state_dict(ckpt["actor"])
    TD3.device = torch.device(device)
    actor = actor.to(TD3.device).eval()

    def policy(obs, ctx, base, c):
        with torch.no_grad():
            o = torch.as_tensor(obs, dtype=torch.float32,
                                device=TD3.device).unsqueeze(0)
            return float(actor(o).squeeze().item())

    return policy, ckpt


def main():
    meta = json.loads((RESULTS / "last_run.json").read_text(encoding="utf-8"))
    ckpt_path = meta["finalCheckpoint"]
    device = "cuda" if torch.cuda.is_available() else "cpu"
    td3_policy, ckpt = make_agent_policy(ckpt_path, device)
    print(f"checkpoint: {ckpt_path} (steps={ckpt.get('totalSteps')})")

    header = ["Policy", "Seed", "MeanPowerW", "EnergyWh", "EnduranceHours",
              "MinimumGroundSpeed", "MaximumGroundSpeed", "RateViolations",
              "BoundViolations", "BlockedFraction", "RadialRms",
              "PowerCoverage", "WindMode", "WindObservation"]
    all_rows = []
    for wind, obs_mode, seeds, rand in SCENARIOS:
        c0 = Config(windMode=wind, windObservation=obs_mode, trajectory="circle",
                    randomizeWind=rand)
        policies = [("fixed", "fixed"), ("baseline", "baseline"),
                    ("scripted", "scripted"), ("td3_agent", td3_policy)]
        rows = []
        for seed in seeds:
            c = Config(**{**c0.__dict__, "seed": seed})
            for name, strat in policies:
                _, m = run_episode(c, strat)
                rows.append([name, seed, f"{m['meanPowerW']:.6f}",
                             f"{m['energyWh']:.6f}",
                             f"{m['estimatedEnduranceHours']:.6f}",
                             f"{m['minimumGroundSpeed']:.6f}",
                             f"{m['maximumGroundSpeed']:.6f}",
                             m["rateViolations"], m["boundViolations"],
                             f"{m['meanBlockedFraction']:.6f}",
                             f"{m['radialRms']:.6f}",
                             f"{m['meanPowerCoverage']:.6f}", wind, obs_mode])
        out = RESULTS / f"policy_evaluation_{wind}_{obs_mode}.csv"
        with open(out, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(header)
            w.writerows(rows)
        all_rows.extend(rows)
        # 场景小结
        print(f"\n== {wind}/{obs_mode} ==")
        base_mean = np.mean([float(r[2]) for r in rows if r[0] == "fixed"])
        for name, _ in policies:
            vals = np.array([float(r[2]) for r in rows if r[0] == name])
            seeds_arr = np.array([int(r[1]) for r in rows if r[0] == name])
            fixed = np.array([float(r[2]) for r in rows if r[0] == "fixed"])
            order = np.argsort(seeds_arr)
            win = int(np.sum(vals[order] < fixed[order] - 1e-12))
            print(f"  {name:12s} mean={vals.mean():8.3f}W "
                  f"({(vals.mean()/base_mean-1)*100:+.2f}%) "
                  f"win={win}/{len(vals)} "
                  f"viol={sum(int(r[7])+int(r[8]) for r in rows if r[0]==name)}")
    print(f"\nCSV 写入 {RESULTS}")


if __name__ == "__main__":
    main()
