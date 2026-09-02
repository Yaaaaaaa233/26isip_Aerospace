# 2026-09-02 删除 Python 版速度寻优演示目录（速度寻优代码/）

## 本次做了什么
- 从仓库根目录删除 `速度寻优代码/` 整个目录（esc_core.py、v1_static.py、v2_dynamics.py、v3_robust.py、demo_kit.py、README.md、report_template.html、ESC速度寻优工作总结.pdf、.vscode/settings.json，共 9 个文件）。
- 删除前已在仓库外做本地完整备份（含 PDF 工作总结与 report_template.html，二者在仓库内无其他副本）。

## 关键决策与理由
- 该目录为早期 Python 版三阶段 ESC 演示套件，其全部算法/仿真能力已移植进 `modules/speed_esc/`（MATLAB），并有逐样本对拍证据：`+speedesc/python_reference.m` 隔离复现器、`tests/fixtures/` 14 组 CSV、`verify_python_parity.m`（最大误差 ~5.33e-15，见 `modules/speed_esc/docs/INTEGRATION_NOTES.md`）。MATLAB 侧验收脚本不调用任何 .py 文件，删除不影响任何验收链。
- 保留 `modules/speed_esc/tests/fixtures/provenance.json` 中的 source_sha256 历史记录与文档中的来源引用，作为移植来源的可追溯锚点。

## 遗留问题 / 风险
- 若今后需要重新生成 Python 对拍 fixtures，需从本地备份（或本提交之前的 Git 历史）取回原 .py 文件。
- 本目录原由队友添加；删除决定经仓库协作成员确认（2026-09-02）。

## 下一步
- 无。

## 验收状态
- run_acceptance：不适用（纯目录删除，未触碰任何 MATLAB 代码路径；fixtures 为预生成数据，与该目录无运行时依赖）。
