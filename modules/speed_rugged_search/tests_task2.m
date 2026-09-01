function tests = tests_task2
%TESTS_TASK2 任务2单元测试：曲线真值、滤波性质、无偏移保证、算法行为、开关。
tests=functiontests(localfunctions);
end

function testCurveTruth(t)
c=task2.config();
[~,vG,PG,wells]=task2.power_map([],c,true);
verifyGreaterThan(t,numel(wells),2,'崎岖默认参数应产生至少3个局部极小');
verifyEqual(t,task2.power_map(vG,c),PG,'AbsTol',1e-9);
% 无崎岖时退化为调试二次曲线, 最优点恰在6
c0=task2.config('rippleA1',0,'rippleA2',0);
[~,vG0,PG0]=task2.power_map([],c0);
verifyLessThan(t,abs(vG0-6),0.01);
verifyEqual(t,PG0,1,'AbsTol',1e-9);
end

function testPlantDeterminismAndNoise(t)
c=task2.config('duration',200,'noiseSigma',0.05,'seed',7);
a=task2.run_algorithm('multistart',c); b=task2.run_algorithm('multistart',c);
verifyEqual(t,a.powerMeas,b.powerMeas);
verifyTrue(t,all(abs(a.powerTrue-a.powerMeas)>0),'sigma=5%时测量应几乎处处不等于真值');
end

function testFilterSymmetryZeroBias(t)
% 对称输入+中心对称滤波 -> 无相位偏移(无偏移保证第1条)
x=sin(linspace(0,4*pi,201))+0.0;
for method={'moving','gaussian','median','sg'}
    y=task2.apply_filter(x,method{1},11);
    [~,ix]=max(x); [~,iy]=max(y);
    verifyLessThan(t,abs(iy-ix),3,sprintf('%s中心对称',method{1}));
end
end

function testFilterKillsNoiseKeepsQuadratic(t)
% 滤波应显著压噪且不明显移动二次曲线argmin(小窗口)
c=task2.config('rippleA1',0,'rippleA2',0);
rng(3); vs=linspace(0,20,81);
meas=task2.power_map(vs,c).*(1+0.02*randn(1,81));
y=task2.apply_filter(meas,'moving',7);
verifyLessThan(t,std(y-meas),0.0195,'滤波后残差应小于噪声');
verifyLessThan(t,abs(vs(argmin(y))-6),1.2,'argmin不应远离真最优(无崎岖时)');
end

function testMultistartHitsGlobal(t)
for seed=[11 17]
    c=task2.config('seed',seed);
    [log,info]=task2.run_algorithm('multistart',c);
    m=task2.evaluate(log,info,c);
    verifyTrue(t,m.hitsGlobal,sprintf('seed%d 应命中全局(seed)',seed));
    verifyLessThan(t,m.finalErr,c.eps);
    verifyEqual(t,height(log),c.duration);
    verifyTrue(t,all(isfinite(log.estimate(~isnan(log.estimate)))));
end
end

function testSingleGoldenExpectedTrap(t)
% 单起点黄金分割在多峰上允许落入局部谷——这是消融对照, 只验证其结构完整
c=task2.config('seed',11);
[log,info]=task2.run_algorithm('single_golden',c);
verifyEqual(t,height(log),c.duration);
verifyTrue(t,abs(info.best-c.initialSpeed)<c.refineSpan*2+0.1,'单起点应停在初始速度邻域');
end

function testEscStructure(t)
c=task2.config('duration',300,'seed',5);
log=task2.run_algorithm('esc',c);
verifyTrue(t,all(strcmp(log.tag,'esc')));
verifyEqual(t,log.speed(1),10+0.5*sin(0.5*1),'AbsTol',1e-9,'ESC首步=初速+扰动');
end

function testGridScanCount(t)
c=task2.config('seed',3);
[~,info]=task2.run_algorithm('grid',c);
verifyEqual(t,info.scanSteps,round(20/c.gridResolution)+1);
end

function testFilterArgminAblation(t)
c=task2.config('seed',12);
[log,info]=task2.run_algorithm('filter_argmin',c);
verifyEqual(t,numel(unique(log.tag)),2,'仅scan与hold两个相位');
verifyTrue(t,abs(info.filteredArgmin-info.best)<1e-12);
end

function testEnergySwitchGating(t)
cOn=task2.config('seed',11);
[log,~]=task2.run_algorithm('multistart',cOn);
cOff=task2.config('seed',11,'energyAccounting',false);
mOn=task2.evaluate(log,struct('filterMethod','moving','filterW',7,'filteredArgmin',NaN),cOn);
mOff=task2.evaluate(log,struct('filterMethod','moving','filterW',7,'filteredArgmin',NaN),cOff);
verifyTrue(t,isfinite(mOn.energyExcessPercent));
verifyTrue(t,isnan(mOff.energyExcessPercent));
verifyEqual(t,mOn.finalErr,mOff.finalErr);
end

function testStructuralBiasSmall(t)
% 滤波器结构偏置: 对真值曲线滤波后argmin相对vG的漂移必须很小(无偏移保证)
c=task2.config();
[~,vG]=task2.power_map([],c);
vs=linspace(0,20,81); yt=task2.power_map(vs,c);
for method={'gaussian','sg'}   % 默认滤波器须紧门槛; moving/median偏置进验收对照表
    yf=task2.apply_filter(yt,method{1},7);
    verifyLessThan(t,abs(vs(argmin(yf))-vG),0.15,sprintf('%s结构偏置',method{1}));
end
end

function testConfigValidation(t)
verifyError(t,@() task2.config('filterW',8),'task2:Config');      % 偶数窗口
verifyError(t,@() task2.config('filterMethod','box'),'task2:Config');
verifyError(t,@() task2.config('energyAccounting',1),'task2:Config');
verifyError(t,@() task2.config('duration',115),'task2:Config');   % 短于scanN(61)+tail(60)
end

function testBudgetEdges(t)
for dur=[200 400]
    c=task2.config('duration',dur,'tailSteps',min(60,dur-140),'scanN',min(81,dur-119));
    [log,~]=task2.run_algorithm('multistart',c);
    verifyEqual(t,height(log),dur);
end
end

function s=argmin(x)
[~,i]=min(x); s=i;
end
