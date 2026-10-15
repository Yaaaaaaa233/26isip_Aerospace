# 2026-10-15 展示面板 v4：整体回贴老 UI 骨架 + 增量绘图（改动收敛 & 流畅性）

> 执行：ZCode 重构 + ds-executor MATLAB 测量/截图；本版起 ZCode 自带视觉
> （叶安开启），视觉判读由 ZCode 直接做，ds-executor 只跑命令。
> 结论先行：v3 反馈"改动太大、运行不流畅"（叶安）→ v4 把**布局与运行模型
> 整体回贴老 UI**（`modules/platform_link/launch_3_6_demo.m`，只读参考）：
> v3-v4 差异收敛为"内容换四旋翼语义，骨架不动"；卡顿根因（每拍 cla+重建
> legend 全量重画）改为老 UI 的**一次建图元 + 每帧只推 XData/YData +
> `drawnow limitrate`**。smoke 五门原样全过；热态一拍 43.5 ms（预算 150 ms）。

## 一、两条反馈的根因

**改动太大**：v3 虽用 uigridlayout，但骨架仍是自创结构——左栏 5 行显式行高
{176,110,175,30,303}、无模块切换按钮、操作钮 2 行、评价卡 5 行、axes 各包
holder 面板、无 GIF 导出/载入报告/清空日志。老 UI 是 6 行动态配平
（resizeLayout 按窗高派生）+ 模块切换按钮 + 操作钮 3 行 + 评价卡 6 行 +
readout + 日志——逐项对比后差异面过大。

**运行不流畅**：量化定位（ds-executor 实测）：`S.step(300)` 面板层 2.67 s vs
物理 0.38 s——v3 每拍 `cla` 6 轴 + `plot` 重建 + `legend` 重建（uiaxes 上
legend 构建是重操作），timer 0.15 s 周期根本喂不饱。老 UI 流畅的机制：
`setupPanels` 一次建好全部 line/patch/text 图元（含 legend），`redraw` 每帧
只 set XData/YData + `drawnow limitrate`（长窗还有 ≤800 点降采样）。

## 二、v4 回贴清单（骨架逐项同构，内容换 quad 语义）

| 老 UI 骨架 | v4 |
| --- | --- |
| 头部大标题（15pt 粗体） | 同（P̂=V·I/谷涌现/命令谷 R7/白名单 G-P2/演示口径） |
| 模块切换按钮 ×3（控制台\|飞机模型\|环境模型）+ setView/highlightButtons | 同构照搬 |
| 滚动表单（choice/number/checkbox/速度滑条） | 同构（控制策略/估计档/风剧本/任务窗/初速/3 复选/滑条） |
| 操作钮 3 行：播放暂停重置末帧 / 导出PNG导出GIF / 载入报告清空日志 | 同构（载入按钮=载入P3证据） |
| 红框评价卡 6 行 + readout + 日志框 | 同构（6 行=Ê/v/P̂/命令谷/t/油门组） |
| 右侧 3×2（4 轴 + 飞机模型双表盘卡 + 环境模型卡）+ 放大 ⤢ | 同构（表盘=地速左/功率右，老 UI 顺序） |
| resizeLayout（SizeChangedFcn 按窗高派生行高） | 照搬（v3 的显式行高配平废弃） |
| setupPanels 一次建图元 + redraw 推数据 + drawnow limitrate | 照搬（含 ≤800 点降采样） |

GIF 导出照搬老 UI 帧循环（resize 到 1000×680 + rgb2ind 128）；timer 巡进
保留演示链逐步推进（tick→air_quad_tick），与老 UI 的 cursor 巡进按内容等价。

## 三、量化验证

- **流畅性**：热态 `S.step(300)` 0.39 s（v3 冷态 3.05 s 含面板层 2.67 s）；
  播放一拍（30 步物理 + 增量 redraw）**43.5 ms**，timer 预算 150 ms，3 倍余量。
- **smoke S-D1–S-D5 全过**：det 1 / frame 1 / vCmd_end 8.00 / E 2.574 Wh
  （S-D2 两次独立启动逐位、S-D4 0xF2 组帧自洽——API/确定性契约未动）。
- **像素对照（老 UI vs v4，同一扫描脚本）**：卡片边框行 y=542/562/791 两图
  逐行相同、左右栏底起点 y=737/695 两图相同、标题带文本行位相同——v4 右列
  几何与老 UI 逐像素对齐，无溢出无空带（此前"标签压卡片"为缩放错觉）。
- 自查修复 4 处：`hist.vc_` 笔误、`windAt(st.t)(1)` 链式索引非法（R2022b 不
  支持）、`envPanel.Text` 误设面板标题、stView 推断→照老 UI 的 curView 变量。

## 四、口径与红线（不变）

演示层黑箱红线不作可引用数据源；P(v) 仍只加载 E1 证据 CSV 不重算；信息面
白名单逐调用断言保留（G-P2）；known=oracle 显式声明；est_model vi/l1/l0；
`air_quad.slx` 与既有 .slx 零触碰；`launch_3_6_demo.m` 只读参考（其工作区
diff 仍是 2026-09-09 长窗提示的既有未提交修改，照旧不提交）。

## 五、证据与文件

- 代码：`models/plane_quad/launch_quad_demo.m`（v4 整文件回贴，~600 行）。
- 冒烟：`models/plane_quad/results/quad_demo_smoke.csv`（开发级，不入库）。
- 截图对照：临时目录（oldui_shot/qdemo_v4_shot + 裁剪），不入库。
- API 契约：`S = getappdata(fig,'qdemo')` 的 step/state/hist/policy/frame/
  autostart 不变；qdemo_start.m 启动器不动。

剩余队列不变：电流采样器规格/质量（老师）→ 多臂适配（最后）→ E3/B 组样张。
