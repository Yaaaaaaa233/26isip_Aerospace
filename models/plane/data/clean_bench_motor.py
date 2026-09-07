# -*- coding: utf-8 -*-
"""clean_bench_motor.py -- MN1005 台架表清洗 (06 方案 §4 流程第 1 步)

用法:
    python clean_bench_motor.py <台架表.xlsx 绝对路径>

规则 (docs/architecture/06_platform_power_environment_model.md §4):
  - 原始 xlsx 留在仓库外 (参考数据目录, 禁止上 git); 本脚本只读它;
  - 清洗记录 (结构/哈希/分块/QA/剔除) 进 models/plane/data/processed/;
  - 派生 tidy CSV 写到参考数据目录旁的 derived/ (仓库外, 不上 git),
    记录文件里登记其 SHA-256;
  - 电芯报告 PDF 不在本脚本范围 (06 §4 人工取数单硬规则)。
"""
import hashlib
import sys
from pathlib import Path

import pandas as pd

# 2026-09-03 登记的源文件指纹 (PAW 40X13.1R @MN1005-V2.0-KV100, 2026-07-04 台架)
EXPECTED_SHA256 = "77ead7cb51b6b1fb2bbf6e369e38cbbd63ca34a4335810fbfaddaa47f715404c"
REPO_PROCESSED = Path(__file__).resolve().parent / "processed"

COLS = ["pwm_us", "throttle", "v_esc", "i_esc", "rpm", "thrust_kgf",
        "torque_nm", "p_elec_w", "eta_total_gfw", "p_shaft_w",
        "eta_motor", "eta_prop_gfw"]  # 表头行第 1..12 列 (第 0 列是行号)

INFO_LABEL = "品牌/来源"
HEAD_LABEL = "脉宽"


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src = Path(sys.argv[1])
    assert src.is_file(), f"source not found: {src}"
    digest = sha256_file(src)
    assert digest == EXPECTED_SHA256, (
        f"source hash changed: {digest} != {EXPECTED_SHA256} -- 登记指纹后才能清洗新文件")

    df = pd.read_excel(src, sheet_name="Sheet1", header=None)
    info_rows = df.index[df[1].astype(str).str.contains(INFO_LABEL, na=False)].tolist()
    head_rows = df.index[df[1].astype(str).str.contains(HEAD_LABEL, na=False)].tolist()
    assert len(info_rows) == len(head_rows) and info_rows, "block structure not recognized"

    blocks, qa_lines = [], []
    for k, r0 in enumerate(info_rows):
        nxt = info_rows[k + 1] if k + 1 < len(info_rows) else len(df)
        info = df.iloc[r0 + 1]
        body = df.iloc[head_rows[k] + 1: nxt].copy()
        body.columns = ["idx"] + COLS
        n_raw = len(body)
        # 剔除: 全测量列皆空的行 (块 6 尾部的纯序号行等)
        meas = ["v_esc", "i_esc", "rpm", "thrust_kgf", "p_elec_w"]
        body = body.dropna(subset=meas, how="all")
        n_blank = n_raw - len(body)
        # 数值化; 仍含 NaN 测量值的行单独剔除计数 (块 6 的 PWM=1000 怠速行)
        for c in ["idx"] + COLS:
            body[c] = pd.to_numeric(body[c], errors="coerce")
        n_nan = int(body[meas].isna().any(axis=1).sum())
        body = body.dropna(subset=meas)
        if body.empty:
            # 块 #6 (30V): 全块为 PWM=1000 怠速重复记录 + 尾部纯序号行,
            # 无任何有效测量 -- 整块登记为无效, 不进 tidy 数据
            qa_lines.append(
                f"| {info[7]} | {info[12]:.0f} | {n_raw} | {n_blank} | {n_nan} "
                f"| 0 | - | - | - | - | - | 整块无有效数据 (怠速/中止块) |"
                f" - | - |")
            continue
        body["block"] = str(info[7])
        body["v_no_load"] = float(info[12])
        # 近重复行: 台架在同一 PWM 点的复测 (如 18V 块 idx 缺失的
        # 1721.14 us 行 vs 常规 1720.0 us 行, 读数差 ~0.1%)。保留并打标,
        # 单调性检查在去重序列上做。
        sw_all = body[body["rpm"] > 1000].sort_values("pwm_us", kind="stable")
        dup = (sw_all["pwm_us"].diff().abs() <= 5) & \
              (sw_all["rpm"].diff().abs() <= 10)
        n_repeat = int(dup.sum())
        sw = sw_all[~dup]
        body["repeat"] = False
        body.loc[sw_all.index[dup], "repeat"] = True
        blocks.append(body)
        mono_pwm = bool(sw["pwm_us"].is_monotonic_increasing)
        mono_rpm = bool(sw["rpm"].is_monotonic_increasing)
        p_calc = (body["v_esc"] * body["i_esc"]).abs()
        p_dev = (body["p_elec_w"] - p_calc).abs() / body["p_elec_w"].clip(lower=1.0)
        p_ok = float(p_dev.max())
        shaft_ok = bool((body["p_shaft_w"] <= body["p_elec_w"] + 1e-6).all())
        qa_lines.append(
            f"| {info[7]} | {info[12]:.0f} | {n_raw} | {n_blank} | {n_nan} | "
            f"{len(body)} | {n_repeat} | {'OK' if mono_pwm else 'FAIL'} | "
            f"{'OK' if mono_rpm else 'FAIL'} | {p_ok * 100:.2f}% | "
            f"{'OK' if shaft_ok else 'FAIL'} | "
            f"{body['rpm'].min():.0f}-{body['rpm'].max():.0f} | "
            f"{body['thrust_kgf'].min():.3f}-{body['thrust_kgf'].max():.3f} | "
            f"{body['p_elec_w'].min():.1f}-{body['p_elec_w'].max():.1f} |")
        assert mono_pwm and mono_rpm, f"block {info[7]}: sweep not monotone"
        assert p_ok < 0.05, f"block {info[7]}: P != V*I (max dev {p_ok:.3%})"
        assert shaft_ok, f"block {info[7]}: shaft power above electrical power"

    tidy = pd.concat(blocks, ignore_index=True)
    out_dir = src.parent / "derived"
    out_dir.mkdir(exist_ok=True)
    out_csv = out_dir / "bench_motor_mn1005_tidy.csv"
    tidy.to_csv(out_csv, index=False, encoding="utf-8-sig")
    tidy_sha = hashlib.sha256(out_csv.read_bytes()).hexdigest()

    REPO_PROCESSED.mkdir(exist_ok=True)
    record = REPO_PROCESSED / "bench_motor_mn1005_cleaning.md"
    record.write_text(
        "# MN1005 台架表清洗记录 (bench motor)\n\n"
        "- 清洗脚本: `models/plane/data/clean_bench_motor.py` (本记录由其生成)\n"
        "- 源文件: `PAW 40X13.1R_推力_18V-30V @MN1005-V2.0-KV100_测试数据"
        "2026-07-04_1(3).xlsx` (仓库外 `第二阶段\\参考数据\\`, **不上 git**)\n"
        f"- 源文件 SHA-256: `{digest}` (脚本内登记值强校验)\n"
        "- 工作表: Sheet1, 443 行 x 13 列; 6 个测试块, 每块 = 环境记录行 + "
        "表头行 + 数据行; 列义按表头原样登记 (脉宽 us / 油门 / 电调电压 V / "
        "电调电流 A / 转速 RPM / 拉力 kgf / 扭矩 Nm / 电功率 W / 总力效 gf/W / "
        "轴功率 W / 电机效率 / 桨力效 gf/W), **未做任何单位换算**\n"
        "- 环境记录 (六块一致): 24.5 C, 991.8 hPa, 79.9 %RH, 空速 0 (静台)\n"
        "- 剔除规则: (a) 全测量列皆空的行 (块 #6 尾部纯序号行); (b) 含 NaN "
        "测量值的行 (块 #6 的 PWM=1000 怠速点, 电调无有效读数)\n"
        "- QA: 带载段油门/转速单调; |电功率 - V*I|/电功率 < 5%; 轴功率 <= 电功率\n"
        f"- 派生 tidy 数据 (仓库外): `{out_csv}`\n"
        f"- 派生文件 SHA-256: `{tidy_sha}`\n\n"
        "| 块 | 空载V | 原始行 | 空行 | NaN行 | 有效行 | 复测行 | 油门单调 | "
        "转速单调 | P=VI最大偏差 | 轴<=电 | RPM域 | 拉力域kgf | 功率域W |\n"
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
        + "\n".join(qa_lines) + "\n\n"
        "等级声明: 数据为**静台 (v_air = 0) 静态扫频**, 拟合参数只声明台架覆盖域内 "
        "`calibrated`; 前进比修正 (H3) / 共轴干扰 (H5) 不在本数据内, 按缺省 + "
        "敏感性处理。\n",
        encoding="utf-8")
    print(f"OK: {len(tidy)} valid rows in {tidy['block'].nunique()} blocks "
          f"(empty/idle-only blocks excluded) -> {out_csv}")
    print(f"record -> {record}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
