function summary = run_q3_checks()
%RUN_Q3_CHECKS Q3 机器验收入口(单元门: L1 估计器自洽/配平域闭合/测量链接线/
% M7 双口径恒等式/因果结构门/l1 短程确定性)。不跑 3600s 冒烟(入口见
% run_q3_smoke 调用说明)。运行: cd modules/platform_link_39 && run_q3_checks
q39.paths_q1();
root = fileparts(mfilename('fullpath'));
folder = fullfile(root, 'results');
if ~exist(folder, 'dir'), mkdir(folder); end
unit = runtests(fullfile(root, 'tests_q3.m'));
fprintf('单元测试：%d/%d 通过\n', sum([unit.Passed]), numel(unit));
summary = struct('unitPassed', sum([unit.Passed]), 'unitTotal', numel(unit));
end
