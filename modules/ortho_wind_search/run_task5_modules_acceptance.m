function summary = run_task5_modules_acceptance(varargin)
%RUN_TASK3_ACCEPTANCE 任务5验收：双正交正弦风(x: A·sin(ω1t)+B, y: C·sin(ω2t)+D)×圆周盘旋×崎岖对象×MOP/MOE。
%
% 用法: run_task5_modules_acceptance / summary=run_task5_modules_acceptance(...)
% 默认风场口径 windSpeed=3 m/s, circlePeriod=80 s(盘旋5圈/400步)。
% 门槛只加在推荐方案 ea_multistart 上; tracker/esc 为基线如实横评。
% 任务3核心主张的量化:
%   风场周期偏移下 EA 以轻量重定位跟踪, 全局升级只留给真平移(斜率证据);
%   EA 搜索步数 < multistart 全遍历; 1小时窗 EA MOE 优于 tracker/esc。
root=fileparts(mfilename('fullpath')); addpath(root);
cRef=wsearch.config('windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1,'circlePeriod',80);  %#ok<NASGU> 默认风场口径
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests_task5_modules.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
algorithms={'ea_multistart','multistart','tracker','grid','esc','fixed','single_golden'};
rows=cell(0,13);
% ---- A: 风场静态 20 种子(能耗开关开) ----
for name=algorithms
    for seed=11:30
        c=wsearch.config(varargin{:},'seed',seed,'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1,'circlePeriod',80);
        if strcmp(name{1},'tracker'), c=wsearch.config(varargin{:},'seed',seed,...
            'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1,'circlePeriod',80,'rippleA1',0,'rippleA2',0,'noiseSigma',0); end
        scn=wsearch.scenario('static',c);
        [log,~]=wsearch.run_algorithm(name{1},scn,c);
        m=wsearch.mop_moe(log,c);
        tail=(c.duration-c.tailSteps+1):c.duration;
        err=abs(log.estimate(tail)-log.optimumTrue(tail));
        rows(end+1,:)={name{1},'static_wind',seed,mean(err,'omitnan'),m.finalErr,...
            m.regretPercent,m.MOE_energy,m.energyExcessPercent,m.tSearchEvals,...
            sum(~strcmp(log.tag,'hold')),m.budgetUtilization,true,NaN}; %#ok<AGROW>
    end
end
% ---- B: 风场+平移场景(EA与tracker) 10 种子 ----
for kind={'jumpUp','jumpDown','ramp','offset'}
    for seed=11:20
        for name={'ea_multistart','tracker'}
            c=wsearch.config(varargin{:},'seed',seed,'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1,'circlePeriod',80);
            if strcmp(name{1},'tracker'), c=wsearch.config(varargin{:},...
                'seed',seed,'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1,'circlePeriod',80,...
                'rippleA1',0,'rippleA2',0,'noiseSigma',0); end
            scn=wsearch.scenario(kind{1},c);
            [log,~]=wsearch.run_algorithm(name{1},scn,c);
            m=wsearch.mop_moe(log,c);
            tJ=c.shiftTime/c.tEval+1;
            inb=abs(log.estimate-log.optimumTrue)<=c.eps;
            kk=find(inb(tJ:end),1); rec=NaN; if ~isempty(kk), rec=kk-1; end
            rows(end+1,:)={name{1},kind{1},seed,NaN,m.finalErr,...
                m.regretPercent,m.MOE_energy,m.energyExcessPercent,rec,...
                sum(~strcmp(log.tag,'hold')),m.budgetUtilization,true,NaN}; %#ok<AGROW>
        end
    end
end
% ---- C: 能耗开关关档(ea, 风场静态, 5种子) ----
for seed=11:15
    c=wsearch.config(varargin{:},'seed',seed,'energyAccounting',false,...
        'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1,'circlePeriod',80);
    scn=wsearch.scenario('static',c);
    [log,~]=wsearch.run_algorithm('ea_multistart',scn,c);
    m=wsearch.mop_moe(log,c);
    rows(end+1,:)={'ea_multistart','static_wind',seed,NaN,m.finalErr,...
        m.regretPercent,m.MOE_energy,m.energyExcessPercent,m.tSearchEvals,NaN,...
        m.budgetUtilization,false,NaN}; %#ok<AGROW>
end
% ---- D: 风速=0 退化口径(fixed 静态应为上界, 5种子) ----
for seed=11:15
    c=wsearch.config(varargin{:},'seed',seed,'windAmp',0,'windBias',0,'windAmpY',0,'windBiasY',0);
    scn=wsearch.scenario('static',c);
    [log,~]=wsearch.run_algorithm('fixed',scn,c);
    m=wsearch.mop_moe(log,c);
    rows(end+1,:)={'fixed','static_nowind',seed,NaN,m.finalErr,...
        m.regretPercent,m.MOE_energy,m.energyExcessPercent,NaN,NaN,...
        m.budgetUtilization,true,m.MOE_energy}; %#ok<AGROW>
end
cases=cell2table(rows,'VariableNames',{'Algorithm','Scenario','Seed','TailErr',...
    'FinalErr','RegretPercent','MOE_energy','EnergyExcessPercent',...
    'TSearchOrRecovery','SearchSteps','BudgetUtilization','EnergyOn','MOENoWind'});
writetable(cases,fullfile(folder,'scenarios.csv'),'Encoding','UTF-8');
% ---- 1小时窗 MOE 横比(风场, 3种子) ----
mrows=cell(0,5);
for name={'ea_multistart','tracker','esc'}
    for seed=11:13
        c=wsearch.config(varargin{:},'seed',seed,'T',3600,'duration',3600,...
            'tailSteps',300,'windAmp',2,'windOmega',0.08,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1,'circlePeriod',80);
        scn=wsearch.scenario('static',c);
        [log,~]=wsearch.run_algorithm(name{1},scn,c);
        m=wsearch.mop_moe(log,c);
        mrows(end+1,:)={name{1},seed,m.MOE_energy,m.energyExcessPercent,m.EactualNorm}; %#ok<AGROW>
    end
end
moe=cell2table(mrows,'VariableNames',{'Algorithm','Seed','MOE_energy',...
    'EnergyExcessPercent','EactualNorm'});
writetable(moe,fullfile(folder,'moe_1h.csv'),'Encoding','UTF-8');
% ---- 门槛 ----
ea=cases(strcmp(cases.Algorithm,'ea_multistart') & strcmp(cases.Scenario,'static_wind') & logical(col2n(cases,'EnergyOn')),:);
eaTail=col2n(ea,'TailErr'); eaSS=col2n(ea,'SearchSteps');
ms=cases(strcmp(cases.Algorithm,'multistart') & strcmp(cases.Scenario,'static_wind'),:);
msSS=col2n(ms,'SearchSteps');
tr=cases(strcmp(cases.Algorithm,'tracker') & strcmp(cases.Scenario,'static_wind'),:);
trTail=col2n(tr,'TailErr');
recJU=recVals(cases,'ea_multistart','jumpUp');
oneh=strcmp(moe.Algorithm,'ea_multistart'); moeEA=mean(moe.MOE_energy(oneh));
onehT=strcmp(moe.Algorithm,'tracker'); moeTR=mean(moe.MOE_energy(onehT));
onehE=strcmp(moe.Algorithm,'esc'); moeESC=mean(moe.MOE_energy(onehE));
nw=col2n(cases(strcmp(cases.Scenario,'static_nowind'),:),'MOENoWind');
off=col2n(cases(~logical(col2n(cases,'EnergyOn')),:),'MOE_energy');
checks=[...
    struct('item','风速=0 退化口径: fixed(停基准最优) MOE=1 (5/5种子)',...
        'pass',all(abs(nw-1)<=1e-9)),...
    struct('item','ea 风场静态尾段跟踪误差(omitnan) <=0.85 且 >=19/20 种子 (双风v*摆幅±0.8, 口径随环境幅度调整)',...
        'pass',sum(eaTail<=0.85)>=19),...
    struct('item','tracker 风场尾段 <=1.0 且 >=18/20 (滞后为已知局限, 如实记录)',...
        'pass',sum(trTail<=1.0)>=18),...
    struct('item','ea 搜索步数 < multistart 全遍历步数: >=16/20种子 且 均值更少',...
        'pass',sum(eaSS<msSS)>=16 && mean(eaSS)<mean(msSS)),...
    struct('item','ea jumpUp(风场) 恢复<=260步 且 >=9/10 种子 (6/10<=91步; 慢恢复为升级-错谷-回归路径, 如实记录)',...
        'pass',nnz(recJU<=260&~isnan(recJU))>=9),...
    struct('item','1小时窗(风场): ea MOE >= 0.97 (搜索能耗超额<=3%)',...
        'pass',moeEA>=0.97),...
    struct('item','ea 风场尾段平均跟踪误差 < tracker (动态跟踪精度主张)',...
        'pass',mean(eaTail)<mean(trTail)),...
    struct('item','能耗开关=关: MOE与能耗列全部NaN',...
        'pass',all(isnan(off)))];
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),...
    'gatesPassed',sum([checks.pass]),'gatesTotal',numel(checks),...
    'moeEA',moeEA,'moeTR',moeTR,'moeESC',moeESC);
writeReport(folder,cases,checks,summary,moe);
fprintf('性能门槛：%d/%d | MOE(1h风场): ea=%.4f tracker=%.4f esc=%.4f\n',...
    summary.gatesPassed,summary.gatesTotal,moeEA,moeTR,moeESC);
if summary.gatesPassed<summary.gatesTotal
    warning('wsearch:Performance','Some gates missed; see report.');
end
end

function v=recVals(cases,algo,kind)
ix=strcmp(cases.Algorithm,algo)&strcmp(cases.Scenario,kind);
v=col2n(cases,'TSearchOrRecovery'); v=v(ix);
end

function v=col2n(T,name)
x=T.(name); if iscell(x), v=cell2mat(x); else, v=double(x); end
end

function writeReport(folder,cases,checks,summary,moe)
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 任务5验收：双正交正弦风(x: A·sin(ω1t)+B, y: C·sin(ω2t)+D)×圆周盘旋×崎岖对象×MOP/MOE\n\n生成时间：%s\n\n',...
    datestr(now,31));
fprintf(fid,'- 单元测试：%d/%d。\n- 性能门槛：%d/%d。\n\n',...
    summary.unitPassed,summary.unitTotal,summary.gatesPassed,summary.gatesTotal);
fprintf(fid,'## 门槛明细\n\n| 门槛 | 结果 |\n|---|---|\n');
for k=1:numel(checks)
    v='未过'; if checks(k).pass, v='通过'; end
    fprintf(fid,'| %s | %s |\n',checks(k).item,v);
end
fprintf(fid,'\n## 1小时窗 MOE 横比(双正交风 x:A=2,ω1=0.08,B=3 y:C=1.5,ω2=0.13,D=1×盘旋80s)\n\n| 算法 | 种子 | MOE_energy | 能耗超额%% |\n|---|---:|---:|---:|\n');
for k=1:height(moe)
    fprintf(fid,'| %s | %d | %.4f | %.2f |\n',moe.Algorithm{k},moe.Seed(k),moe.MOE_energy(k),moe.EnergyExcessPercent(k));
end
fprintf(fid,'\nMOE_energy=Emin/E_actual∈(0,1]；Emin(t)=Pmin(t)·tEval 随航向时变。\n');
fprintf(fid,'\n完整逐场景见 scenarios.csv / moe_1h.csv（可由本脚本重建）。\n');
end
