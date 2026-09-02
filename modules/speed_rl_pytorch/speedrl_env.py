# -*- coding: utf-8 -*-
"""
speed_rl_residual 环境的 Python 逐行移植(对拍基准:modules/speed_rl_residual/@speedrl,
仓库 main@11d3a8e)。语义严格对应:
  synthetic_reset.m / synthetic_step.m / guard.m / context.m / observe.m /
  step.m / reset.m / make_baseline.m / scripted_residual.m / run_episode.m
差异说明:RNG 用 numpy PCG64(统计等价,不逐位复现 MATLAB mt19937ar);
确定性场景(无风/恒定风+无随机化)下动态与 MATLAB 精确一致,用于奇偶校验。
"""
from dataclasses import dataclass, field, replace
import math
import numpy as np


@dataclass
class Config:
    Ts: float = 0.05
    decisionPeriod: float = 1
    duration: float = 120
    history: int = 8
    seed: int = 1
    training: bool = False
    randomizeWind: bool = False
    windMode: str = "irregular"
    windObservation: str = "observable"
    powerDropouts: bool = False
    trajectory: str = "straight"
    speedBounds: tuple = (2, 15)
    deltaBounds: tuple = (-3, 3)
    initialSpeed: float = 6.3
    baselineSpeed: float = 6.3
    speedRate: float = 0.5
    tauSpeed: float = 1
    optimumAirSpeed: float = 6.3
    powerScale: float = 500
    powerNoiseFraction: float = 0.02
    powerDelay: float = 0.5
    maxPowerAge: float = 1
    windNoiseStd: float = 0.15
    windDelay: float = 0.2
    maxWindAge: float = 2
    capacityAh: float = 8
    internalResistance: float = 0.04
    initialSoc: float = 0.85
    minimumVoltage: float = 18
    pathRadius: float = 30
    radialFreeze: float = 5
    radialScale: float = 5
    usableEnergyWh: float = 150
    movePenalty: float = 0.002
    missingPenalty: float = 10
    blockedPenalty: float = 10
    trajectoryPenalty: float = 2
    constantWind: tuple = (2.0, -1.0)
    ouTimeConstant: float = 12
    ouStd: float = 2
    gustProbability: float = 0.004
    gustMagnitude: float = 3


@dataclass
class Sample:
    """对应 validate_sample 的 14 字段契约 + evaluator 真值。"""
    time_s: float
    ground_velocity_ne_mps: np.ndarray
    wind_velocity_ne_mps: np.ndarray
    wind_sample_time_s: float
    power_w: float
    power_sample_time_s: float
    voltage_v: float
    soc: float
    path_phase_rad: float
    path_tangent_ne: np.ndarray
    radial_error_m: float
    velocity_valid: bool
    wind_valid: bool
    power_valid: bool
    evaluator: dict = field(default_factory=dict)


class SyntheticAdapter:
    """make_synthetic_adapter / synthetic_reset / synthetic_step 的移植。"""

    def reset(self, seed, c: Config):
        rng = np.random.default_rng(seed)
        mode = c.windMode
        if mode == "mixed":
            choices = ("constant", "step", "sine", "irregular")
            mode = choices[seed % 4]
        tau, factor, resistance = c.tauSpeed, 1.0, c.internalResistance
        base_wind = np.array(c.constantWind, dtype=float)
        wind_phase = 0.0
        if c.training:
            tau = tau * (0.75 + 0.5 * rng.random())
            factor = 0.9 + 0.2 * rng.random()
            resistance = resistance * (0.75 + 0.5 * rng.random())
        if c.randomizeWind:
            magnitude = 0.5 + 3 * rng.random()
            angle = 2 * math.pi * rng.random()
            base_wind = magnitude * np.array([math.cos(angle), math.sin(angle)])
            wind_phase = 2 * math.pi * rng.random()
        s = {
            "rng": rng, "mode": mode, "time": 0.0, "speed": c.initialSpeed,
            "phase": 0.0, "radial": 0.0, "soc": c.initialSoc, "tau": tau,
            "factor": factor, "resistance": resistance, "base_wind": base_wind,
            "wind_phase": wind_phase, "ou": np.zeros(2), "gust": np.zeros(2),
            "power_queue": [], "wind_queue": [], "last_power": None,
            "last_wind": None,
        }
        return self.step(s, c.initialSpeed, 0.0, c)

    def step(self, s, v_ref, dt, c: Config):
        old_speed = s["speed"]
        if dt > 0:
            s["speed"] = v_ref + (s["speed"] - v_ref) * math.exp(-dt / s["tau"])
            s["time"] += dt
        t = s["time"]
        if c.trajectory == "circle":
            if dt > 0:
                s["phase"] = math.fmod(s["phase"] + s["speed"] * dt / c.pathRadius,
                                       2 * math.pi)
            tangent = np.array([-math.sin(s["phase"]), math.cos(s["phase"])])
        else:
            tangent = np.array([1.0, 0.0])
            s["phase"] = 0.0
        true_wind = self._wind(s, dt, c)
        ground = tangent * s["speed"]
        true_air = float(np.linalg.norm(ground - true_wind))
        acceleration = (s["speed"] - old_speed) / dt if dt > 0 else 0.0
        shaft = c.powerScale * s["factor"] * (
            0.913 + 0.012 * (true_air - c.optimumAirSpeed) ** 2
            + 0.01 * acceleration ** 2)
        open_voltage = 21 + 4.2 * s["soc"]
        disc = open_voltage ** 2 - 4 * s["resistance"] * shaft
        assert disc > 0, "battery feasibility"
        current = 2 * shaft / (open_voltage + math.sqrt(disc))
        voltage = open_voltage - s["resistance"] * current
        true_power = voltage * current
        if dt > 0:
            s["soc"] = max(0.0, s["soc"] - current * dt / (3600 * c.capacityAh))

        # 功率测量:噪声 + FIFO 延迟 + (可选)掉测窗 [35,38) mod 50
        power_item = (true_power * (1 + c.powerNoiseFraction * s["rng"].standard_normal()),
                      t, voltage, s["soc"])
        power_delay = round(c.powerDelay / c.Ts)
        if not s["power_queue"]:
            s["power_queue"] = [power_item] * power_delay
        s["power_queue"].append(power_item)
        delayed_power = s["power_queue"].pop(0)
        drop_power = c.powerDropouts and 35 <= (t % 50) < 38
        if s["last_power"] is None or not drop_power:
            s["last_power"] = delayed_power
        p = s["last_power"]
        power_valid = (t - p[1]) <= c.maxPowerAge + 1e-9 and p[0] > 0

        # 风测量:噪声 + FIFO 延迟 + hidden/dropout 窗 [25,32) mod 40
        wind_item = (true_wind + c.windNoiseStd * s["rng"].standard_normal(2), t)
        wind_delay = round(c.windDelay / c.Ts)
        if not s["wind_queue"]:
            s["wind_queue"] = [wind_item] * wind_delay
        s["wind_queue"].append(wind_item)
        delayed_wind = s["wind_queue"].pop(0)
        drop_wind = c.windObservation == "hidden" or (
            c.windObservation == "dropout" and 25 <= (t % 40) < 32)
        if s["last_wind"] is None or not drop_wind:
            s["last_wind"] = delayed_wind
        w = s["last_wind"]
        wind_valid = (c.windObservation != "hidden" and
                      (t - w[1]) <= c.maxWindAge + 1e-9)

        observed_wind = w[0] if wind_valid else np.full(2, np.nan)
        wind_time = w[1] if wind_valid else np.nan
        power_obs = p[0] if True else np.nan  # 与 MATLAB 一致:掉测时保持旧值
        sample = Sample(
            time_s=t, ground_velocity_ne_mps=ground,
            wind_velocity_ne_mps=observed_wind, wind_sample_time_s=wind_time,
            power_w=power_obs, power_sample_time_s=p[1], voltage_v=p[2],
            soc=p[3], path_phase_rad=s["phase"], path_tangent_ne=tangent,
            radial_error_m=s["radial"], velocity_valid=True,
            wind_valid=bool(wind_valid), power_valid=bool(power_valid),
            evaluator={"true_power_w": true_power,
                       "true_wind_ne_mps": true_wind,
                       "true_air_speed_mps": true_air,
                       "chemical_power_w": open_voltage * current,
                       "wind_mode": s["mode"]})
        return s, sample

    def _wind(self, s, dt, c: Config):
        t = s["time"]
        mode = s["mode"]
        if mode == "none":
            return np.zeros(2)
        if mode == "constant":
            return s["base_wind"].copy()
        if mode == "step":
            if t < 0.45 * c.duration:
                return s["base_wind"].copy()
            return np.array([-0.8 * s["base_wind"][0],
                             -s["base_wind"][1] + 0.5])
        if mode == "sine":
            period = max(40, c.duration)
            q = 2 * math.pi * t / period + s["wind_phase"]
            return np.array([2 * math.sin(q), 1.5 * math.cos(q)])
        if mode == "irregular":
            if dt > 0:
                a = math.exp(-dt / c.ouTimeConstant)
                s["ou"] = a * s["ou"] + c.ouStd * math.sqrt(1 - a * a) * \
                    s["rng"].standard_normal(2)
                s["gust"] = s["gust"] * math.exp(-dt / 2)
                if s["rng"].random() < c.gustProbability:
                    angle = 2 * math.pi * s["rng"].random()
                    s["gust"] = s["gust"] + c.gustMagnitude * np.array(
                        [math.cos(angle), math.sin(angle)])
            return s["ou"] + s["gust"]
        raise ValueError(mode)


def make_context(sample: Sample, reference, last_delta, mean_power, delta_power,
                 c: Config):
    """context.m:仅测量构造;真值不进入。"""
    tangent = sample.path_tangent_ne
    if sample.velocity_valid:
        ground = float(np.dot(sample.ground_velocity_ne_mps, tangent))
    else:
        ground = np.nan
    if sample.wind_valid:
        wind = sample.wind_velocity_ne_mps
        wind_along = float(np.dot(wind, tangent))
        normal = np.array([-tangent[1], tangent[0]])
        wind_normal = float(np.dot(wind, normal))
        air_speed = float(np.linalg.norm(sample.ground_velocity_ne_mps - wind))
        wind_age = sample.time_s - sample.wind_sample_time_s
    else:
        wind_along = wind_normal = air_speed = np.nan
        wind_age = np.inf
    return {"time": sample.time_s, "groundSpeed": ground, "airSpeed": air_speed,
            "reference": reference, "lastDelta": last_delta,
            "meanPower": mean_power, "deltaPower": delta_power,
            "windNE": sample.wind_velocity_ne_mps, "windAlong": wind_along,
            "windNormal": wind_normal, "windAge": wind_age,
            "windValid": sample.wind_valid, "velocityValid": sample.velocity_valid,
            "powerValid": sample.power_valid, "voltage": sample.voltage_v,
            "soc": sample.soc, "phase": sample.path_phase_rad,
            "tangentNE": tangent, "radialError": sample.radial_error_m,
            "baselineDefault": c.baselineSpeed,
            "optimumAirSpeed": c.optimumAirSpeed, "speedBounds": c.speedBounds}


def guard(request, previous, sample: Sample, dt, c: Config):
    """guard.m:限幅 + 限速 + 反馈失效保持;blocked 语义一致。"""
    reason = "ok"
    reference = previous
    if not np.isfinite(request):
        reason = "invalid_action"
    elif not sample.velocity_valid or not sample.power_valid:
        reason = "invalid_or_stale_feedback"
    else:
        bounded = min(max(request, c.speedBounds[0]), c.speedBounds[1])
        change = min(max(bounded - previous, -c.speedRate * dt),
                     c.speedRate * dt)
        reference = previous + change
        if abs(sample.radial_error_m) > c.radialFreeze:
            reason = "trajectory_freeze"
    blocked = reason != "ok"
    return reference, blocked, reason


def make_frame(ctx, c: Config):
    """observe.m 的单帧 18 维(归一化与掩码一致)。"""
    b = c.speedBounds
    d = max(abs(c.deltaBounds[0]), abs(c.deltaBounds[1]))
    frame = np.array([
        ctx["groundSpeed"] / b[1], ctx["airSpeed"] / 20,
        (ctx["reference"] - b[0]) / (b[1] - b[0]),
        (ctx["baseSpeed"] - b[0]) / (b[1] - b[0]), ctx["lastDelta"] / d,
        ctx["meanPower"] / c.powerScale, ctx["deltaPower"] / c.powerScale,
        ctx["windAlong"] / 10, ctx["windNormal"] / 10,
        ctx["windAge"] / c.maxWindAge, ctx["soc"], ctx["voltage"] / 25.2,
        math.sin(ctx["phase"]), math.cos(ctx["phase"]),
        ctx["radialError"] / c.radialScale,
        float(ctx["velocityValid"]), float(ctx["powerValid"]),
        float(ctx["windValid"])])
    frame[~np.isfinite(frame)] = 0
    return np.clip(frame, -5, 5)


def baseline_reference(kind, ctx):
    """make_baseline.m:fixed / wind_analytic。"""
    if kind == "fixed":
        return ctx["baselineDefault"], {"method": "fixed", "usedWind": False}
    if kind == "wind_analytic":
        used = ctx["windValid"]
        if used:
            wind = ctx["windNE"]
            tangent = ctx["tangentNE"]
            along = float(np.dot(wind, tangent))
            normal = float(np.dot(wind, np.array([-tangent[1], tangent[0]])))
            v = along + math.sqrt(max(ctx["optimumAirSpeed"] ** 2 - normal ** 2, 0))
        else:
            v = ctx["baselineDefault"]
        lo, hi = ctx["speedBounds"]
        v = min(max(v, lo), hi)
        return v, {"method": "wind_analytic", "usedWind": used}
    raise ValueError(kind)


def scripted_residual(ctx, base, c: Config):
    """scripted_residual.m:可观测风解析残差(接口上限参考,非学习策略)。"""
    if not ctx["windValid"]:
        desired = base
    else:
        along, normal = ctx["windAlong"], ctx["windNormal"]
        desired = along + math.sqrt(max(c.optimumAirSpeed ** 2 - normal ** 2, 0))
    lo, hi = c.speedBounds
    desired = min(max(desired, lo), hi)
    return min(max(desired - base, c.deltaBounds[0]), c.deltaBounds[1])


class ResidualSpeedEnv:
    """reset.m + step.m:残差 RL 环境(决策 1 s,对象 0.05 s)。"""

    def __init__(self, c: Config, adapter=None, baseline_kind="fixed"):
        self.c = c
        self.adapter = adapter or SyntheticAdapter()
        self.baseline_kind = baseline_kind

    def reset(self, seed=None):
        c = replace(self.c) if seed is None else replace(self.c, seed=seed)
        self.c = c
        adapter_state, sample = self.adapter.reset(c.seed, c)
        self.reference = c.initialSpeed
        self.last_delta = 0.0
        self.previous_mean = (sample.power_w if sample.power_valid
                              else c.powerScale)
        ctx = make_context(sample, self.reference, self.last_delta,
                           self.previous_mean, 0, c)
        base, base_info = baseline_reference(self.baseline_kind, ctx)
        ctx["baseSpeed"] = base
        self.history = np.tile(make_frame(ctx, c), (c.history, 1))
        self._s = {"adapter_state": adapter_state, "sample": sample,
                   "base": base, "base_info": base_info, "steps": 0}
        return self.history.flatten().copy()

    def step(self, action):
        c = self.c
        s = self._s
        assert s["steps"] < round(c.duration / c.decisionPeriod)
        delta = min(max(float(action), c.deltaBounds[0]), c.deltaBounds[1])
        ctx0 = make_context(s["sample"], self.reference, self.last_delta,
                            self.previous_mean, 0, c)
        base, _ = baseline_reference(self.baseline_kind, ctx0)
        request = base + delta
        if abs(s["sample"].radial_error_m) > c.radialFreeze:
            request = base
        n = round(c.decisionPeriod / c.Ts)
        powers = np.full(n, np.nan)
        true_powers = np.full(n, np.nan)
        speeds = np.full(n, np.nan)
        airspeeds = np.full(n, np.nan)
        wind_along = np.full(n, np.nan)
        wind_normal = np.full(n, np.nan)
        radial = np.zeros(n)
        blocked = 0
        for k in range(n):
            self.reference, blk, _ = guard(request, self.reference,
                                           s["sample"], c.Ts, c)
            if blk:
                blocked += 1
            s["adapter_state"], s["sample"] = self.adapter.step(
                s["adapter_state"], self.reference, c.Ts, c)
            sample = s["sample"]
            if sample.power_valid:
                powers[k] = sample.power_w
            if "evaluator" in sample.__dict__ and sample.evaluator:
                true_powers[k] = sample.evaluator["true_power_w"]
            elif sample.power_valid:
                true_powers[k] = sample.power_w
            measured = make_context(sample, self.reference, delta,
                                    self.previous_mean, 0, c)
            speeds[k] = measured["groundSpeed"]
            airspeeds[k] = measured["airSpeed"]
            wind_along[k] = measured["windAlong"]
            wind_normal[k] = measured["windNormal"]
            radial[k] = sample.radial_error_m
        good = np.isfinite(powers)
        coverage = float(good.mean())
        mean_power = float(powers[good].mean()) if good.any() else self.previous_mean
        delta_power = mean_power - self.previous_mean
        ctx = make_context(s["sample"], self.reference, delta, mean_power,
                           delta_power, c)
        next_base, _ = baseline_reference(self.baseline_kind, ctx)
        ctx["baseSpeed"] = next_base
        frame = make_frame(ctx, c)
        self.history = np.vstack([self.history[1:], frame])
        move = ((delta - self.last_delta) /
                (c.deltaBounds[1] - c.deltaBounds[0])) ** 2
        trajectory_cost = float(np.mean((radial / c.radialScale) ** 2))
        reward = (-mean_power / c.powerScale - c.movePenalty * move
                  - c.missingPenalty * (1 - coverage)
                  - c.blockedPenalty * blocked / n
                  - c.trajectoryPenalty * trajectory_cost)
        self.previous_mean = mean_power
        self.last_delta = delta
        s["steps"] += 1
        done = s["steps"] >= round(c.duration / c.decisionPeriod)
        true_mean = (float(np.nanmean(true_powers))
                     if np.isfinite(true_powers).any() else mean_power)
        info = {"time": s["sample"].time_s, "baseline": base,
                "requestedResidual": delta, "appliedReference": self.reference,
                "meanPower": mean_power, "trueMeanPower": true_mean,
                "energyWh": float(np.nansum(true_powers)) * c.Ts / 3600,
                "powerCoverage": coverage, "blockedFraction": blocked / n,
                "reward": reward,
                "meanGroundSpeed": float(np.nanmean(speeds)),
                "meanAirSpeed": float(np.nanmean(airspeeds)),
                "meanWindAlong": float(np.nanmean(wind_along)),
                "meanWindNormal": float(np.nanmean(wind_normal)),
                "radialRms": float(np.sqrt(np.mean(radial ** 2)))}
        return self.history.flatten().copy(), reward, done, info


def run_episode(c: Config, strategy, seed=None, baseline_kind="fixed"):
    """run_episode.m:公平固定时长回合,返回逐步行记录 L 与汇总 summary。"""
    env = ResidualSpeedEnv(c, baseline_kind=baseline_kind)
    obs = env.reset(seed if seed is not None else c.seed)
    n = round(c.duration / c.decisionPeriod)
    rows = []
    for k in range(n):
        s = env._s
        ctx = make_context(s["sample"], env.reference, env.last_delta,
                           env.previous_mean, 0, c)
        base, _ = baseline_reference(baseline_kind, ctx)
        if isinstance(strategy, str):
            if strategy == "fixed":
                action = c.baselineSpeed - base
            elif strategy == "baseline":
                action = 0.0
            elif strategy == "scripted":
                action = scripted_residual(ctx, base, c)
            else:
                raise ValueError(strategy)
        else:  # 可调用:agent(obs)->action 或 (obs,ctx,base,c)->action
            if callable(strategy):
                action = strategy(obs, ctx, base, c)
        obs, reward, done, info = env.step(action)
        sample = s["sample"]
        rows.append((info["time"], info["meanGroundSpeed"], info["meanAirSpeed"],
                     info["appliedReference"], info["baseline"],
                     info["requestedResidual"], info["meanPower"],
                     info["trueMeanPower"], reward, info["energyWh"],
                     info["meanWindAlong"], info["meanWindNormal"],
                     sample.wind_valid, info["powerCoverage"],
                     info["blockedFraction"], sample.path_phase_rad,
                     info["radialRms"], sample.soc))
        assert done == (k == n - 1)
    arr = np.asarray(rows)
    names = ["time_s", "ground_speed_mps", "air_speed_mps", "reference_mps",
             "baseline_mps", "delta_v_mps", "measured_power_w", "true_power_w",
             "reward", "energy_wh", "wind_tangent_mps", "wind_normal_mps",
             "wind_valid", "power_coverage", "blocked_fraction",
             "path_phase_rad", "radial_rms_m", "soc"]
    mean_power = float(arr[:, 7].mean())
    summary = {
        "policy": strategy if isinstance(strategy, str) else "td3_agent",
        "seed": c.seed, "meanPowerW": mean_power,
        "energyWh": float(arr[:, 9].sum()),
        "estimatedEnduranceHours": c.usableEnergyWh / mean_power,
        "minimumGroundSpeed": float(arr[:, 1].min()),
        "maximumGroundSpeed": float(arr[:, 1].max()),
        "rateViolations": int(np.sum(np.abs(np.diff(arr[:, 3])) >
                                     c.speedRate * c.decisionPeriod + 1e-9)),
        "boundViolations": int(np.sum((arr[:, 3] < c.speedBounds[0] - 1e-9) |
                                      (arr[:, 3] > c.speedBounds[1] + 1e-9))),
        "meanBlockedFraction": float(arr[:, 14].mean()),
        "radialRms": float(np.sqrt(np.mean(arr[:, 16] ** 2))),
        "meanPowerCoverage": float(arr[:, 13].mean()),
    }
    return dict(zip(names, arr.T)), summary


def curriculum_stages(duration=120):
    """curriculum.m:7 阶段(难度递增至隐藏风)。"""
    spec = [("calm", "none", "observable", "straight"),
            ("constant", "constant", "observable", "straight"),
            ("step", "step", "observable", "straight"),
            ("circle_sine", "sine", "observable", "circle"),
            ("irregular_visible", "irregular", "observable", "circle"),
            ("irregular_dropout", "irregular", "dropout", "circle"),
            ("irregular_hidden", "irregular", "hidden", "circle")]
    stages = []
    for k, (name, wind, obs, traj) in enumerate(spec, start=1):
        c = Config(duration=duration, windMode=wind, windObservation=obs,
                   trajectory=traj, randomizeWind=True, seed=1000 + 100 * k)
        stages.append((name, c))
    return stages
