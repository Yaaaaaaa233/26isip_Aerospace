# 2026-10-16 演示面板 MOE 回归（老 UI 评价卡 + 方案1 参照 + ΔMOE 行）

任务来源：叶安指令"UI上的显示数据都按照之前的老UI来吧，按照方案1加回MOE，把'vs 开环 ΔMOE'行也带回来"
（承接"为什么现在UI没有MOE的显示了？"的两案答复，选定方案1：演示口径 MOE +
离线已知臂参照）。

## 交付：`models/plane_quad/launch_quad_demo.m` 评价卡

六行 MOP/MOE 卡逐字照搬老 3.6 卡（`modules/platform_link/launch_3_6_demo.m:119-140`，
只读参照，未改）：行标签原文、行高 {30,24,24,24,24,24}、双列 {'1x','1x'}、
mkTag 9pt 灰字无换行 / mkVal 粗体右对齐——330 左列宽下长标签截断观感与老 UI
逐像素同（老 UI 同宽同字号同无 WordWrap，非本次引入）。

| 行 | 老 UI 标签 | 显示公式（w36.mop_moe 逐式照搬） |
|---|---|---|
| 1 | MOE 综合效能 overall(2026-09-04口径: =续航能耗Emin/Eactual) | `Emin/Eactual`（15pt 绿/橙/红 0.99/0.97 阈值同款） |
| 2 | 续航能效 MOE_energy / 能耗超额 | `MOE_energy + 100*(Eactual-Emin)/Emin` |
| 3 | vs 开环基线: ΔMOE / 能耗相对变化 | `MOE−MOE_openloop / 100*(Eopen-E)/Eopen`（openloop 臂显示"基线=自身"，老 UI 同款） |
| 4 | 瞬时能效 instant / 指令跟踪滞后 | 尾窗 60 行 `mean(P_known/P真)` + `mean\|v实−v_cmd\|` |
| 5 | 入带步数 / 任务可用率 | 首个带内行号（未入带 NaN，%g 同款） + inband 行占比 |
| 6 | 搜索步数(含就位) / 稳态波动σ | 行末 v_cmd 变动行数 + 尾窗 `std(v_cmd)` |

指标口径映射（老 UI log 列 -> 演示 1 Hz 评价行，tEval=1 s / tailSteps=60 / eps=0.4
与 `w36/config` 同值）：estimate→v_cmd（臂的谷信念）、optimumTrue→命令谷
v*(t)=clip(6∓w)（R7）、speed/speedCmd→v实/v_cmd、powerTrue→行区间均 V·I、
minPowerTrue→known 参照趟同行区间均值、hold 行→行末 v_cmd 未变（"搜索步数(含就位)"
=非 hold 行，就位占比=带内变动行/变动行）。末帧 `report()` 输出老 UI 同款
状态行（`MOE=… | 末误差 … | 稳态超额 …% | 全程能耗超额 …%`）与汇总行
（`MOP/MOE汇总: overall=… | MOE_energy=… | 开环基线MOE=… | ΔMOE=… | 可用率=… |
末误差=… | 跟踪滞后=… | 搜索步数=…(就位占…%) | 峰值加速度=…`）。

## 方案1 参照趟（Emin/Eopen）

- known(oracle, R7 命令谷) 与 openloop(8) 两趟离线预跑：同 `air_quad_tick` 链、
  同配置（`quad_sim.config(quad_sim.baseline('b40'),'est_model',estTier)`）、
  同风剧本同任务窗，逐拍 P真 积分；每趟前后 `clear air_quad_tick`（persistent 链）。
- **同 horizon 对齐**：MOE 用"至今"部分窗 EminP/EopenP vs 实飞 E（运行中=至今值，
  任务窗终点=全窗值）——直接用全窗 Emin 配部分窗 E 会在开局把 MOE 显示成 >10 的
  错数（老 UI 是整窗日志回放才无此问题，逐拍能量数组就是为了消掉这个错配）。
- 缓存：`containers.Map` 跨启动复用（key=`qdemo_refs_v1|风剧本|窗`，含逐拍
  Pmin/Popen 供瞬时能效/部分窗取数）；onReset 触发，首播（t=0）补算；带
  "known 趟 n%" 进度提示，避免界面看似卡死。

## 关键发现：演示层风语义取负修复（本次顺带修掉的真 bug）

`air_quad_tick` 的 `wind_ned_mps` 输入 +w=**顺风**（P(v,w)=P0(v−w)），而 P3/证据
口径 +w=**头风**（P(v,w)=P0(v+w)，多臂会话已逐点验到 0.06 W）。证据逐点核对：

- `quad_p3_sweep_vi.csv` 相位1 P(4)=603.14 W ≡ 清洁链 P0(8)=603.19 W；
- 探针：`air_quad_tick` wind_ned=+4 @ v=8 → 587.64 W ≡ P0(4)=587.64 W（整数吻合）。

不取负时谷律 6∓w 反向（实际空速 6∓2w：相位1 v=4→空速 0、相位3 v=10→空速 14），
known 参照 54.77 Wh **反超** openloop 45.38 Wh，与冻结证据 known 38.99 <
openloop 44.93 直接矛盾（S-D6 门当场抓住）。修复：stepSim/refPass 两处植物输入
取负（`air_quad_tick([vCmd; -w; rst])`），面板/P3/证据语义保持 +w=头风不动；
**只动演示层**，证据、植物、现实性链、多臂结论零触碰。

修复后参照与冻结证据逐位吻合：Emin=38.987 Wh（证据 known 38.99）、
Eopen=44.921 Wh（证据 openloop 44.93）；工作点落回面板所绘证据曲线。

## 终窗数值（240 s 三段相位风，sweepcal 默认臂，vi 档）

MOE overall 0.9200 | 能耗超额 8.70% | **ΔMOE +0.0521 / 能耗相对变化 +5.66%** |
instant 0.9796 | 入带 140 步 / 可用率 14.6% | 搜索 29 步 / σ=1.249 |
E真 42.378 Wh（sweepcal）。截图目检：六行全对位、汇总/状态行同格式。

## 冒烟与证据

`run_quad_demo_smoke` S-D1–S-D5 保持绿（S-D2 两次冷启动逐位：参照只影响显示层
不影响推进历史）；新增 **S-D6**：reset 后 refs 就绪（known<openloop 且有限）、
推满窗 MOE∈(0.5,1.2) 且 ΔMOE>0（sweepcal 应优于开环，P3 排序）。冒烟证据
`docs/evidence/quad_migration/quad_demo/` 刷新（CSV 新列 moe_end/moe_openloop/d_moe）。

## 口径与边界（不变）

面板非可引用数据源（黑箱红线）；MOE 内部归一化，C9 禁外引；参照趟是演示口径
（清洁链），与 TYP 证据口径不同档，巧合的是清洁链定常段功率与证据尾段均值差
<0.1 W（证据本就是该链尾段均值），故参照数值与证据逐位接近——但**不**把演示
面板数字当证据用。如实记录既有小疵（本次未改）：表单"任务窗/s"字段为装饰，
实际窗=常量 `T_s=240`（风剧本绝对相位 [0 80 160 240] 不随动），需产品决策再动。
