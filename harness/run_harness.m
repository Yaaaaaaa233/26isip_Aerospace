function run_harness(varargin)
%RUN_HARNESS harness 入口：自动配置依赖路径后按需运行。
% 用法:
%   run_harness('demo')     三模块 1 小时窗 MOP/MOE 横比(results/mop_moe/)
%   run_harness('tests')    harness 单元测试(4项)
%   run_harness             两者都跑
% 依赖: ../task2_rugged 的 +task2 包(对象/搜索器复用), 自动加入路径。
root=fileparts(mfilename('fullpath')); addpath(root);
addpath(fullfile(root,'..','modules','speed_rugged_search'));
doAll=(nargin==0);
if doAll || any(strcmp(varargin,'tests'))
    r=runtests(fullfile(root,'tests_harness.m'));
    assertSuccess(r);
    fprintf('harness 单元测试 %d/%d 通过\n',sum([r.Passed]),numel(r));
end
if doAll || any(strcmp(varargin,'demo'))
    run_mop_moe_demo();
end
end
