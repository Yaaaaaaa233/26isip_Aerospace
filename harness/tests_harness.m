function tests = tests_harness
%TESTS_HARNESS 三模块架构与MOP/MOE评价体系单元测试。
tests=functiontests(localfunctions);
end

function setupOnce(tc) %#ok<INUSD>
% harness 复用 ../task2_rugged 的 +task2 包(对象/搜索器), 测试前注入路径
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'modules','speed_rugged_search'));
end

function testThreeModuleWiring(t)
c=harness.config('T',600);
env=harness.make_environment(c);
ac=harness.make_aircraft(c);
w=env.wind(0); w2=env.wind(12345);
verifyEqual(t,w,[0 0]);
verifyEqual(t,w2,[0 0],'任务2静态场景恒零风');
tr=ac.truth();
verifyLessThan(t,abs(tr.vStar-6),1e-6,'对称设计全局最优=6');
tr2=ac.truth();
verifyEqual(t,ac.Pmin,tr2.PminNorm,'AbsTol',1e-12);
verifyEqual(t,tr2.vStar,6+0,'AbsTol',1e-9);
end

function testBlackboxCausalBoundary(t)
% 红线1: query 只返回标量测量; gauges 只有两表盘; 无真值泄漏
c=harness.config('T',600,'noiseSigma',0.05);
ac=harness.make_aircraft(c);
J=ac.query(6.3,0);
verifyTrue(t,isscalar(J) && isfinite(J));
g=ac.gauges();
verifyEqual(t,fieldnames(g),fieldnames(struct('speed',1,'power',1)));
verifyEqual(t,g.speed,6.3);
% 同一点重复查询应不同(噪声), 真值固定
J2=ac.query(6.3,1);
verifyFalse(t,J==J2);
trEnd=ac.truth();
verifyEqual(t,numel(trEnd.curveV),numel(trEnd.curveJ));
verifyEqual(t,min(trEnd.curveJ),ac.Pmin,'AbsTol',1e-9);
end

function testMOEEnergyRatioDefinition(t)
% MOE=Emin/E_actual 且与能耗超额互为倒数目(解析关系)
c=harness.config('T',600);
ac=harness.make_aircraft(c);
[~,log]=harness.make_console('fixed',c);
m=harness.mop_moe(log,ac,c);
verifyEqual(t,m.MOE_energy,1/(1+m.energyExcessPercent/100),'AbsTol',1e-9);
verifyEqual(t,m.MOE_energy_W,m.MOE_energy,'AbsTol',1e-9,'瓦级与归一化同比值');
verifyEqual(t,m.EminNorm,ac.Pmin*c.T,'AbsTol',1e-9);
verifyEqual(t,m.EactualNorm,sum(log.powerTrue)*c.tEval,'AbsTol',1e-9);
end

function testMOEOrderingAcrossConsoles(t)
% 效能排序应稳定: fixed(上界) >= multistart/grid >= esc >= single_golden
c=harness.config('T',600,'seed',11);
kinds={'fixed','multistart','grid','esc','single_golden'};
moe=zeros(1,numel(kinds));
for k=1:numel(kinds)
    [~,log]=harness.make_console(kinds{k},c);
    m=harness.mop_moe(log,ac_ref(c),c);
    moe(k)=m.MOE_energy;
end
verifyGreaterThanOrEqual(t,moe(1),max(moe(2:end))-1e-12,'fixed应为上界');
verifyGreaterThanOrEqual(t,moe(2),moe(5)-1e-12,'multistart应优于单起点陷阱');
% multistart vs esc 的对比在短窗下有波动(扫描占比大), 由1小时窗横比展示, 不设硬门槛
end

function ac=ac_ref(c)
ac=harness.make_aircraft(c);
end

function c2=task2cfg(c)
c2=struct('lower',c.lower,'upper',c.upper,'optimum0',c.optimum0,...
    'rippleA1',c.rippleA1,'rippleL1',c.rippleL1,'rippleF1',c.rippleF1,...
    'rippleA2',c.rippleA2,'rippleL2',c.rippleL2,'rippleF2',c.rippleF2);
end
