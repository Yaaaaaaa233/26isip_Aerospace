# -*- coding: utf-8 -*-
"""
TD3(PyTorch),超参镜像 modules/speed_rl_residual/+speedrl/make_agent.m:
  隐层 128×2 / batch 128 / buffer 200k / γ=0.995
  探索噪声 σ=0.12×span=0.72 → min 0.01×span=0.06(指数衰减)
  目标策略平滑 σ=0.03×span=0.18,clip 0.5×span=3.0
  动作输出线性不压缩,环境侧 clip(与 MATLAB run_episode 一致)
"""
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F


class Actor(nn.Module):
    def __init__(self, obs_dim, act_dim, hidden=128):
        super().__init__()
        self.net = nn.Sequential(nn.Linear(obs_dim, hidden), nn.ReLU(),
                                 nn.Linear(hidden, hidden), nn.ReLU(),
                                 nn.Linear(hidden, act_dim))

    def forward(self, obs):
        return self.net(obs)


class QNet(nn.Module):
    def __init__(self, obs_dim, act_dim, hidden=128):
        super().__init__()
        self.net = nn.Sequential(nn.Linear(obs_dim + act_dim, hidden), nn.ReLU(),
                                 nn.Linear(hidden, hidden), nn.ReLU(),
                                 nn.Linear(hidden, 1))

    def forward(self, obs, act):
        return self.net(torch.cat([obs, act], dim=-1))


class ReplayBuffer:
    def __init__(self, capacity, obs_dim, act_dim):
        self.capacity = capacity
        self.obs = np.zeros((capacity, obs_dim), dtype=np.float32)
        self.act = np.zeros((capacity, act_dim), dtype=np.float32)
        self.rew = np.zeros(capacity, dtype=np.float32)
        self.next_obs = np.zeros((capacity, obs_dim), dtype=np.float32)
        self.done = np.zeros(capacity, dtype=np.float32)
        self.ptr = 0
        self.size = 0

    def add(self, obs, act, rew, next_obs, done):
        self.obs[self.ptr] = obs
        self.act[self.ptr] = act
        self.rew[self.ptr] = rew
        self.next_obs[self.ptr] = next_obs
        self.done[self.ptr] = float(done)
        self.ptr = (self.ptr + 1) % self.capacity
        self.size = min(self.size + 1, self.capacity)

    def sample(self, batch, rng):
        idx = rng.integers(0, self.size, size=batch)
        to = lambda x: torch.as_tensor(x, device=TD3.device)  # noqa: E731
        return (to(self.obs[idx]), to(self.act[idx]), to(self.rew[idx]),
                to(self.next_obs[idx]), to(self.done[idx]))


class TD3:
    device = None

    def __init__(self, obs_dim, act_dim, act_low, act_high, device="cuda",
                 hidden=128, batch=128, buffer_size=200_000, gamma=0.995,
                 tau=5e-3, lr=1e-3, policy_delay=2,
                 target_noise=0.18, noise_clip=3.0,
                 explore_start=0.72, explore_min=0.06, explore_decay=1.5e-5,
                 warmup=500, seed=1000):
        if device == "cuda" and not torch.cuda.is_available():
            device = "cpu"
        TD3.device = torch.device(device)
        self.act_low, self.act_high = act_low, act_high
        self.batch, self.gamma, self.tau = batch, gamma, tau
        self.policy_delay = policy_delay
        self.target_noise, self.noise_clip = target_noise, noise_clip
        self.explore_std = explore_start
        self.explore_min, self.explore_decay = explore_min, explore_decay
        self.warmup = warmup
        self.rng = np.random.default_rng(seed)
        torch.manual_seed(seed)

        dev = TD3.device
        self.actor = Actor(obs_dim, act_dim, hidden).to(dev)
        self.actor_target = Actor(obs_dim, act_dim, hidden).to(dev)
        self.actor_target.load_state_dict(self.actor.state_dict())
        self.critic1 = QNet(obs_dim, act_dim, hidden).to(dev)
        self.critic2 = QNet(obs_dim, act_dim, hidden).to(dev)
        self.critic1_target = QNet(obs_dim, act_dim, hidden).to(dev)
        self.critic2_target = QNet(obs_dim, act_dim, hidden).to(dev)
        self.critic1_target.load_state_dict(self.critic1.state_dict())
        self.critic2_target.load_state_dict(self.critic2.state_dict())
        self.actor_opt = torch.optim.Adam(self.actor.parameters(), lr=lr)
        self.critic_opt = torch.optim.Adam(
            list(self.critic1.parameters()) + list(self.critic2.parameters()),
            lr=lr)
        self.buffer = ReplayBuffer(buffer_size, obs_dim, act_dim)
        self.total_steps = 0
        self.updates = 0

    def select_action(self, obs, explore=True):
        if explore and self.total_steps < self.warmup:
            a = self.rng.uniform(self.act_low, self.act_high, size=1)
            return float(a[0])
        with torch.no_grad():
            o = torch.as_tensor(obs, dtype=torch.float32,
                                device=TD3.device).unsqueeze(0)
            a = float(self.actor(o).squeeze().item())
        if explore:
            a = a + self.rng.normal(0, self.explore_std)
        return a

    def _decay_explore(self):
        self.explore_std = max(self.explore_min,
                               self.explore_std * math_exp(-self.explore_decay))

    def update(self):
        if self.buffer.size < max(self.batch, self.warmup):
            return
        obs, act, rew, next_obs, done = self.buffer.sample(self.batch, self.rng)
        with torch.no_grad():
            noise = (torch.randn_like(act) * self.target_noise
                     ).clamp(-self.noise_clip, self.noise_clip)
            next_a = (self.actor_target(next_obs) + noise).clamp(
                self.act_low, self.act_high)
            q1t = self.critic1_target(next_obs, next_a)
            q2t = self.critic2_target(next_obs, next_a)
            target = rew + (1 - done) * self.gamma * torch.min(q1t, q2t)
        q1 = self.critic1(obs, act)
        q2 = self.critic2(obs, act)
        critic_loss = F.mse_loss(q1, target) + F.mse_loss(q2, target)
        self.critic_opt.zero_grad()
        critic_loss.backward()
        self.critic_opt.step()

        self.updates += 1
        if self.updates % self.policy_delay == 0:
            actor_loss = -self.critic1(obs, self.actor(obs)).mean()
            self.actor_opt.zero_grad()
            actor_loss.backward()
            self.actor_opt.step()
            for src, dst in [(self.actor, self.actor_target),
                             (self.critic1, self.critic1_target),
                             (self.critic2, self.critic2_target)]:
                for p, pt in zip(src.parameters(), dst.parameters()):
                    pt.data.mul_(1 - self.tau).add_(self.tau * p.data)

    def observe_transition(self, obs, act, rew, next_obs, done):
        self.buffer.add(obs, np.asarray([act], dtype=np.float32), rew,
                        next_obs, done)
        self.total_steps += 1
        self.update()
        self._decay_explore()


def math_exp(x):
    import math
    return math.exp(x)
