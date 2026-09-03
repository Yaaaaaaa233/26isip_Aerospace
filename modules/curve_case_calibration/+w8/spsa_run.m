function info = spsa_run(plant, p, n)
%SPSA_RUN 随机同步扰动逼近(Spall 1992)+占空比调度(算法逻辑原样移植任务6)。
% 任务7差异: 全部查询经 w8.settled_q 指令就位包装器——±探针需等时延+限幅
% 过渡完成后测量, 就位时间 τ+|Δv|/amax 计入搜索能耗(这正是任务7要量化的
% 实际约束代价之一)。探针间隔2·spsaCk=3与涟漪波长整倍对齐等设计不变。
qs=w8.settled_q(plant,p,n);
gE=0; v=p.initialSpeed; iter=0;
a=p.spsaGain; ck=p.spsaCk; alpha=p.spsaEwma;
while plant.count()<=n-2
    d=randi([0 1])*2-1;                      % Bernoulli ±1 同步扰动
    yp=qs(v+ck*d,'search');
    if ~isfinite(yp), break; end
    ym=qs(v-ck*d,'search');
    if ~isfinite(ym), break; end
    ghat=(yp-ym)/(2*ck*d);
    gE=alpha*ghat+(1-alpha)*gE;
    step=max(-p.spsaStepMax,min(p.spsaStepMax,-a*gE));
    v=min(max(v+step,p.lower+ck),p.upper-ck);
    iter=iter+1;
    holdUntil=min(n,plant.count()+p.spsaPeriod-2);   % 间歇hold(定界, 防滚动目标)
    while plant.count()<holdUntil
        qs(v,'hold');
    end
end
while plant.count()<n
    plant.q(v,'hold'); plant.amendEstimate(v);
end
info=struct('best',v,'bestP',NaN,'iterations',iter,'gradEwma',gE,...
    'dutyCycle',2/p.spsaPeriod);
end
