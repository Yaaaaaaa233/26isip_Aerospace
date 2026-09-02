function tests = tests_wind
%TESTS_WIND 环境风场研究模块单元测试（TASKS_1_5_ROUTE §3-5 交付口径）。
tests=functiontests(localfunctions);
end

function setupOnce(tc) %#ok<INUSD>
addpath(fileparts(mfilename('fullpath')));
end

function testPowerCurveAnchors(t)
c=wind.config();
verifyEqual(t,wind.power_curve(c.Vstar,c),c.Pstar,'AbsTol',1e-12);
verifyEqual(t,wind.power_curve(0,c),1,'AbsTol',1e-12);
xs=linspace(0.01,1,50);
verifyTrue(t,all(diff(wind.power_curve(xs*c.Vstar,c))<0),'P0在[0,V*)递减');
xs2=linspace(1,2,50);
verifyTrue(t,all(diff(wind.power_curve(xs2*c.Vstar,c))>0),'P0在(V*,2V*]递增');
% 数值逆: 双支各自精确往返(谷两侧)
Plo=wind.power_curve([4 5 5.5 6],c);
verifyLessThan(t,max(abs(wind.inv_power(Plo,c,'low')-[4 5 5.5 6])),2e-3,...
    '低速支持续往返');
Phi=wind.power_curve([7 8 9 10],c);
hi=wind.inv_power(Phi,c,'high');
verifyLessThan(t,max(abs(hi-[7 8 9 10])),2e-3,'高速支持续往返');
end

function testWindTruthModes(t)
tt=[0 10 40];
c=wind.config('windMode','const','windSpeed',3);
[wx,wy]=wind.wind_truth(c,tt);
verifyEqual(t,wx,[3 3 3],'AbsTol',1e-12); verifyEqual(t,wy,[0 0 0],'AbsTol',1e-12);
c=wind.config('windMode','sin','windAmp',2,'windOmega',0.1,'windBias',3);
[wx,wy]=wind.wind_truth(c,tt);
verifyLessThan(t,max(abs(wx-(2*sin(0.1*tt)+3))),1e-12);
verifyEqual(t,wy,[0 0 0],'AbsTol',1e-12);
c=wind.config('windMode','dual','windAmp',2,'windOmega',0.1,'windBias',3,...
    'windAmpY',1,'windOmegaY',0.2,'windBiasY',1);
[wx,wy]=wind.wind_truth(c,tt);
verifyLessThan(t,max(abs(wy-(1*sin(0.2*tt)+1))),1e-12);
% 风向角旋转90°: x向风转到+y
c90=wind.config('windMode','const','windSpeed',3,'windDirDeg',90);
[wx90,wy90]=wind.wind_truth(c90,0);
verifyLessThan(t,abs(wx90),1e-12); verifyLessThan(t,abs(wy90-3),1e-12);
% 风参数全0 = 无风退化
c0=wind.config('windMode','dual','windAmp',0,'windBias',0,'windAmpY',0,'windBiasY',0);
[wx0,wy0]=wind.wind_truth(c0,tt);
verifyEqual(t,wx0,[0 0 0]); verifyEqual(t,wy0,[0 0 0]);
end

function testAirspeedIdentity(t)
c=wind.config();
v=[4 7 10]; tt=[0 20 60];
a=wind.airspeed(v,c,tt);
% 直接矢量计算对照: u = v·t̂ + w
for k=1:3
    th=[cos(a.psi(k)) sin(a.psi(k))];
    uvec=v(k)*th+[a.wx(k) a.wy(k)];
    verifyLessThan(t,abs(a.u2(k)-dot(uvec,uvec)),1e-9);
    verifyLessThan(t,abs(a.q(k)-dot(th,[a.wx(k) a.wy(k)])),1e-12);
end
end

function testAnalyticConstWindSchedule(t)
% 路线公式核心性质: 恒风下 v*(t) 以盘旋周期周期化;
% 逆风段地速调高、顺风段调低; 可行时 Pmin≡P*
c=wind.config('windMode','const','windSpeed',3,'vLower',1.0);
tt=linspace(0,c.circlePeriod,200);
sa=wind.analytic_sched(c,tt);
verifyTrue(t,all(sa.feasible),'|w|=3<V* 应全程可行');
verifyLessThan(t,max(abs(sa.Pmin-c.Pstar)),1e-9,'可行且未裁剪时Pmin≡P*');
% 周期性: v*(0)=v*(T)
verifyLessThan(t,abs(sa.v(1)-sa.v(end)),1e-9);
% 风沿+x: 航向逆风(ψ=π)时地速最高, 顺风(ψ=0)最低
[~,iHead]=max(sa.v); [~,iTail]=min(sa.v);
verifyLessThan(t,abs(tt(iHead)-c.circlePeriod/2),1.0,'逆风段在半圈处');
verifyTrue(t,tt(iTail)<1.0||tt(iTail)>c.circlePeriod-1.0,'顺风段在整圈处');
verifyGreaterThan(t,sa.v(iHead),sa.v(iTail)+3,'逆风地速应显著高于顺风');
end

function testFeasibilityInfeasibleCase(t)
% |w|=7>V*=6.3: 横向风分量超V*的航向不可达P*; 对齐航向仍可达。
% 全周期可行性条件 max|w|<V* 不满足 → 部分航向 infeasible。
c=wind.config('windMode','const','windSpeed',7.0,'vLower',0.5);
tt=linspace(0,c.circlePeriod,200);
sa=wind.analytic_sched(c,tt);
verifyTrue(t,any(sa.feasible)&&any(~sa.feasible),...
    '|w|=7>V*: 顺风/逆风对齐段可行、横风段不可行');
% 可行航向(未裁剪)处 Pmin≡P*
inb=sa.feasible & sa.v==sa.vRaw;
verifyLessThan(t,max(abs(sa.Pmin(inb)-c.Pstar)),1e-9);
% 横风段(ψ≈90°) 不可行: Pmin=P0(|w⊥|)>P*(横向分量成为空速下限)
[~,iPerp]=min(abs(mod(rad2deg(sa.psi),360)-90));
verifyGreaterThan(t,sa.Pmin(iPerp),c.Pstar+0.002,'横风段功率高于P*');
% 最差点在顺风对齐段(v*负值被下界裁剪的代价)
[~,iWorst]=max(sa.Pmin);
verifyLessThan(t,min(abs(sa.psi(iWorst)),abs(sa.psi(iWorst)-2*pi)),0.06,...
    '最差航向应在顺风对齐段(v*<vLower被裁剪)');
verifyGreaterThan(t,max(sa.Pmin),c.Pstar+0.008,'裁剪段存在功率代价');
% 全周期可行性: |w|=3<V* 时应全程可行
cF=wind.config('windMode','const','windSpeed',3.0,'vLower',1.0);
saF=wind.analytic_sched(cF,tt);
verifyTrue(t,all(saF.feasible),'|w|<V* 全程可行');
end

function testDpFreeMatchesAnalytic(t)
for mode={'const','sin','dual'}
    c=wind.config('windMode',mode{1},'dpGridN',161);
    dp=wind.dp_verify(c,inf);
    verifyLessThan(t,dp.relDiff,1e-4,...
        sprintf('%s风 DP(无限速)应与解析一致',mode{1}));
end
end

function testDpRateLimitedInterface(t)
c=wind.config('dpGridN',81);
dpF=wind.dp_verify(c,inf);
dpR=wind.dp_verify(c,0.15);
verifyGreaterThanOrEqual(t,dpR.meanPowerDp,dpF.meanPowerDp-1e-9,...
    '限速DP不优于无限速');
verifyGreaterThan(t,dpR.meanPowerDp,dpF.meanPowerDp,'严格限速应付出代价');
verifyLessThan(t,(dpR.meanPowerDp-dpF.meanPowerDp)/dpF.meanPowerDp,0.05,...
    '限速0.15 m/s的超额应在5%内(接口演示量级)');
end

function testUniformBaseline(t)
c=wind.config();
uB=wind.uniform_baseline(c);
sa=wind.analytic_sched(c,linspace(0,c.circlePeriod,200));
mPan=mean(sa.Pmin);
verifyGreaterThanOrEqual(t,uB.vU,c.vLower-1e-9);
verifyLessThanOrEqual(t,uB.vU,c.vUpper+1e-9);
verifyGreaterThan(t,uB.meanPower,mPan-1e-9,'匀速不应优于逐点解析最优');
verifyLessThan(t,(uB.meanPower-mPan)/mPan,0.10,'默认风下匀速超额应<10%');
end

function testKnownPolicyUpperBound(t)
c=wind.config('duration',400,'tailSteps',60,'seed',11);
[log,info]=wind.run_policy('known',c);
verifyEqual(t,height(log),400);
verifyEqual(t,info.moe.MOE_energy,1,'AbsTol',1e-9,'已知风=解析调度应达上界');
verifyLessThan(t,info.moe.rmsVErr,1e-9);
end

function testOnlineConstWindConverges(t)
c=wind.config('windMode','const','windSpeed',3,'duration',400,...
    'tailSteps',60,'seed',11);
[log,info]=wind.run_policy('online',c);
m=info.moe;
verifyLessThan(t,m.windEstErr,0.6,'恒风下风估计末段误差应<0.6 m/s');
verifyGreaterThan(t,m.MOE_energy,0.99,'恒风在线调度应接近上界');
end

function testInfoStructureOrdering(t)
% 三档信息结构(1小时窗): known > online > uniform(离线匀速) >= blind
res=struct();
for mode={'known','online','blind','uniform'}
    moe=0;
    for s=11:12
        c=wind.config('duration',720,'tailSteps',120,'seed',s);
        [~,info]=wind.run_policy(mode{1},c);
        moe=moe+info.moe.MOE_energy;
    end
    res.(mode{1})=moe/2;
end
verifyEqual(t,res.known,1,'AbsTol',1e-9);
verifyGreaterThan(t,res.online,res.blind,'在线估计风应优于不知风(风速信息价值)');
verifyGreaterThan(t,res.uniform,res.blind,'离线最优匀速也应优于不知风搜索');
verifyGreaterThanOrEqual(t,res.online,res.uniform-0.005,...
    '在线变速调度相对离线匀速(如实口径, 允许小裕度)');
end

function testBlindPolicyBoundsAndBudget(t)
c=wind.config('duration',400,'tailSteps',60,'seed',13);
[log,info]=wind.run_policy('blind',c);
verifyEqual(t,height(log),400,'预算用满');
verifyGreaterThanOrEqual(t,min(log.vCmd),c.vLower-1e-9);
verifyLessThanOrEqual(t,max(log.vCmd),c.vUpper+1e-9);
verifyTrue(t,isfinite(info.moe.MOE_energy)&&info.moe.MOE_energy>0.9);
end

function testMopMoeConsistency(t)
c=wind.config('duration',400,'tailSteps',60,'seed',11);
[log,~]=wind.run_policy('online',c);
m=wind.mop_moe(log,c);
verifyEqual(t,m.MOE_energy,1/(1+m.energyExcessPercent/100),'AbsTol',1e-9);
verifyEqual(t,m.EminNorm,sum(wind.analytic_sched(c,log.time).Pmin)*c.tEval,...
    'AbsTol',1e-9);
end

function testDeterminism(t)
c=wind.config('seed',13,'duration',400,'tailSteps',60);
a=wind.run_policy('online',c);
b=wind.run_policy('online',c);
verifyEqual(t,a.powerTrue,b.powerTrue);
verifyEqual(t,a.vCmd,b.vCmd);
end

function testConfigStructBase(t)
c=wind.config('seed',5,'windMode','sin');
c2=wind.config(c,'windOmega',0.2);
verifyEqual(t,c2.seed,5,'结构体底座继承');
verifyEqual(t,c2.windOmega,0.2);
verifyEqual(t,c2.windMode,'sin');
verifyError(t,@() wind.config('badKey',1),'wind:Config');
end
