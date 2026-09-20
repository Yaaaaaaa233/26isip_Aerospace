function paths_q1()
%Q39.PATHS_Q1 Q1 运行路径装配。权威 +w36 = 3.8 号包(滑动电压参照 + 真相位句柄,
% moe38 口径), 最后 addpath 保证其优先于任何已入径的 3.6 冻结包。
root = fileparts(fileparts(mfilename('fullpath')));       % modules/platform_link_39
repo = fileparts(fileparts(root));                        % 26isip_Aerospace 仓库根
addpath(root);                                        % tests_q1 / run_q1_*
addpath(fullfile(repo, 'models', 'plane'));
addpath(fullfile(repo, 'harness'));
addpath(fullfile(repo, 'modules', 'platform_link_38'));   % 权威 +w36 最后入径
end
