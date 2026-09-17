function info = openloop_run(plant, p, n)
%OPENLOOP_RUN 开环控制基线(用户需求4)：固定速度平飞, 不带任何反馈/估计。
% 速度 = openLoopV(默认=名义设计点 optimum0=6, 台架标定可得, 不含风场知识)。
% 作用: 量化"算法优化带来的MOE提升"——所有自适应算法与其同对象、同预算、
% 同种子横比, 提升=MOE_algo − MOE_openloop 与能耗相对下降。
% 与任务6 'fixed'(评价上界参照)的区别: fixed 是"全程停在真值最优"的
% 上界; openloop 是工程上真实可实现的固定速度巡航, 风致漂移它照单全收。
v=p.openLoopV;
while plant.count()<n
    plant.q(v,'hold'); plant.amendEstimate(v);
end
info=struct('best',v,'bestP',NaN,'evals',0,'mode','openloop');
end
