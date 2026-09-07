%START_HERE 任务3.3标定后在线该用什么：一键打开动态演示面板。
% 曲线未知(黑盒调速→功率) × 风未知 × hybrid主角=首飞3→12全速度域标定(冻结曲线)
% + task2式在线风推断 × sweepcal/rl消融对照 × 空速=地速−风速 × 七种可选风场
% × MOE=纯能耗口径。含2026-09-08截断拟合边缘假谷修复(与+w34同源)。
root=fileparts(mfilename('fullpath'));
addpath(root);
launch_3_3_demo('on');
