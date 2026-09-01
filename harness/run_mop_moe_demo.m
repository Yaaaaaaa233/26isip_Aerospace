function report = run_mop_moe_demo()
%RUN_MOP_MOE_DEMO 三模块闭环演示：同一评价体系横比五种控制台(1小时窗口)。
% environment(风) -> aircraft(双表盘黑箱) -> console(算法)；harness评价MOE/MOP。
% 1小时窗口演示默认用加速口径(T=3600, tEval=1s, 总3600评估步)，
% 全部算法共用同一预算——能耗比、能耗超额在同一口径下横比。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results','mop_moe'); if ~exist(folder,'dir'), mkdir(folder); end
c=harness.config();
env=harness.make_environment(c);
ac=harness.make_aircraft(c);
truth=ac.truth();
kinds={'multistart','grid','single_golden','esc','fixed'};
rows=cell(0,9);
logs=struct();
for k=1:numel(kinds)
    kind=kinds{k};
    [console,log]=harness.make_console(kind,c);
    m=harness.mop_moe(log,ac,c);
    rows(end+1,:)={kind,m.MOE_energy,m.MOE_energy_W,m.finalErr,m.regretPercent,...
        m.energyExcessPercent,m.tSearchEvals,m.holdFraction,m.budgetUtilization}; %#ok<AGROW>
    logs.(kind)=log;
end
T=cell2table(rows,'VariableNames',{'Console','MOE_energy','MOE_energy_W',...
    'FinalErr','RegretPercent','EnergyExcessPercent','TSearchEvals',...
    'HoldFraction','BudgetUtilization'});
T=sortrows(T,'MOE_energy','descend');
writetable(T,fullfile(folder,'mop_moe.csv'),'Encoding','UTF-8');
% 摘要(降序=效能从高到低)
fprintf(['\n== MOP/MOE 横比(1小时窗口, Pmin=%.4f norm / %.0f W, Emin=%.0f W-equivalent) ==\n'],...
    truth.PminNorm,truth.PminW,truth.PminNorm*c.T);
for k=1:height(T)
    fprintf('%-14s MOE=%.4f  能耗超额=%5.2f%%  末误差=%.3f m/s  稳态超额=%5.3f%%  锁定占空=%.2f\n',...
        T.Console{k},T.MOE_energy(k),T.EnergyExcessPercent(k),T.FinalErr(k),...
        T.RegretPercent(k),T.HoldFraction(k));
end
fprintf(['\n解读: MOE=Emin/E_actual∈(0,1]，fixed(全程停在最优)是算法不可达的\n' ...
    '上界参照；multistart以最低搜索代价逼近上界。\n']);
report=struct('table',T,'env',env,'aircraft',ac,'config',c);
save(fullfile(folder,'mop_moe.mat'),'-struct','report');
end
