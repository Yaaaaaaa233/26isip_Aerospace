function info = gtrack_run(plant, p, n)
%GTRACK_RUN 小行程交替dither梯度跟踪(任务7新增第6策略)。
% 设计动机(与任务7对象口径匹配, 见验收报告的横比依据):
%   1) 实际半径(50-150 m)下最优以整圈周期 T=2πR/v 快速漂移, 任务6宽行程
%      探针法(spsa±1.5/qnewton宽stencil)就位慢、行程能耗高, 带宽不足;
%   2) J0的涟漪谷深0.034、半宽约0.7——底部平坦, |u−V*|<=0.5 m/s的额外
%      能耗<0.5%, 因此只需把跟踪误差压在谷内, 不需要精确锁定argmin;
%   3) 小行程交替dither(±gtDither=±0.3)的就位时间 τ+0.6/amax≈0.6s,
%      每步一步即可测完——时延与限幅下依然保持逐步测量的跟踪带宽;
%   4) 相邻±对的风漂近似共模, 差分自动相消; 梯度EWMA压噪后积分控制
%      v ← v − gtGain·gE 把驻点拉回谷底。
% 因果口径(红线1): 只用带噪测量与自身指令。
qs=w8.settled_q(plant,p,n);
d=p.gtDither; k=p.gtGain; alpha=p.gtEwma;
v=p.initialSpeed; gE=0; sPrev=NaN; yPrev=NaN; pairs=0; kStep=0;
while plant.count()<n-1
    kStep=kStep+1;
    s=1-2*mod(kStep,2);                    % ±1 逐步交替
    y=qs(v+s*d,'track');
    if ~isfinite(y), break; end
    if sPrev==-s && ~isnan(yPrev)          % 凑齐一对相邻±测量
        g=(yPrev-y)/(2*d*sPrev);           % sPrev=+1: (P+−P−)/(2d)
        gE=alpha*g+(1-alpha)*gE;
        v=min(max(v-k*gE,p.lower+d),p.upper-d);
        pairs=pairs+1;
    end
    sPrev=s; yPrev=y;
end
while plant.count()<n
    plant.q(v,'hold'); plant.amendEstimate(v);
end
info=struct('best',v,'bestP',NaN,'gradEwma',gE,'pairs',pairs,'mode','gtrack');
end
