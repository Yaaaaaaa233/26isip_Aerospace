# 2026-10-15 展示面板 v3：按老 UI 网格骨架重做布局（错位修复）

> 执行：ZCode 重写骨架 + ds-executor 视觉迭代（其模型带视觉；叶安指定）。
> 结论先行：v1 手工坐标版"错位很多"（叶安反馈）→ v2/v3 改为老 UI
> （`modules/platform_link/launch_3_6_demo.m`，只读参考）的 **uifigure +
> uigridlayout 网格托管 + uipanel 卡片**骨架——布局由网格解析，错位类问题
> 结构性消除。ds-executor 4 轮看图迭代修掉 6 类问题（P1–P6），smoke 五门
> 原样全过。

## 一、根因与方案

v1 错位根因：手工 `'Units','normalized'` 坐标 + `text` 绝对定位，字号/容器
尺寸变化即碰撞。老 UI 从不错位的原因：**uigridlayout 网格托管**（RowHeight/
ColumnWidth 声明式配平）+ uipanel 卡片 + put/choice/number 助手。方案 =
"基于原先的 UI 来改"：布局层照搬老骨架（1500×960 窗、outer 3×2、左栏
表单/按钮/评价卡/日志、右侧 3×2 四图+双卡、状态栏），内容语义保留 v1 全部
（臂/估计档/风剧本/速度、P(v) 谷图、时间线、能量、0xF2 字节、双表盘、风图）。

## 二、ds-executor 视觉迭代（P1–P6，均有像素测量证据）

| # | 问题 | 修复 |
| --- | --- | --- |
| P1 | 播放速度滑条刻度标签截断 | 表单行高 32→54、刻度 [.5 1 2 3 5]→[1 2 3 5] |
| P2 | 环境卡"放大"按钮压住轴刻度标签 | **uiaxes 直接放多行 grid 单元会伸出单元格**（机制性坑）→ 4 只 uiaxes 各包无边框 holder 面板入格 |
| P3 | P(v) 图例与曲线相擦 | 图例 northeast→northwest（两态均为空区） |
| P4 | 时间线图例与 v_cmd 尖峰相擦 | 图例改顶部横排（Orientation horizontal, Location north） |
| P5 | 底部 120px 空带、左右栏底边不齐 | 行高显式配平（左栏 {176,110,175,30,303}、右栏 {274,274,250}），两列底边对齐 y≈884 |
| P6 | 左栏顺序/空 readout 行 | 小字说明移入 readout 槽，顺序=表单→按钮→评价卡→说明→日志 |

排除项（查证无问题）：表盘 t=0 指针、0xF2 柱状与 S.frame() 逐字节一致、
命令谷 +4 = vMin 钳位正确值。

## 三、验证

- 渲染迭代 4 轮（`results/shot_a.png` t=0 / `shot_b.png` t=120s，exportapp
  口径——uifigure 不支持 saveas）；最终几何像素测量：两列底边对齐、无重叠、
  无截断、两态布局一致（固定行高）。
- `run_quad_demo_smoke` **PASS**（S-D1–S-D5：逐位确定性/白名单/组帧自洽/长推
  sane），smoke 仅改 saveas→exportapp 一行，门槛语义未动。
- 对外 API 未动：`fig=launch_quad_demo(visible)` + `getappdata(fig,'qdemo')`
  的 step/state/hist/frame/autostart；getState/getHist/getPol 保持具名嵌套
  （匿名按值捕获教训不复犯）。

## 四、经验入档（老账+新账）

1. **uiaxes 占多行 grid 单元会按偏好高度渲染并伸出单元格**（P2 根因）——
   uiaxes 入格必须包 holder 面板或锁死行高；
2. uifigure 不能 saveas，批处理截图用 **exportapp**（HANDOFF 旧账）；
3. yyaxis 重置 hold、patch 先于 line、timer 运行中禁改 Period——三账沿用；
4. 视觉迭代分工：ds-executor（带视觉）看图-改码-重渲染闭环，像素测量做
   两态一致性证据；本会话 visual-judge 账号连接不可用，ds 通道即视觉门。

## 边界

演示层不作验收证据（黑箱红线）；截图与中间放大图存 results/ 不入库；
`launch_3_6_demo.m` 未提交 UI fix（2026-09-09 长窗提示）照旧不动；冻结件零触碰
（ds-executor 收到禁改清单并遵守）。
