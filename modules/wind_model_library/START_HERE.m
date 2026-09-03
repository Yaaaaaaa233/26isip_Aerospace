%START_HERE 任务9风场模型库：一键打开三模块动态演示面板。
% 七种可选风场(恒定/双正弦/方波/三角/湍流/复合/扇区, 选中即预览)
% × 空速=地速+风速语义 × 曲线case标定 × 真实约束。
root=fileparts(mfilename('fullpath'));
addpath(root);
launch_task9_demo('on');
