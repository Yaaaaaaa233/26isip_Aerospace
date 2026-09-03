%START_HERE 任务8功率曲线case标定：一键打开三模块动态演示面板。
% case1 95% / case2 90% / case3 85%(谷底/悬停)，参考DJI Mavic Pro实测曲线。
root=fileparts(mfilename('fullpath'));
addpath(root);
launch_task8_demo('on');
