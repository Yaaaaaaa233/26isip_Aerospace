function tests = tests_task1
%TESTS_TASK1 任务1单元测试：算法正确性、平移判别、预算边界、能耗开关。
tests=functiontests(localfunctions);
end

function testConfigSwitch(t)
c=task1.config('energyAccounting',false);
verifyFalse(t,c.energyAccounting);
verifyTrue(t,task1.config().energyAccounting);
verifyError(t,@() task1.config('energyAccounting',1),'task1:Config');
end

function testPowerMapTranslation(t)
for curve={'debug','cubic'}
    c=task1.config('curve',curve{1});
    x=linspace(c.lower,c.upper,40001); y=task1.power_map(x,c);
    [~,k]=min(y); verifyLessThan(t,abs(x(k)-c.optimum0),0.01);
    if strcmp(curve{1},'cubic'), verifyEqual(t,y(k),c.minimumRatio,'AbsTol',1e-9);
    else, verifyEqual(t,y(k),1,'AbsTol',1e-9); end
    % 严格平移: 曲线平移2.7后最优点右移2.7、最小值不变
    y2=task1.power_map(x-2.7,c); [~,k2]=min(y2);
    verifyLessThan(t,abs(x(k2)-(c.optimum0+2.7)),0.01);
    verifyEqual(t,y2(k2),y(k),'AbsTol',1e-12);
end
end

function testGoldenSearch(t)
c=task1.config();
s=task1.golden_search(@(v) task1.power_map(v,c),c.lower,c.upper,0.02,60);
verifyLessThan(t,abs(s.x-c.optimum0),0.05);
verifyLessThan(t,s.evals,26);
verifyLessThan(t,diff(s.bracket),0.05);
end

function testBrentMatchesFminbnd(t)
c=task1.config();
s=task1.brent_search(@(v) task1.power_map(v,c),c.lower,c.upper,0.02,60);
[xf,~]=fminbnd(@(v) task1.power_map(v,c),c.lower,c.upper,...
    optimset('TolX',1e-8,'OutputFcn',[]));
verifyLessThan(t,abs(s.x-xf),1e-3);
verifyLessThan(t,s.evals,17);
end

function testBrentNoSlowerThanGolden(t)
c=task1.config();
sb=task1.brent_search(@(v) task1.power_map(v,c),c.lower,c.upper,0.02,60);
sg=task1.golden_search(@(v) task1.power_map(v,c),c.lower,c.upper,0.02,60);
verifyLessThanOrEqual(t,sb.evals,sg.evals);
verifyLessThan(t,sb.evals,15);
end

function testTernarySearch(t)
c=task1.config();
s=task1.ternary_search(@(v) task1.power_map(v,c),c.lower,c.upper,0.02,60);
verifyLessThan(t,abs(s.x-c.optimum0),0.05);
verifyLessThanOrEqual(t,s.evals,45);
end

function testGridScan(t)
c=task1.config();
s=task1.grid_scan(@(v) task1.power_map(v,c),c.lower,c.upper,c.gridResolution);
verifyLessThan(t,abs(s.x-c.optimum0),c.gridResolution/2+1e-9);
verifyEqual(t,s.evals,round((c.upper-c.lower)/c.gridResolution)+1);
end

function testPlantShiftTruth(t)
c=task1.config('duration',400);
scn=task1.scenario('jumpUp',c); plant=task1.make_plant(scn,c);
for k=1:c.duration
    plant.q(7.0,'hold'); plant.amendEstimate(7.0);
end
log=plant.table();
verifyEqual(t,log.optimumTrue(120),c.optimum0,'AbsTol',1e-12);
verifyEqual(t,log.optimumTrue(121),c.optimum0+2.7,'AbsTol',1e-12);
% 真实功率按平移后曲线计算, 与 power_map(v-dx) 一致
dx=2.7*(log.time>=120);
verifyEqual(t,log.powerTrue,task1.power_map(log.speed-dx,c),'AbsTol',1e-12);
end

function testSearchThenLockStructure(t)
c=task1.config('duration',200,'tailSteps',40);
scn=task1.scenario('static',c);
[log,info]=task1.run_algorithm('brent',scn,c);
verifyEqual(t,height(log),c.duration);
verifyTrue(t,all(strcmp(log.tag(1:info.searchEvals),'search')));
verifyTrue(t,all(strcmp(log.tag(info.searchEvals+1:end),'hold')));
verifyLessThan(t,abs(log.estimate(end)-c.optimum0),0.05);
end

function testTrackerRecoversAfterDxJump(t)
c=task1.config('duration',240,'tailSteps',40);
scn=task1.scenario('jumpUp',c);
[log,info]=task1.run_algorithm('tracker',scn,c);
m=task1.evaluate(log,scn,c);
verifyGreaterThanOrEqual(t,info.researchCount,1);
verifyLessThan(t,m.finalErr,0.05);
verifyLessThan(t,m.recoverySteps,31);
verifyTrue(t,all(isfinite(log.estimate)));
end

function testTrackerIgnoresPureOffset(t)
c=task1.config('duration',240,'tailSteps',40);
scn=task1.scenario('offset',c);
[~,info]=task1.run_algorithm('tracker',scn,c);
verifyEqual(t,info.researchCount,0);
end

function testTrackerFollowsRamp(t)
c=task1.config('duration',260,'tailSteps',40);
scn=task1.scenario('ramp',c);
[log,info]=task1.run_algorithm('tracker',scn,c);
verifyGreaterThanOrEqual(t,info.researchCount,1);
verifyLessThan(t,abs(log.estimate(end)-log.optimumTrue(end)),0.15);
end

function testEnergySwitchGating(t)
c=task1.config('duration',200,'tailSteps',40);
scn=task1.scenario('static',c);
[log,~]=task1.run_algorithm('brent',scn,c);
mOn=task1.evaluate(log,scn,task1.config('duration',200,'tailSteps',40,'energyAccounting',true));
mOff=task1.evaluate(log,scn,task1.config('duration',200,'tailSteps',40,'energyAccounting',false));
verifyTrue(t,isfinite(mOn.energyExcessPercent) && mOn.energyExcessPercent>0);
verifyTrue(t,isnan(mOff.energyExcessPercent));
verifyEqual(t,mOn.evalsToEps,mOff.evalsToEps);
end

function testDeterminism(t)
c=task1.config('duration',200,'tailSteps',40);
scn=task1.scenario('jumpUp',c);
a=task1.run_algorithm('tracker',scn,c); b=task1.run_algorithm('tracker',scn,c);
verifyEqual(t,a.powerTrue,b.powerTrue);
verifyEqual(t,a.speed,b.speed);
verifyEqual(t,a.tag,b.tag);
end

function testEscBaselineConverges(t)
c=task1.config('duration',400,'tailSteps',60);
scn=task1.scenario('static',c);
[log,~]=task1.run_algorithm('esc',scn,c);
verifyLessThan(t,abs(log.estimate(end)-c.optimum0),0.15);
verifyTrue(t,all(strcmp(log.tag,'esc')));
end

function testTrackerBudgetEdges(t)
% 短预算下不得越过评估上限、不得死循环(由测试超时保障)
for dur=[80 100 240]
    c=task1.config('duration',dur,'tailSteps',min(40,dur-40),...
        'maxSearchEval',min(60,dur-20));
    scn=task1.scenario('jumpUp',c);
    [log,~]=task1.run_algorithm('tracker',scn,c);
    verifyEqual(t,height(log),dur);
    verifyTrue(t,all(isfinite(log.estimate)));
end
end
