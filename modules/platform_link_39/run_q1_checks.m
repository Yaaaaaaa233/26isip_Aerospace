function summary = run_q1_checks()
%RUN_Q1_CHECKS Q1 机器验收入口(单元门 M1 估计器一致性 + 估计器单元测试 + M5 短程
% 确定性冒烟 + S3 离线分解曲线)。不跑 3600s 矩阵(入口见 run_q1_matrix.m)。
% 运行: cd modules/platform_link_39 && run_q1_checks
q39.paths_q1();
root = fileparts(mfilename('fullpath'));
folder = fullfile(root, 'results');
if ~exist(folder, 'dir'), mkdir(folder); end
unit = runtests(fullfile(root, 'tests_q1.m'));
fprintf('单元测试：%d/%d 通过\n', sum([unit.Passed]), numel(unit));
out = q39.trim_curve(folder); %#ok<NASGU>
summary = struct('unitPassed', sum([unit.Passed]), 'unitTotal', numel(unit), ...
    'trim', out);
end
