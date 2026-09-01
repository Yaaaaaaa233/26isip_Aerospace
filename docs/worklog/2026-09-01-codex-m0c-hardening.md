# 2026-09-01 M0-C 验收加固与文档统一

## 本次做了什么

- 修复 `add_air_m0c_esc.m`：若已加载的 `air_spare` 存在未保存修改，在任何更新、关闭或保存前以 `air:M0C:DirtyModel` 拒绝执行。
- 新增 `test_m0c_installer_dirty_guard.m`，验证拒绝后模型仍保持 loaded/dirty，且磁盘文件 SHA256 不变。
- 修复 `run_air_m0c_trials.m` 的配对能量口径：fixed/ESC 必须共享相同连续 `[20,30] s` 时间网格；active 掩码只用于稳态和安全指标。
- 统一 M0-C 脚本的 `ratio_esc` 路径解析：优先仓库内 `modules/ratio_esc`，仅在目录真实存在时回退旧外部布局，消除无效 `addpath` 警告并恢复两个诊断脚本在主库布局下的可用性。
- 统一根 README、开发状态、执行路线、模型 README 与 M0-A/B/C 接口文档；`docs/PROJECT_EXECUTION_ROADMAP.md` 为唯一路线正文，interfaces 下旧同名文件改为迁移说明。
- 更新 M0-C evidence，并提交机器可读的共同网格配对数据 CSV。

## 关键决策与理由

- 修订 `docs/worklog/2026-09-01-zcode-m0c-speed-esc.md` 中“五组配对”和 `−0.12%～−0.36%` 的历史表述：实际是四组 fixed/ESC 配对加一组 ESC 确定性复现；旧能量数值来自两次运行各自不同的稀疏 active 掩码，比较的有效时间长度不一致。旧 worklog 按追加式规则不回改，本篇记录修订。
- 共同网格重算后四组 `|ΔE|≤0.00013%`，应解释为当前 `P_est` 功率面数值上平坦，不作任何真实节能结论。
- `air_m0c.slx` 是冻结快照，本轮不修改任何平台 `.slx`；修复集中在可重复安装、验收脚本和文档证据。

## 遗留问题 / 风险

- 当前 `P_est=ΣC_M·ω³` 未经电压、电流、台架或飞行数据校准，M0-C 只证明接口、闭环机制、确定性和安全链。
- 扰动场景 active 窗仍受限；模型编译时的已知未连接端口警告尚未清理。
- M1 尚未实施：需要固定随机种子的功率/速度噪声、反馈时延和风扰动，以及冻结/恢复统计。

## 下一步

- 按 `docs/PROJECT_EXECUTION_ROADMAP.md` 进入 M1；先定义场景矩阵、随机种子、信号注入点和通过门槛，再改模型或脚本。

## 验收状态

- `test_m0c_esc_unit`：通过。
- `test_m0c_installer_dirty_guard`：通过。
- `run_air_m0c_trials`：通过，归档 `results/air_m0c_trials/20260901_144953/`。
- `run_air_m0a_baseline_compare`：通过，四类信号最大差 0，归档 `results/air_m0a_baseline_compare/20260901_145110/`。
- `run_air_m0b_safety_injection`：通过，4/4 注入场景及严格恢复通过，归档 `results/air_m0b_safety_injection/20260901_145111/`。
- `modules/ratio_esc/run_acceptance`：通过，`allPassed=1`（单元、无噪声、10 个组合种子、漂移、Simulink、RL 均通过）。
