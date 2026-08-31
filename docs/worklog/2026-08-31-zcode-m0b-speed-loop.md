# 2026-08-31 M0-B 速度闭环与安全回退（ZCode 会话简报）

## 交付

按 `docs/interfaces/PROJECT_EXECUTION_ROADMAP.md` §6 完成 M0-B 全部五项，验收通过：

1. **参考选择器 + 安全监视器**（`M0B Reference & Safety`）：`optimizer_enable=0` 走手动固定 `v_ref`（状态 0）；`=1` 走优化器参考（状态 1/2）；硬标志（位 1/2/3/4/6/7）触发 → 冻结 0.5 s（状态 3）→ 回退手动参考（状态 4），清除 1.5 s 后重进。`v_ref` 范围 [0,15] m/s、变化率 2 m/s²，warm-up 由速率限制实现。位 5（速度失跟）只记录不门控。
2. **速度外环**（`M0B Speed Controller`）：投影 PI → 归一化 `pitch_cmd`（chart_23 域，`theta_des=0.523·cmd`）。符号经实验标定：`cmd>0 → θ+ → 加速 −x`（`dVe_x/dθ≈−147`，每单位指令约 15 m/s²）。`Kp=0.12`、`Ki=0.04` 为根层常量（扫描 0.06–0.30 证明更大增益放大振荡）；`|cmd|≤0.40`、积分 ≤0.15、变化率 0.25/s。
3. **俯仰注入**：wrapper 内 `InputConditioning` 出 2 → Demux → **算术融合** `y=orig·(1−e)+m0b·e` → Mux → 内层 `roll_pitch`。`speed_loop_enable=0` 时逐位复现原信号（IEEE754 `x·1.0+0.0=x`），实测与 `air` 比对差 0。roll/yaw/thrust/arming 零改动。
4. **阈值运行时化**：`M0B Flags Override` 用普通逻辑方块覆盖约束位 3/5，阈值 `M0B Att Tol`（0.523 rad）/`M0B Speed Tol`（1.0 m/s）为常量，位 5 语义升级为 `|v−v_ref(unit delay)|>tol`。M0-A chart 原样保留。
5. **验收试验**（`run_air_m0b_tests`，归档 `results/air_m0b_tests/20260831_234117`）：5 m/s 均值误差 1.62、9 m/s 1.60、6→9 阶跃后 1.88 m/s；PWM 1500±4 无饱和；安全演示（收紧 Att Tol 至 0.15）8 次 frozen/fallback 转换、回退 5 m/s。快照 `air_m0b.slx`。

## 审计新发现（air 原模型行为，此前文档未记录）

- `InputConditioning` 忽略全部 RC 输入：roll=内部正弦 ±0.4 @1 rad/s、pitch=0、thrust=0.5、yaw=0；chart `arm` 由 wrapper 内 Constant 1 提供（恒解锁）。
- 基线水平漂移（|Ve_y| 0–8.4 m/s 摆动）由 roll 正弦驱动；速度外环只能操纵俯仰，故 |v| 跟踪存在 ~1.6 m/s 的扰动下限（9 m/s 时）。
- 垂直方向固有自由落体（PWM=1500×8、P_est≈251 W，净推力≈0）。功率仅作模型内对照。

## 工程踩坑（重要，已写入 M0B_SPEED_LOOP.md §4）

1. **对已存在的 MATLAB Function chart 重新赋值 `Script`（哪怕只改字面量）会静默丢弃其全部连线**；新增 chart 的输入线也可能在编译端口重推导时被丢弃。对策：旧 chart 不改、语义用普通方块外层覆盖；新 chart 创建→设脚本→接线→编译→逐一验证（`ensureLine` 循环）；**任何安装脚本保存前必须先跑一次功能仿真**（本会话两次靠该检查拦截了断线模型落盘）。
2. **Switch 控制口连线在本环境不可靠**（编译后控制口视为断开，恒选 in1）。对策：选择器用算术融合实现。
3. R2022b 其他：To Workspace 时序数据布局会翻转（需按宽度归一）；`fullfile` 生成反斜杠不能用于模块路径；PortConnectivity 无 `Width` 字段。

## 下一步（M0-C，见路线图 §6）

把单变量速度 ESC 封装为可替换接口替换 `M0B v Ref Optimizer` 占位：输入仅 `t/v/P_e/E_e/attitude/yaw_rate/constraint_flags`，稳定窗口排除 warmup/非 active/失跟阶段，至少三组初值配对基线试验；每次结构变更后重跑 `run_air_m0a_baseline_compare`。
