%START_HERE 任务3.1曲线未知在线寻优：一键打开三模块动态演示面板。
% 曲线未知(黑盒调速→功率) × 风未知 × 首飞3→12全速度域快扫标定(sweepcal主角)
% × RL在线策略梯度对照 × 空速=地速−风速 × 七种可选风场 × MOE=纯能耗口径。
root=fileparts(mfilename('fullpath'));
addpath(root);
launch_3_1_demo('on');
