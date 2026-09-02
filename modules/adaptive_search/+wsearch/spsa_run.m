function info = spsa_run(plant, p, n)
%SPSA_RUN 随机同步扰动逼近(Spall 1992)+占空比调度(事件触发ES思想)。
% 适配"双正交正弦风×圆周盘旋"时变最优的四项设计：
%   1) 探针间隔 2·spsaCk=3 与崎岖波长(λ1=6, λ2=2)整倍对齐，差分中
%      涟漪斜率精确相消(与 ea_run probeDelta 同源口径)，只余基线斜率；
%   2) +/− 探针相邻交错采样，两探针间风场漂移近似共模，差分相消；
%   3) 增益不随步数衰减(时变最优需要持续跟踪能力)，梯度 EWMA 压噪；
%   4) 占空比调度: 每 spsaPeriod 步只做一对探针(能耗≈探针驻点成本×
%      2/period)，其余步停在当前信念 v̂(hold)——把"持续激励"改成
%      "间歇激励"，搜索能耗大幅下降而跟踪能力保留(间歇期风漂由
%      下一次探针对的斜率证据修正)。
% 黑箱口径：只用 plant.q 测量(红线1)，不接触场景真值。
gE=0; v=p.initialSpeed; iter=0;
a=p.spsaGain; ck=p.spsaCk; alpha=p.spsaEwma;
while plant.count()<=n-2
    d=randi([0 1])*2-1;                      % Bernoulli ±1 同步扰动
    yp=plant.q(v+ck*d,'search'); plant.amendEstimate(v);
    ym=plant.q(v-ck*d,'search'); plant.amendEstimate(v);
    ghat=(yp-ym)/(2*ck*d);
    gE=alpha*ghat+(1-alpha)*gE;
    step=max(-p.spsaStepMax,min(p.spsaStepMax,-a*gE));
    v=min(max(v+step,p.lower+ck),p.upper-ck);
    iter=iter+1;
    holdUntil=min(n,plant.count()+p.spsaPeriod-2);   % 间歇hold(定界, 防滚动目标)
    while plant.count()<holdUntil
        plant.q(v,'hold'); plant.amendEstimate(v);
    end
end
while plant.count()<n
    plant.q(v,'hold'); plant.amendEstimate(v);
end
info=struct('best',v,'bestP',NaN,'iterations',iter,'gradEwma',gE,...
    'dutyCycle',2/p.spsaPeriod);
end
