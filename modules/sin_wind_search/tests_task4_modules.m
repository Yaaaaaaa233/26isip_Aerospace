function tests = tests_task4_modules
%TESTS_TASK4 统一程序单元测试：对象/平移/黑箱边界/MOE定义/算法行为/开关。
tests=functiontests(localfunctions);
end

function setupOnce(tc) %#ok<INUSD>
% 测试自身即位于 unified_search, 包父目录已在路径; 显式化以便独立调用
addpath(fileparts(mfilename('fullpath')));
end

function testConfigValidation(t)
verifyError(t,@() wsearch.config('filterW',8),'wsearch:Config');
verifyError(t,@() wsearch.config('duration',115),'wsearch:Config');
verifyError(t,@() wsearch.config('energyAccounting',1),'wsearch:Config');
c=wsearch.config('jumpDownDx',-2.3);   % 带符号字段合法
verifyEqual(t,c.jumpDownDx,-2.3);
end

function testSymmetricBaseCurve(t)
c=wsearch.config();
y=wsearch.base_curve(linspace(0,20,4001),c);
verifyMinimum(t,y);
[J0,J0min]=wsearch.base_curve(6,c);
verifyEqual(t,J0,J0min,'AbsTol',1e-12);
verifyEqual(t,J0min,1-c.rippleA1-c.rippleA2,'AbsTol',1e-12);
% 崎岖置零退化为纯调试二次曲线
c0=wsearch.config('rippleA1',0,'rippleA2',0);
y0=wsearch.base_curve(linspace(0,20,4001),c0);
verifyMinimum(t,y0);
[~,i0]=min(y0); verifyLessThan(t,abs(i0-1201),3,'纯二次最优在v=6');
end

function testScenarioShiftTruth(t)
c=wsearch.config('shiftTime',100,'windAmp',0,'windBias',0);
scn=wsearch.scenario('jumpUp',c);
[dx,dy]=wsearch.shift_truth(scn,[99 101]);
verifyEqual(t,dx,[0 2.7]); verifyEqual(t,dy,[0 0]);
scn2=wsearch.scenario('offset',c);
[dx2,dy2]=wsearch.shift_truth(scn2,[99 101]);
verifyEqual(t,dx2,[0 0]); verifyEqual(t,dy2,[0 c.dyOffset]);
scn3=wsearch.scenario('ramp',c);
[dx3,~]=wsearch.shift_truth(scn3,[60 120 180]);
verifyEqual(t,dx3(1),0); verifyEqual(t,dx3(3),c.rampDx);
verifyLessThan(t,abs(dx3(2)-c.rampDx/2),1e-9);
end

function testPlantCausalBoundary(t)
c=wsearch.config('duration',200,'tailSteps',60,'noiseSigma',0.05,'seed',7);
scn=wsearch.scenario('jumpUp',c);
plant=wsearch.make_plant(scn,c);
verifyEqual(t,plant.count(),0);
J=plant.q(6.3,'hold');
verifyTrue(t,isscalar(J)&&isfinite(J));
plant.amendEstimate(6.3);
verifyEqual(t,plant.count(),1);
% 预算耗尽后拒绝查询(因果预算边界)
for k=2:c.duration, plant.q(6.3,'hold'); end
verifyError(t,@() plant.q(6.3,'hold'),'wsearch:Plant');
end

function testMOEDefinitionAndSwitch(t)
c=wsearch.config('duration',200,'tailSteps',60,'seed',11,'windAmp',0,'windBias',0);
scn=wsearch.scenario('static',c);
[log,~]=wsearch.run_algorithm('fixed',scn,c);
m=wsearch.mop_moe(log,c);
verifyEqual(t,m.EminNorm,sum(log.minPowerTrue)*c.tEval,'AbsTol',1e-9);
verifyEqual(t,m.EactualNorm,sum(log.powerTrue)*c.tEval,'AbsTol',1e-9);
verifyEqual(t,m.MOE_energy,1/(1+m.energyExcessPercent/100),'AbsTol',1e-9);
verifyEqual(t,m.MOE_energy_W,m.MOE_energy,'AbsTol',1e-9);
verifyTrue(t,m.MOE_consistency);
cOff=wsearch.config('duration',200,'tailSteps',60,'seed',11,'energyAccounting',false);
mOff=wsearch.mop_moe(log,cOff);
verifyTrue(t,isnan(mOff.MOE_energy)&&isnan(mOff.energyExcessPercent));
verifyEqual(t,mOff.finalErr,m.finalErr);
end

function testFixedUpperBoundOnStatic(t)
c=wsearch.config('duration',200,'tailSteps',60,'seed',3,'windAmp',0,'windBias',0);
scn=wsearch.scenario('static',c);
[logF,~]=wsearch.run_algorithm('fixed',scn,c);
mF=wsearch.mop_moe(logF,c);
verifyEqual(t,mF.MOE_energy,1,'AbsTol',1e-9);
end

function testEAStaticHitsGlobal(t)
for seed=11:16
    c=wsearch.config('seed',seed,'windAmp',0,'windBias',0);
    scn=wsearch.scenario('static',c);
    [log,~]=wsearch.run_algorithm('ea_multistart',scn,c);
    m=wsearch.mop_moe(log,c);
    verifyLessThan(t,m.finalErr,0.4,sprintf('seed%d',seed));
    verifyLessThan(t,m.regretPercent,1,sprintf('seed%d regret',seed));
end
end

function testEAJumpRecovery(t)
c=wsearch.config('seed',11,'windAmp',0,'windBias',0);
scn=wsearch.scenario('jumpUp',c);
[log,~]=wsearch.run_algorithm('ea_multistart',scn,c);
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
    c=wsearch.config('seed',seed,'windAmp',0,'windBias',0);
    scn=wsearch.scenario('offset',c);
    [log,info]=wsearch.run_algorithm('ea_multistart',scn,c);
    verifyLessThanOrEqual(t,info.escalations,2,sprintf('seed%d 升级次数过多',seed));
    verifyLessThan(t,abs(log.estimate(end)-log.optimumTrue(end)),0.4,...
        sprintf('seed%d dy-only末误差',seed));
end
end

function testEAFewerSearchStepsThanMultistart(t)
c=wsearch.config('seed',11,'windAmp',0,'windBias',0);
scn=wsearch.scenario('static',c);
[logE,~]=wsearch.run_algorithm('ea_multistart',scn,c);
[logM,~]=wsearch.run_algorithm('multistart',scn,c);
sE=sum(~strcmp(logE.tag,'hold'));
sM=sum(~strcmp(logM.tag,'hold'));
verifyLessThan(t,sE,sM,'能耗感知方案搜索步数必须少于全遍历');
verifyLessThan(t,sE,160,'EA搜索步数上限');
end

function testTrackerFlatJumps(t)
% tracker设计点: 平坦曲线+无噪声(任务1口径)
c=wsearch.config('seed',11,'rippleA1',0,'rippleA2',0,'noiseSigma',0,'windAmp',0,'windBias',0);
scn=wsearch.scenario('jumpUp',c);
[log,~]=wsearch.run_algorithm('tracker',scn,c);
tJump=c.shiftTime/c.tEval+1;
inband=abs(log.estimate-log.optimumTrue)<=0.5;
kk=find(inband(tJump:end),1);
verifyTrue(t,~isempty(kk)&&kk-1<=30,'tracker跳变30步内恢复');
end

function testEADeterminism(t)
c=wsearch.config('seed',13);
scn=wsearch.scenario('jumpUp',c);
a=wsearch.run_algorithm('ea_multistart',scn,c);
b=wsearch.run_algorithm('ea_multistart',scn,c);
verifyEqual(t,a.powerTrue,b.powerTrue);
verifyEqual(t,a.estimate,b.estimate);
end

function testBudgetEdges(t)
for dur=[150 240]
    c=wsearch.config('duration',dur,'tailSteps',40,'scanN',min(61,dur-50),'shiftTime',min(120,dur-60));
    scn=wsearch.scenario('jumpUp',c);
    [log,~]=wsearch.run_algorithm('ea_multistart',scn,c);
    verifyEqual(t,height(log),dur);
end
end

function verifyMinimum(t,y)
[~,i]=min(y);
verifyLessThan(t,abs(i-1201),100,'全局最优应在v=6(索引1201)附近(对称设计)');
end

function testWindTruthModel(t)
% 任务4环境模型: W(t)=A sin(w t)+B, 周期偏移=风投影×航向; 零风退化
c=wsearch.config('windAmp',2,'windOmega',0.1,'windBias',3,'circlePeriod',80,'windDirDeg',0);
scn=wsearch.scenario('static',c);
[W,dx0,dy0,psi0]=wsearch.wind_truth(scn,0);
verifyEqual(t,W(1),3,'AbsTol',1e-12);        % t=0: W=B=3
verifyEqual(t,psi0(1),0);                    % 航向迎风
verifyEqual(t,dx0(1),c.windDxGain*3,'AbsTol',1e-12);
verifyEqual(t,dy0(1),c.windDyGain*3,'AbsTol',1e-12);
[W40,dx40,dy40,psih]=wsearch.wind_truth(scn,40);  % 半圈: 航向180, 投影反向
verifyEqual(t,psih(1),pi,'AbsTol',1e-9);
verifyEqual(t,W40(1),c.windAmp*sin(0.1*40)+3,'AbsTol',1e-12);
verifyEqual(t,dx40(1),c.windDxGain*W40(1)*cos(pi),'AbsTol',1e-9);
verifyEqual(t,dy40(1),c.windDyGain*W40(1)*cos(pi),'AbsTol',1e-9);
[~,dxq,dyq,psiq]=wsearch.wind_truth(scn,20); % 1/4圈: 侧风, 零投影
verifyEqual(t,psiq(1),pi/2,'AbsTol',1e-9);
verifyEqual(t,dxq(1),0,'AbsTol',1e-12); verifyEqual(t,dyq(1),0,'AbsTol',1e-12);
c0=wsearch.config('windAmp',0,'windBias',0);
scn0=wsearch.scenario('static',c0);
[Wn,dxN,dyN,psiN]=wsearch.wind_truth(scn0,[0 40]);  % 零风兼容
verifyEqual(t,Wn,[0 0]); verifyEqual(t,dxN,[0 0]); verifyEqual(t,dyN,[0 0]);
verifyEqual(t,psiN,[0 0]);
end

function testWindZeroEqualsUnified(t)
% 风速=0时 fixed(停基准最优)应为不可达上界 MOE=1
c=wsearch.config('duration',200,'tailSteps',60,'seed',3,'windAmp',0,'windBias',0);
scn=wsearch.scenario('static',c);
[log,~]=wsearch.run_algorithm('fixed',scn,c);
m=wsearch.mop_moe(log,c);
verifyEqual(t,m.MOE_energy,1,'AbsTol',1e-9);
end

function testWindBreaksFixedController(t)
% 风场圆周下 v*(t) 周期移动: 全程停基准最优必然持续损失(MOE<1)
c=wsearch.config('duration',400,'tailSteps',60,'seed',3,'windAmp',0,'windBias',3);
scn=wsearch.scenario('static',c);
[log,~]=wsearch.run_algorithm('fixed',scn,c);
m=wsearch.mop_moe(log,c);
verifyLessThan(t,m.MOE_energy,0.999,'风场下固定速度不应到达上界');
rngOff=abs(log.optimumTrue-6);
verifyGreaterThan(t,max(rngOff),0.3,'真值最优应随航向周期偏移');
end

function testTrackerTracksWindCircle(t)
% tracker在风场圆周上(平坦无噪设计点+风速3): 末段平均跟踪误差有界
c=wsearch.config('seed',11,'rippleA1',0,'rippleA2',0,'noiseSigma',0,...
    'windAmp',0,'windBias',3,'circlePeriod',80);
scn=wsearch.scenario('static',c);
[log,~]=wsearch.run_algorithm('tracker',scn,c);
tail=81:400;
err=abs(log.estimate(tail)-log.optimumTrue(tail));
verifyLessThan(t,mean(err),1.0,'tracker末段平均跟踪误差(滞后为已知局限)');
end

function testEAWindStaticTailError(t)
% ea_multistart在崎岖+风场圆周: 末段平均误差有界且少于全遍历步数
c=wsearch.config('seed',11,'windAmp',0,'windBias',3,'circlePeriod',80);
scn=wsearch.scenario('static',c);
[log,~]=wsearch.run_algorithm('ea_multistart',scn,c);
tail=341:400;
err=abs(log.estimate(tail)-log.optimumTrue(tail));
verifyLessThan(t,mean(err,'omitnan'),1.0,'ea末段平均跟踪误差(种子相关 Basin恢复有差异, 门槛1.0)');
sE=sum(~strcmp(log.tag,'hold'));
[logM,~]=wsearch.run_algorithm('multistart',scn,c);
sM=sum(~strcmp(logM.tag,'hold'));
verifyLessThan(t,sE,sM,'EA搜索步数 < 全遍历');
end

function testWindJumpCombined(t)
% 风场圆周 + jumpUp叠加: 平移跳变仍须被恢复(环境偏移不掩盖任务1能力)
c=wsearch.config('seed',11,'windAmp',0,'windBias',3,'circlePeriod',80);
scn=wsearch.scenario('jumpUp',c);
[log,~]=wsearch.run_algorithm('ea_multistart',scn,c);
tJump=c.shiftTime/c.tEval+1;
inband=abs(log.estimate-log.optimumTrue)<=c.eps;
kk=find(inband(tJump:end),1);
verifyTrue(t,~isempty(kk),'风场+跳变后必须重新入带');
verifyLessThan(t,kk-1,260,'风场+跳变恢复步数');
end
