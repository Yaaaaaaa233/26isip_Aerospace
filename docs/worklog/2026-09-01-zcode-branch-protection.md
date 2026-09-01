# 2026-09-01 顶层治理文件权限保护（CODEOWNERS + 分支保护）

## 本次做了什么

- 新增 `.github/CODEOWNERS`：将 `AGENTS.md`、`README.md`、`.gitignore`、`docs/COLLABORATION.md`、`docs/PROJECT_EXECUTION_ROADMAP.md`、`docs/interfaces/`、`.github/` 指定给创始人 @Zhoucmd6 所有。
- 通过 GitHub API 为 `main` 开启分支保护并读回验证：要求 PR + 至少 1 个批准 + **Code Owners review 必需** + 新提交撤销旧批准；禁止强推与分支删除；要求线性历史；`enforce_admins=false`（管理员/创始人保留直推与绕过权限）。

## 关键决策与理由

- **GitHub 无按文件写权限**，采用官方机制 CODEOWNERS + 分支保护：其他人修改顶层治理文件必须经创始人 review 的 PR 才能合并，保证顶层规则只由创始人变更。
- **有意不保护** `docs/DEVELOPMENT_STATUS.md` 与 `docs/worklog/`：AGENTS.md 规定每次工作会话必须回写这两处，锁定会阻塞协作流程；`modules/`、`models/`、`docs/evidence/` 等为成员日常工作区，同样不锁。
- **`enforce_admins=false`**：创始人日常直推 main 的工作方式不变；保护只约束其他协作者。
- 保护清单调整方式：由创始人修改 `.github/CODEOWNERS`（其自身也在保护范围内）或在 Settings → Branches 修改规则。

## 遗留问题 / 风险

- 协作者此后向 main 直推会被拒绝，需要改为 fork/分支 + PR 流程；非顶层文件的 PR 也需要 1 个批准（创始人或具有写权限的协作者均可批）。
- 2026-09-01 上午并入速度模块与 M0-C 提交均在保护开启前直推完成；此后同类操作将走 PR。

## 下一步

- 团队成员知悉新流程；如需放宽或收紧保护清单，由创始人修改 CODEOWNERS 或保护规则。

## 验收状态

- run_acceptance：未运行（本次仅新增 `.github/CODEOWNERS` 与本文档，未改动任何模块代码）。
- 分支保护：API 读回验证通过（enforce_admins=false、code owner review=true、1 批准、禁强推/删除、线性历史）。
