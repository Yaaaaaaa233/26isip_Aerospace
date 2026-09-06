function out = compare_baseline(name, scn, c)
%COMPARE_BASELINE 算法 vs 开环基线(固定速度平飞)的同对象、同预算、同种子横比。
% 用户需求4: 以开环为对照组量化"算法优化带来的MOE提升"。输出:
%   out.moeAlgo / out.moeBase      双方 MOE_energy
%   out.overallAlgo / out.overallBase  双方综合效能
%   out.liftAbsolute               MOE提升 = MOE_algo − MOE_base
%   out.liftPercent                相对能耗下降 = 100(E_base−E_algo)/E_base
%   out.excessAlgo / out.excessBase    全程能耗超额%
% 开环基线与算法经历完全相同的对象(风场/半径/时延/限幅)与随机种子。
if ~any(strcmp(name,{'est','windinfer','sweepcal','rl','purerl'}))  % 2026-09-07精简后口径(各任务按需含purerl/sweepcal/rl)
    error('w21:CompareBaseline','Baseline comparison needs an adaptive algorithm, got %s.',name);
end
cB=c; cB.seed=c.seed;
[logA,~]=w21.run_algorithm(name,scn,c);
mA=w21.mop_moe(logA,c);
[logB,~]=w21.run_algorithm('openloop',scn,cB);
mB=w21.mop_moe(logB,cB);
out=struct('name',name,'scenario',scn.kind,'seed',c.seed,...
    'moeAlgo',mA.MOE_energy,'moeBase',mB.MOE_energy,...
    'overallAlgo',mA.MOE.overall,'overallBase',mB.MOE.overall,...
    'liftAbsolute',mA.MOE_energy-mB.MOE_energy,...
    'liftPercent',100*(mB.EactualNorm-mA.EactualNorm)/mB.EactualNorm,...
    'excessAlgo',mA.energyExcessPercent,'excessBase',mB.energyExcessPercent,...
    'logAlgo',logA,'logBase',logB,'mAlgo',mA,'mBase',mB);
end
