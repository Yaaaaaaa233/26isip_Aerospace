function tests = tests_unified
%TESTS_UNIFIED 统一程序单元测试：对象/平移/黑箱边界/MOE定义/算法行为/开关。
tests=functiontests(localfunctions);
end

function setupOnce(tc) %#ok<INUSD>
% 测试自身即位于 unified_search, 包父目录已在路径; 显式化以便独立调用
addpath(fileparts(mfilename('fullpath')));
end

function testConfigValidation(t)
verifyError(t,@() usearch.config('filterW',8),'usearch:Config');
verifyError(t,@() usearch.config('duration',115),'usearch:Config');
verifyError(t,@() usearch.config('energyAccounting',1),'usearch:Config');
c=usearch.config('jumpDownDx',-2.3);   % 带符号字段合法
verifyEqual(t,c.jumpDownDx,-2.3);
end

function testSymmetricBaseCurve(t)
c=usearch.config();
y=usearch.base_curve(linspace(0,20,4001),c);
verifyMinimum(t,y);
[J0,J0min]=usearch.base_curve(6,c);
verifyEqual(t,J0,J0min,'AbsTol',1e-12);
verifyEqual(t,J0min,1-c.rippleA1-c.rippleA2,'AbsTol',1e-12);
% 崎岖置零退化为纯调试二次曲线
c0=usearch.config('rippleA1',0,'rippleA2',0);
y0=usearch.base_curve(linspace(0,20,4001),c0);
verifyMinimum(t,y0);
[~,i0]=min(y0); verifyLessThan(t,abs(i0-1201),3,'纯二次最优在v=6');
end

function testScenarioShiftTruth(t)
c=usearch.config('shiftTime',100);
scn=usearch.scenario('jumpUp',c);
[dx,dy]=usearch.shift_truth(scn,[99 101]);
verifyEqual(t,dx,[0 2.7]); verifyEqual(t,dy,[0 0]);
scn2=usearch.scenario('offset',c);
[dx2,dy2]=usearch.shift_truth(scn2,[99 101]);
verifyEqual(t,dx2,[0 0]); verifyEqual(t,dy2,[0 c.dyOffset]);
scn3=usearch.scenario('ramp',c);
[dx3,~]=usearch.shift_truth(scn3,[60 120 180]);
verifyEqual(t,dx3(1),0); verifyEqual(t,dx3(3),c.rampDx);
verifyLessThan(t,abs(dx3(2)-c.rampDx/2),1e-9);
end

function testPlantCausalBoundary(t)
c=usearch.config('duration',200,'tailSteps',60,'noiseSigma',0.05,'seed',7);
scn=usearch.scenario('jumpUp',c);
plant=usearch.make_plant(scn,c);
verifyEqual(t,plant.count(),0);
J=plant.q(6.3,'hold');
verifyTrue(t,isscalar(J)&&isfinite(J));
plant.amendEstimate(6.3);
verifyEqual(t,plant.count(),1);
% 预算耗尽后拒绝查询(因果预算边界)
for k=2:c.duration, plant.q(6.3,'hold'); end
verifyError(t,@() plant.q(6.3,'hold'),'usearch:Plant');
end

function testMOEDefinitionAndSwitch(t)
c=usearch.config('duration',200,'tailSteps',60,'seed',11);
scn=usearch.scenario('static',c);
[log,~]=usearch.run_algorithm('fixed',scn,c);
m=usearch.mop_moe(log,c);
verifyEqual(t,m.EminNorm,sum(log.minPowerTrue)*c.tEval,'AbsTol',1e-9);
verifyEqual(t,m.EactualNorm,sum(log.powerTrue)*c.tEval,'AbsTol',1e-9);
verifyEqual(t,m.MOE_energy,1/(1+m.energyExcessPercent/100),'AbsTol',1e-9);
verifyEqual(t,m.MOE_energy_W,m.MOE_energy,'AbsTol',1e-9);
verifyTrue(t,m.MOE_consistency);
cOff=usearch.config('duration',200,'tailSteps',60,'seed',11,'energyAccounting',false);
mOff=usearch.mop_moe(log,cOff);
verifyTrue(t,isnan(mOff.MOE_energy)&&isnan(mOff.energyExcessPercent));
verifyEqual(t,mOff.finalErr,m.finalErr);
end

function testFixedUpperBoundOnStatic(t)
c=usearch.config('duration',200,'tailSteps',60,'seed',3);
scn=usearch.scenario('static',c);
[logF,~]=usearch.run_algorithm('fixed',scn,c);
mF=usearch.mop_moe(logF,c);
verifyEqual(t,mF.MOE_energy,1,'AbsTol',1e-9);
end

function testEAStaticHitsGlobal(t)
for seed=11:16
    c=usearch.config('seed',seed);
    scn=usearch.scenario('static',c);
    [log,~]=usearch.run_algorithm('ea_multistart',scn,c);
    m=usearch.mop_moe(log,c);
    verifyLessThan(t,m.finalErr,0.4,sprintf('seed%d',seed));
    verifyLessThan(t,m.regretPercent,1,sprintf('seed%d regret',seed));
end
end

function testEAJumpRecovery(t)
c=usearch.config('seed',11);
scn=usearch.scenario('jumpUp',c);
[log,~]=usearch.run_algorithm('ea_multistart',scn,c);
tJump=c.shiftTime/c.tEval+1;
inband=abs(log.estimate-log.optimumTrue)<=c.eps;
kk=find(inband(tJump:end),1);
verifyTrue(t,~isempty(kk),'跳变后必须重新入带');
verifyLessThan(t,kk-1,120,'恢复步数过长');
verifyLessThan(t,abs(log.estimate(end)-log.optimumTrue(end)),0.4);
end

function testEAOffsetAbsorbedWithinBudget(t)
% dy-only平移: 升级一次后重找同谷(设计行为), 误差必须仍在带内且不反复升级
for seed=11:14
    c=usearch.config('seed',seed);
    scn=usearch.scenario('offset',c);
    [log,info]=usearch.run_algorithm('ea_multistart',scn,c);
    verifyLessThanOrEqual(t,info.escalations,2,sprintf('seed%d 升级次数过多',seed));
    verifyLessThan(t,abs(log.estimate(end)-log.optimumTrue(end)),0.4,...
        sprintf('seed%d dy-only末误差',seed));
end
end

function testEAFewerSearchStepsThanMultistart(t)
c=usearch.config('seed',11);
scn=usearch.scenario('static',c);
[logE,~]=usearch.run_algorithm('ea_multistart',scn,c);
[logM,~]=usearch.run_algorithm('multistart',scn,c);
sE=sum(~strcmp(logE.tag,'hold'));
sM=sum(~strcmp(logM.tag,'hold'));
verifyLessThan(t,sE,sM,'能耗感知方案搜索步数必须少于全遍历');
verifyLessThan(t,sE,160,'EA搜索步数上限');
end

function testTrackerFlatJumps(t)
% tracker设计点: 平坦曲线+无噪声(任务1口径)
c=usearch.config('seed',11,'rippleA1',0,'rippleA2',0,'noiseSigma',0);
scn=usearch.scenario('jumpUp',c);
[log,~]=usearch.run_algorithm('tracker',scn,c);
tJump=c.shiftTime/c.tEval+1;
inband=abs(log.estimate-log.optimumTrue)<=0.5;
kk=find(inband(tJump:end),1);
verifyTrue(t,~isempty(kk)&&kk-1<=30,'tracker跳变30步内恢复');
end

function testEADeterminism(t)
c=usearch.config('seed',13);
scn=usearch.scenario('jumpUp',c);
a=usearch.run_algorithm('ea_multistart',scn,c);
b=usearch.run_algorithm('ea_multistart',scn,c);
verifyEqual(t,a.powerTrue,b.powerTrue);
verifyEqual(t,a.estimate,b.estimate);
end

function testBudgetEdges(t)
for dur=[150 240]
    c=usearch.config('duration',dur,'tailSteps',40,'scanN',min(61,dur-50),'shiftTime',min(120,dur-60));
    scn=usearch.scenario('jumpUp',c);
    [log,~]=usearch.run_algorithm('ea_multistart',scn,c);
    verifyEqual(t,height(log),dur);
end
end

function verifyMinimum(t,y)
[~,i]=min(y);
verifyLessThan(t,abs(i-1201),100,'全局最优应在v=6(索引1201)附近(对称设计)');
end
