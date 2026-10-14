# 2026-10-13 ZCode（叶安线）：P4 air_quad.slx 薄包装 + 商飞协议接口位

## 任务与边界

按 [`QUAD_SIM_MODEL_PLAN_20261011.md`](../QUAD_SIM_MODEL_PLAN_20261011.md) P4 收尾
（叶安定序：P4 先收、多臂适配最后）。产物：`air_quad.slx` 薄包装 + 遥测组帧接口位 +
估计器→实机传感器映射 + 接口文档（正式验收=接口审查）。红线照旧：既有 `.slx`
全部零触碰（新建 air_quad.slx 为 B2/P4 计划产物）；MATLAB 链单一权威。

## 实现（惯例同 ratio_esc/build_simulink：程序化建模）

- `air_quad_tick.m`：薄包装一步推进——dt=0 采样 → ctrl → step（与 trim_run 同序），
  persistent 状态 + reset 口；输出 8 路（P̂/V/I/地速/油门 1,2/x/SOC）。
- `air_quad_telemetry_pack.m`：商飞协议**遥测第二副帧（0xF2）组帧接口位**——
  主电压 0.1 V、油门 0.1%、电流 1 A、报警字输入、校验和（暂按前 23 字节和
  mod 256，算法以协议原文为准）；其余副帧/整帧分发/CRC 预留（SITL/串口阶段）。
- `build_air_quad.m`：程序化生成 `models/plane_quad/models/air_quad.slx`
  （From Workspace 激励 → Interpreted Fcn 包装 → 记录/组帧/Out1 P̂ SITL 插槽，
  模型注释带 C9/R7 口径声明）。
- `run_quad_slx_checks.m`：冒烟验收（函数+result+硬断言）。

调试坑（照抄惯例仍踩了三个）：本地 `line` 函数须包装 `add_line`（否则撞内置
绘图）；From Workspace 多列输出是单个宽向量口（用 Vector Concatenate）；
Interpreted MATLAB Fcn 参数名是 `MATLABFcn`/`OutputDimensions`（无 Expr/InputPorts）。

## 冒烟结果（PASS，S-B1–S-B5）

- **S-B2 对拍：slx vs MATLAB 权威链 V/v/x/soc 逐位一致**（激励=悬停 5 s + 6 m/s
  阶跃 + 头风 2.5 m/s）——slx 管道透明性证明。
- S-B3 两遍仿真逐位；S-B4 组帧：24 字节/0xF2 标识/电压回读差 0.038 V/油门
  0.0003/电流 0（均 ≤1 LSB）/校验和自洽；S-B5 估计映射偏差 −0.18%（门 ≤3%）。
- 证据：[`quad_p4/`](evidence/quad_migration/quad_p4/)（指标 CSV + 对拍图）；
  `models/plane_quad/models/air_quad.slx` 随代码入库。

## 待叶安接口审查（AIR_QUAD_INTERFACE.md, Proposed）

审查要点：① 0xF2 字段映射 vs 协议表 4.2（尤其校验和算法）；② 电机 3/4 与多
电压通道映射策略；③ 实机传感器口径（l1 空速依赖 vs 纯油门+电压退化档 l0）。

## 边界

全数字 workbook_baseline/quad_placeholder 口径（C9）；组帧只做量化不做传输；
P3 遗留 G-P4（sweepcal 倾斜鲁棒性）与多臂适配按叶安排最后。
