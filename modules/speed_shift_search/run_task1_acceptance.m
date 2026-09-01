function summary = run_task1_acceptance(varargin)
%RUN_TASK1_ACCEPTANCE 任务1验收：算法横评 x 平移场景 x 曲线 x 能耗开关两档。
%
% 用法:
%   run_task1_acceptance                       % 运行并写 results/task1/
%   summary = run_task1_acceptance(...)        % 返回汇总结构
% 可选参数透传 task1.config (如 'duration',600)。能耗开关两档始终都被评估：
% "开"档把寻优过程能量计入验收，"关"档能耗列记NaN、只看定位与稳态。
%
% 验收哲学与 +speedesc 一致：功能门槛(单元测试)必须全过；
% 性能门槛只加在推荐方案 tracker 上，基线如实报告、不设门槛。
root=fileparts(mfilename('fullpath')); addpath(root);
cRef=task1.config(varargin{:});   % 提前校验参数并读取默认口径
folder=fullfile(root,'results','task1'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests_task1.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
algorithms={'grid','ternary','golden','brent','tracker','esc'};
scenarios={'static','jumpUp','jumpDown','offset','ramp','midsearch'};
curves={'cubic','debug'};
rows=cell(0,12);
for eSwitch=[true false]
    for curve=curves
        cc=task1.config(varargin{:},'energyAccounting',eSwitch,'curve',curve{1});
        for kind=scenarios
            scn=task1.scenario(kind{1},cc);
            for name=algorithms
                [log,info]=task1.run_algorithm(name{1},scn,cc);
                m=task1.evaluate(log,scn,cc);
                rows(end+1,:)=({eSwitch,curve{1},kind{1},name{1},m.finalErr,m.evalsToEps,...
                    m.recoverySteps,m.steadyRegretPercent,m.energyExcessPercent,...
                    m.searchSteps,m.probeSteps,info.researchCount}); %#ok<AGROW>
            end
        end
    end
end
cases=cell2table(rows,'VariableNames',{'EnergyOn','Curve','Scenario','Algorithm',...
    'FinalError','EvalsToEps','RecoverySteps','SteadyRegretPercent',...
    'EnergyExcessPercent','SearchSteps','ProbeSteps','ResearchCount'});
writetable(cases,fullfile(folder,'scenarios.csv'),'Encoding','UTF-8');
% ---- 推荐方案(tracker)的性能门槛；能耗门槛只在开关=开的记录上生效 ----
g=cases(strcmp(cases.Algorithm,'tracker'),:);
fe=numcol(g,'FinalError'); ev=numcol(g,'EvalsToEps'); rc=numcol(g,'RecoverySteps');
sr=numcol(g,'SteadyRegretPercent'); en=numcol(g,'EnergyExcessPercent');
rs=numcol(g,'ResearchCount'); on=numcol(g,'EnergyOn')==1;
jump=strcmp(g.Scenario,'jumpUp')|strcmp(g.Scenario,'jumpDown')|strcmp(g.Scenario,'midsearch');
checks=[...
    struct('item','tracker 静态场景定位精度<=eps',          'pass',all(fe(strcmp(g.Scenario,'static'))<=cRef.eps)),...
    struct('item','tracker 静态场景入带评估数<=25',        'pass',all(ev(strcmp(g.Scenario,'static'))<=25)),...
    struct('item','tracker dx跳变恢复步数<=30',            'pass',all(arrayfun(@(x) x<=30,rc(jump)))),...
    struct('item','tracker dy-only不触发重搜',             'pass',all(rs(strcmp(g.Scenario,'offset'))==0)),...
    struct('item','tracker 慢漂末段误差<=0.15 m/s',        'pass',all(fe(strcmp(g.Scenario,'ramp'))<=0.15)),...
    struct('item','tracker 稳态超额<=0.2%',                'pass',all(sr<0.2)),...
    struct('item','开关=开: tracker 全程能耗<=1.5%',       'pass',all(arrayfun(@(x) x<=1.5,en(on)))),...
    struct('item','开关=关: 能耗列全部为NaN(不参与判定)',  'pass',all(isnan(en(~on))))];
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),...
    'trackerChecksPassed',sum([checks.pass]),'trackerChecksTotal',numel(checks));
writeReport(folder,cases,checks,summary,cRef);
fprintf('tracker性能门槛：%d/%d 通过\n',summary.trackerChecksPassed,summary.trackerChecksTotal);
assert(summary.unitPassed==summary.unitTotal,'task1:Acceptance','Unit tests failed; see console.');
if summary.trackerChecksPassed<summary.trackerChecksTotal
    warning('task1:Performance','Some tracker performance targets were missed; they remain in the report.');
end
end

function writeReport(folder,cases,checks,summary,cRef)
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 任务1验收：平移曲线上的瞬时跳变黑箱搜索\n\n生成时间：%s\n\n',...
    datestr(now,31));
fprintf(fid,['对象为代理曲线平移(非X8实测)；速度瞬时生效；任务1无噪声；'...
    '每评估步 %.1f s；全程 %d 步。能耗开关两档均评估："开"把寻优过程'...
    '能量计入验收，"关"只看定位与稳态。\n\n'],cRef.tEval,cRef.duration);
fprintf(fid,'- 单元测试：%d/%d。\n- tracker性能门槛：%d/%d。\n\n',...
    summary.unitPassed,summary.unitTotal,summary.trackerChecksPassed,summary.trackerChecksTotal);
fprintf(fid,'## tracker 门槛明细\n\n| 门槛 | 结果 |\n|---|---|\n');
for k=1:numel(checks)
    if checks(k).pass, verdict='通过'; else, verdict='未过'; end
    fprintf(fid,'| %s | %s |\n',checks(k).item,verdict);
end
fprintf(fid,'\n## 全部场景结果(诚实记录，含未达标项)\n\n');
fprintf(fid,['| 能耗开关 | 曲线 | 场景 | 算法 | 末段误差m/s | 入带步数 | 恢复步数 |'...
    ' 稳态超额%% | 全程能耗%% | 重搜次数 |\n|---|---|---|---|---:|---:|---:|---:|---:|---:|\n']);
fe=numcol(cases,'FinalError'); ev=numcol(cases,'EvalsToEps'); rc=numcol(cases,'RecoverySteps');
sr=numcol(cases,'SteadyRegretPercent'); en=numcol(cases,'EnergyExcessPercent');
rs=numcol(cases,'ResearchCount'); on=numcol(cases,'EnergyOn')==1;
for k=1:height(cases)
    e='NaN'; if isfinite(en(k)), e=sprintf('%.3f',en(k)); end
    r='NaN'; if isinf(rc(k)), r='Inf'; elseif ~isnan(rc(k)), r=sprintf('%.0f',rc(k)); end
    if on(k), es='开'; else, es='关'; end
    fprintf(fid,'| %s | %s | %s | %s | %.3f | %.0f | %s | %.3f | %s | %.0f |\n',...
        es,charcol(cases,'Curve',k),charcol(cases,'Scenario',k),charcol(cases,'Algorithm',k),...
        fe(k),ev(k),r,sr(k),e,rs(k));
end
fprintf(fid,['\n基线(grid/ternary/golden/brent/esc)不设门槛，仅横评。'...
    '"搜索后锁定"算法在平移后不重搜属预期行为，正是tracker监测层的对照证据。\n']);
end

function v=numcol(T,name)
%NUMCOL 表列转数值向量(cell2table可能把纯数值列解包成数组)。
x=T.(name);
if iscell(x), v=cell2mat(x); else, v=double(x); end
end

function s=charcol(T,name,k)
x=T.(name);
if iscell(x), s=x{k}; elseif isstring(x), s=char(x(k)); else, s=char(x(k)); end
end
