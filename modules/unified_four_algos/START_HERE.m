%START_HERE 任务3.4四算法整合横比：一键打开动态演示面板。
% 曲线未知(黑盒调速→功率) × 风未知 × 首飞3→12全速度域双向快扫标定 × 四算法横比
% (sweepcal全速域标定+精化 / rl仿真器预训练+微调 / purerl纯奖励RL / hybrid标定+风推断)
% × 空速=地速−风速 × 七种可选风场 × MOE=纯能耗口径。
% 含2026-09-08截断拟合边缘假谷修复：样本支撑谷底选择(标定块支撑)+û*锚定信赖域。
root=fileparts(mfilename('fullpath'));
addpath(root);
launch_3_4_demo('on');
