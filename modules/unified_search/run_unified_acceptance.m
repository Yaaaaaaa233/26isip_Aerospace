function summary = run_unified_acceptance(varargin)
%RUN_UNIFIED_ACCEPTANCE 统一程序验收：MOP/MOE 横比 + 能耗感知门槛。
%
% 用法: run_unified_acceptance / summary=run_unified_acceptance(...)
% 门槛只加在推荐方案 ea_multistart 上；基线如实横评不设门槛。
% 核心能耗主张(用户要求"考虑寻优消耗的能量, 完全遍历未必最好")的量化：
%   g3 ea 搜索步数 < multistart 全遍历步数
%   g4 1小时窗 ea MOE_energy > multistart MOE_energy
root=fileparts(mfilename('fullpath')); addpath(root);
cRef=usearch.config(varargin{:});
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests_unified.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
algorithms={'ea_multistart','multistart','tracker','grid','esc','fixed','single_golden'};
rows=cell(0,11);
% ---- A: 崎岖静态 20 种子(能耗开关开) ----
for name=algorithms
    for seed=11:30
        c=usearch.config(varargin{:},'seed',seed);
        scn=usearch.scenario('static',c);
        [log,~]=usearch.run_algorithm(name{1},scn,c);
        m=usearch.mop_moe(log,c);
        rows(end+1,:)={name{1},'static',seed,m.finalErr,m.regretPercent,...
            m.MOE_energy,m.energyExcessPercent,m.tSearchEvals,...
            sum(~strcmp(log.tag,'hold')),m.budgetUtilization,true}; %#ok<AGROW>
    end
end
% ---- B: 平移场景(EA与tracker) 10 种子 ----
for kind={'jumpUp','jumpDown','ramp','offset'}
    for seed=11:20
        for name={'ea_multistart','tracker'}
            c=usearch.config(varargin{:},'seed',seed);
            if strcmp(name{1},'tracker'), c=usearch.config(varargin{:},...
                'seed',seed,'rippleA1',0,'rippleA2',0,'noiseSigma',0); end
            scn=usearch.scenario(kind{1},c);
            [log,~]=usearch.run_algorithm(name{1},scn,c);
            m=usearch.mop_moe(log,c);
            tJ=c.shiftTime/c.tEval+1;
            inb=abs(log.estimate-log.optimumTrue)<=c.eps;
            kk=find(inb(tJ:end),1); rec=NaN; if ~isempty(kk), rec=kk-1; end
            rows(end+1,:)={name{1},kind{1},seed,m.finalErr,m.regretPercent,...
                m.MOE_energy,m.energyExcessPercent,rec,...
                sum(~strcmp(log.tag,'hold')),m.budgetUtilization,true}; %#ok<AGROW>
        end
    end
end
% ---- C: 能耗开关关档(ea, 静态, 5种子) ----
for seed=11:15
    c=usearch.config(varargin{:},'seed',seed,'energyAccounting',false);
    scn=usearch.scenario('static',c);
    [log,~]=usearch.run_algorithm('ea_multistart',scn,c);
    m=usearch.mop_moe(log,c);
    rows(end+1,:)={'ea_multistart','static',seed,m.finalErr,m.regretPercent,...
        m.MOE_energy,m.energyExcessPercent,m.tSearchEvals,NaN,...
        m.budgetUtilization,false}; %#ok<AGROW>
end
cases=cell2table(rows,'VariableNames',{'Algorithm','Scenario','Seed','FinalErr',...
    'RegretPercent','MOE_energy','EnergyExcessPercent','TSearchOrRecovery',...
    'SearchSteps','BudgetUtilization','EnergyOn'});
writetable(cases,fullfile(folder,'scenarios.csv'),'Encoding','UTF-8');
% ---- 1小时窗 MOE 横比(3种子) ----
mrows=cell(0,5);
for name={'ea_multistart','multistart','fixed'}
    for seed=11:13
        c=usearch.config(varargin{:},'seed',seed,'T',3600,'duration',3600,...
            'tailSteps',300,'shiftTime',1200);
        scn=usearch.scenario('static',c);
        [log,~]=usearch.run_algorithm(name{1},scn,c);
        m=usearch.mop_moe(log,c);
        mrows(end+1,:)={name{1},seed,m.MOE_energy,m.energyExcessPercent,m.EactualNorm}; %#ok<AGROW>
    end
end
moe=cell2table(mrows,'VariableNames',{'Algorithm','Seed','MOE_energy',...
    'EnergyExcessPercent','EactualNorm'});
writetable(moe,fullfile(folder,'moe_1h.csv'),'Encoding','UTF-8');
% ---- 门槛 ----
ea=cases(strcmp(cases.Algorithm,'ea_multistart') & strcmp(cases.Scenario,'static') & logical(col2n(cases,'EnergyOn')),:);
eaFE=col2n(ea,'FinalErr'); eaRG=col2n(ea,'RegretPercent'); eaMOE=col2n(ea,'MOE_energy');
ms=cases(strcmp(cases.Algorithm,'multistart') & strcmp(cases.Scenario,'static'),:);
msSS=col2n(ms,'SearchSteps');
eaSS=col2n(ea,'SearchSteps');
errVec=signedBias(varargin{:});   % 有符号跨种子偏置(FinalErr为绝对值)
recJU=recVals(cases,'ea_multistart','jumpUp');
recRD=recVals(cases,'tracker','jumpDown');
oneh=strcmp(moe.Algorithm,'ea_multistart'); moeEA=mean(moe.MOE_energy(oneh));
oneh2=strcmp(moe.Algorithm,'multistart'); moeMS=mean(moe.MOE_energy(oneh2));
checks=[...
    struct('item','ea 静态全局命中 >=18/20 (|err|<=0.4 且 regret<=1%)',...
        'pass',sum(eaFE<=0.4 & eaRG<=1)>=18),...
    struct('item','ea 跨种子系统偏置 |mean| <= 0.15 (对称设计, 精调窗口口径)',...
        'pass',abs(mean(errVec))<=0.15),...
    struct('item','ea 搜索步数 < multistart 全遍历步数 (全部种子)',...
        'pass',all(eaSS<msSS)),...
    struct('item','1小时窗: ea 平均MOE > multistart 平均MOE (能耗感知主张)',...
        'pass',moeEA>moeMS),...
    struct('item','ea jumpUp 恢复<=120步 且 >=9/10 种子',...
        'pass',nnz(recJU<=120&~isnan(recJU))>=9),...
    struct('item','ea ramp 末误差 >=9/10 种子 <=1.6 (慢漂为已知局限, 尾部种子如实记录)',...
        'pass',nnz(col2n(cases(strcmp(cases.Algorithm,'ea_multistart') & strcmp(cases.Scenario,'ramp'),:),'FinalErr')<=1.6)>=9),...
    struct('item','tracker(平坦无噪) jumpDown 恢复<=30步 >=9/10 种子',...
        'pass',nnz(recRD<=30&~isnan(recRD))>=9),...
    struct('item','能耗开关=关: MOE与能耗列全部NaN',...
        'pass',all(isnan(col2n(cases(~logical(col2n(cases,'EnergyOn')),:),'MOE_energy'))))];
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),...
    'gatesPassed',sum([checks.pass]),'gatesTotal',numel(checks),...
    'moeEA',moeEA,'moeMS',moeMS,'bias',mean(errVec));
writeReport(folder,cases,checks,summary,moe);
fprintf('性能门槛：%d/%d | MOE(1h): ea=%.4f multistart=%.4f\n',...
    summary.gatesPassed,summary.gatesTotal,moeEA,moeMS);
if summary.gatesPassed<summary.gatesTotal
    warning('usearch:Performance','Some gates missed; see report.');
end
end

function v=recVals(cases,algo,kind)
ix=strcmp(cases.Algorithm,algo)&strcmp(cases.Scenario,kind);
v=col2n(cases,'TSearchOrRecovery'); v=v(ix);
end

function v=col2n(T,name)
x=T.(name); if iscell(x), v=cell2mat(x); else, v=double(x); end
end

function b=signedBias(varargin)
% 有符号跨种子偏置(重跑ea静态20种子)
for seed=11:30
    c=usearch.config(varargin{:},'seed',seed);
    scn=usearch.scenario('static',c);
    lg=usearch.run_algorithm('ea_multistart',scn,c);
    e(seed-10)=lg.estimate(end)-lg.optimumTrue(end); %#ok<AGROW>
end
b=mean(e);
end

function writeReport(folder,cases,checks,summary,moe)
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 统一程序验收：任务1+2整合(平移×崎岖×MOP/MOE)\n\n生成时间：%s\n\n',...
    datestr(now,31));
fprintf(fid,'- 单元测试：%d/%d。\n- 性能门槛：%d/%d。\n\n',...
    summary.unitPassed,summary.unitTotal,summary.gatesPassed,summary.gatesTotal);
fprintf(fid,'## 门槛明细\n\n| 门槛 | 结果 |\n|---|---|\n');
for k=1:numel(checks)
    v='未过'; if checks(k).pass, v='通过'; end
    fprintf(fid,'| %s | %s |\n',checks(k).item,v);
end
fprintf(fid,'\n## 1小时窗 MOE 横比(崎岖静态)\n\n| 算法 | 种子 | MOE_energy | 能耗超额%% |\n|---|---:|---:|---:|\n');
for k=1:height(moe)
    fprintf(fid,'| %s | %d | %.4f | %.2f |\n',moe.Algorithm{k},moe.Seed(k),moe.MOE_energy(k),moe.EnergyExcessPercent(k));
end
fprintf(fid,'\nMOE_energy=Emin/E_actual∈(0,1]；fixed 为不可达上界参照。\n');
fprintf(fid,'\n完整逐场景见 scenarios.csv / moe_1h.csv（可由本脚本重建）。\n');
end
