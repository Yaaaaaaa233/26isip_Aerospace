# 仓库同步与 Plane 重规划

项目组：周航正、霍奕茗、于跃、叶安、王健祺
文件负责人：待组内确认
主要撰写：Codex
技术贡献：周航正（提出恢复与新指导文件重规划需求）；Codex（远端同步、接口审计、Plane P0--P4 实现与测试）
审核：待项目组审核、待指导教师确认
AI协助：Codex

## 本次处理

- 远端缓存 `origin/main` 已安全快进至 `f75b77e`，包含 2026-09-02 的架构、接口、M2、Wind、Harness 与治理更新。
- 网络再次访问 GitHub 失败（443 reset/timeout），因此未重复下载；快进使用的是本地已获取的远端对象。
- 更新前全部本地改动先保存为 `stash@{0}`，随后恢复；两个文档冲突采用新仓库权威版本解决。用户数据 `功率-升力.xlsx` 未删除，已按数据生命周期规则移动到 `models/plane/data/raw/`，原始内容未编辑。

## 重新规划后的实现

- 恢复并保留 `models/px4_x8/+x8phys` 作为 PX4 PWM 兼容对象，明确不等同于统一 Plane。
- 新增 `models/plane`，按 `docs/architecture/04_interface_dictionary.md` 和 `docs/PROJECT_EXECUTION_ROADMAP.md` P0--P4 实现 `plane.reset/step`：风-空地速、速度/eta 限速、圆周相位/径向误差、联合 `P(v_air,eta)` 代理、累计能量和 SOC。
- 新增 `run_plane_acceptance` / `test_plane_p0p4`，并更新 `modules/README.md`、`DEVELOPMENT_STATUS.md`。

## 验证结果

- `run_plane_acceptance`：PASS；零风功率 323.566 W，5 m/s 顺风样例功率 299.206 W（代理口径）。
- `run_x8phys_acceptance`：PASS；零风 PWM 功率 334.208 W，20 m/s 风 430.097 W，平台字段和 8 位标志映射通过。
- `git diff --check`：通过。
- `tools/check_repo_governance.ps1`：未能解析，远端脚本中的中文字符串在当前 PowerShell 环境显示为损坏编码并产生语法错误；需由仓库维护者修复编码后重跑。

## 当前边界

`models/plane` 仍是 E0/E1 未校准代理，尚未接入 PX4 `air_spare.slx` 或统一 Harness。下一步应先由负责人确认 Plane 参数和公共接口 1.0 冻结，再建立 Wind/Plane/Control/Harness 的端到端场景；不能把本次代理测试写成真实节能或飞行安全结论。
