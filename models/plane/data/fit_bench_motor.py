# -*- coding: utf-8 -*-
"""fit_bench_motor.py -- MN1005 台架数据初版拟合 (06 方案 §4 流程第 2-3 步)

用法:
    python fit_bench_motor.py <tidy.csv>

输入: clean_bench_motor.py 产出的派生 tidy CSV (仓库外 derived/)。
输出 (进仓库 models/plane/data/calibration/):
  - bench_motor_mn1005_fit.json : 分块拟合系数 + 留出误差 + 适用范围;
  - bench_motor_mn1005_fit.md   : 人读版标定报告骨架 (等级声明 + 误差表)。

口径:
  - 每电压块分别拟合 (V 视为块常量, 取空载电压 V_nom):
      P_elec = a3*n^3 + a2*n^2 + a0   (n = RPM/1000, 常量项吸收低速损耗)
      Thrust = b2*n^2 + b1*n + b0     [kgf]
      Torque = c2*n^2 + c1*n + c0     [Nm]
  - 留出验证: 每块按行序每第 4 行留出 (确定性, 无随机种子), 报告
    留出点相对误差 mean/max;
  - 等级: 台架静态 (v_air = 0) 域内 calibrated; 前进比 (H3) / 共轴 (H5)
    不含; V 之间不作外推, 平台运行时按块间插值并在敏感性里声明。
"""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

CAL_DIR = Path(__file__).resolve().parent / "calibration"


def fit_block(g: pd.DataFrame) -> dict:
    n = (g["rpm"] / 1000.0).to_numpy(float)
    idx = np.arange(len(g))
    hold = idx % 4 == 3
    tr = ~hold
    out = {"v_nom": float(g["v_no_load"].iloc[0]), "n_fit": int(tr.sum()),
           "n_hold": int(hold.sum()), "rpm_min": float(g["rpm"].min()),
           "rpm_max": float(g["rpm"].max())}
    for name, deg in (("p_elec", 3), ("thrust", 2), ("torque", 2)):
        ycol = {"p_elec": "p_elec_w", "thrust": "thrust_kgf",
                "torque": "torque_nm"}[name]
        y = g[ycol].to_numpy(float)
        coef = np.polynomial.polynomial.polyfit(n[tr], y[tr], deg)
        pred = np.polynomial.polynomial.polyval(n[hold], coef)
        rel = np.abs(pred - y[hold]) / np.maximum(np.abs(y[hold]), 1e-9)
        out[name] = {"coef": [float(c) for c in coef],
                     "hold_rel_err_mean": float(rel.mean()),
                     "hold_rel_err_max": float(rel.max())}
    return out


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src = Path(sys.argv[1])
    df = pd.read_csv(src)
    CAL_DIR.mkdir(exist_ok=True)

    blocks = {}
    for blk, g in df.groupby("block"):
        g = g.sort_values("rpm")
        blocks[str(blk)] = fit_block(g)

    fit = {
        "source_tidy_sha256": hashlib.sha256(src.read_bytes()).hexdigest(),
        "prop": "PAW 40X13.1R", "motor": "MN1005-V2.0-KV100",
        "bench_date": "2026-07-04", "static_air": True,
        "variable": "n = RPM/1000; polyfit ascending coefficients",
        "blocks": blocks,
        "level": "calibrated (bench static domain only)",
        "notes": [
            "v_air = 0 静台数据: 不含前进比修正 (H3) / 共轴干扰 (H5);",
            "运行点电压落在块间时按相邻块线性插值, 不外推到 18-30 V 之外;",
            "留出协议: 每块按 rpm 排序后每第 4 行留出 (确定性);",
            "块 #6 为怠速/中止记录, 无有效数据, 未参与拟合。",
        ],
    }
    jp = CAL_DIR / "bench_motor_mn1005_fit.json"
    jp.write_text(json.dumps(fit, ensure_ascii=False, indent=2),
                  encoding="utf-8")

    lines = [
        "# MN1005 台架标定 (初版拟合)", "",
        f"- 源 tidy: `{src.name}` SHA-256 `{fit['source_tidy_sha256'][:16]}...`",
        "- 拟合形式: P=a3*n^3+a2*n^2+a0 [W]; T=b2*n^2+b1*n+b0 [kgf]; "
        "Q=c2*n^2+c1*n+c0 [Nm]; n=RPM/1000 (系数见同名 .json)",
        "- 留出: 每块每第 4 行; 下表为留出点相对误差", "",
        "| 块 | V_nom | 拟合/留出 | RPM 域 | P 留出 mean/max | "
        "T 留出 mean/max | Q 留出 mean/max |",
        "|---|---|---|---|---|---|---|",
    ]
    for blk, b in blocks.items():
        lines.append(
            f"| {blk} | {b['v_nom']:.0f} | {b['n_fit']}/{b['n_hold']} | "
            f"{b['rpm_min']:.0f}-{b['rpm_max']:.0f} | "
            f"{b['p_elec']['hold_rel_err_mean']:.2%} / "
            f"{b['p_elec']['hold_rel_err_max']:.2%} | "
            f"{b['thrust']['hold_rel_err_mean']:.2%} / "
            f"{b['thrust']['hold_rel_err_max']:.2%} | "
            f"{b['torque']['hold_rel_err_mean']:.2%} / "
            f"{b['torque']['hold_rel_err_max']:.2%} |")
    lines += [""] + [f"- {t}" for t in fit["notes"]] + [
        "",
        "等级: **calibrated, 限台架静态覆盖域**; 任何 U 形右支 / 前进比 / "
        "eta 物理效果结论仍属缺省 + 敏感性口径 (06 方案 §3.1 H3/H5)。",
    ]
    mp = CAL_DIR / "bench_motor_mn1005_fit.md"
    mp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"fit -> {jp}\n     {mp}")
    for blk, b in blocks.items():
        print(f"  {blk}: P hold {b['p_elec']['hold_rel_err_mean']:.2%}/"
              f"{b['p_elec']['hold_rel_err_max']:.2%}  "
              f"T hold {b['thrust']['hold_rel_err_mean']:.2%}/"
              f"{b['thrust']['hold_rel_err_max']:.2%}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
