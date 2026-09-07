function info = openloop_run(plant, p, n)
%OPENLOOP_RUN 开环控制基线: 固定桨比 r=openLoopR(默认1.0, PX4默认等转速分配)运行。
% 不带任何反馈/估计; 干扰(γ场)引起的 r* 漂移照单全收。作用: 量化"算法优化带来的
% MOE提升"——所有自适应算法与其同对象、同预算、同种子横比。
% 基准无干扰档的固有超额 = P(1)/P(r*)−1 ≈ 1/case−1 ≈ 5.3%(case=0.95, 飞试节能口径)。
r=p.openLoopR;
while plant.count()<n
    plant.q(r,'hold'); plant.amendEstimate(r);
end
info=struct('best',r,'bestP',NaN,'evals',0,'mode','openloop');
end
