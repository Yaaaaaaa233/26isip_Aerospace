function run_q1_matrix(chunkId)
%RUN_Q1_MATRIX Q1 敏感性矩阵分块入口(每分块独立 MATLAB 会话, R6 缓解)。
% 运行: matlab -batch "cd('modules/platform_link_39'); run_q1_matrix('S3')"
% 分块定义(预注册单一事实源): +q39/q1_opt.m。建议顺序:
%   ANCHOR -> XCHECK -> S3 -> S1m3/S1p3/S1m5/S1p5 -> S2m07/S2p07/S2m14/S2p14/
%   S2m28/S2p28 -> S4p1/S4m1 -> S5d1/S5d2/S5d5 -> RERUN
q39.paths_q1();
q39.run_q1_chunk(chunkId);
end
