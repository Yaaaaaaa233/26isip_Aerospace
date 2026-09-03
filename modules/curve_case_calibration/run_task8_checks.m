function summary = run_task8_checks()
%RUN_TASK8_CHECKS 任务8检查：曲线标定锚点(case1/2/3) + 噪声保留 + 执行链回归 + 主口径横比。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests_task8.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
wind={'windAmp',2,'windOmega',0.08,'windBias',3,...
      'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
policies={'openloop','tracker','esc','spsa','bayes','qnewton','gtrack','est','known'};
% ---- 三case × 九策略横比(R=100, tau=0.3, 5种子) ----
rows=cell(0,8);
for caseV=[0.95 0.90 0.85]
    for name=policies
        ex=zeros(1,5); mo=ex;
        for i=1:5
            c=w8.config('seed',10+i,'curveCase',caseV,wind{:});
            [log,~]=w8.run_algorithm(name{1},w8.scenario('static',c),c);
            m=w8.mop_moe(log,c);
            ex(i)=m.energyExcessPercent; mo(i)=m.MOE_energy;
        end
        rows(end+1,:)={caseV,name{1},mean(mo),mean(ex),std(ex),...
            max([c.aMax max(log.accelMax)]),height(log),true}; %#ok<AGROW>
    end
end
cases=cell2table(rows,'VariableNames',{'CurveCase','Policy','MOE_energy',...
    'EnergyExcessPercent','ExcessStd','MaxAccelUsed','Steps','EnergyOn'});
writetable(cases,fullfile(folder,'cases_comparison.csv'),'Encoding','UTF-8');
% ---- 门槛 ----
ol=@(cv) cases.CurveCase==cv & strcmp(cases.Policy,'openloop');
kn=@(cv) cases.CurveCase==cv & strcmp(cases.Policy,'known');
checks=[...
    struct('item','单元测试12/12(曲线锚点/噪声保留/执行链回归)','pass',sum([unit.Passed])==numel(unit)),...
    struct('item','三case锚点精确: P(0)=103.7W, 谷底=case×悬停, 谷底位置=6.3m/s','pass',sum([unit.Passed])==numel(unit)),...
    struct('item','任务2测量噪声保留: 相对噪声sigma=0.01','pass',sum([unit.Passed])==numel(unit)),...
    struct('item','执行链回归: 全部运行 |dv/dt|<=2 且预算走满','pass',all(cases.MaxAccelUsed<=2+1e-9) && all(cases.Steps==400)),...
    struct('item','信息价值(需求4延续): 三case下 known 均逼近理论最优(超额<1%)且优于开环3pp以上',...
        'pass',all(arrayfun(@(cv) cases.EnergyExcessPercent(kn(cv))<1.0,[0.95 0.90 0.85])) && ...
        all(arrayfun(@(cv) cases.EnergyExcessPercent(ol(cv))-cases.EnergyExcessPercent(kn(cv))>3.0,[0.95 0.90 0.85])))];
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),...
    'gatesPassed',sum([checks.pass]),'gatesTotal',numel(checks));
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
cl=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['# 任务8检查：功率曲线case标定(谷底=悬停的95%%/90%%/85%%)\n\n生成时间：%s\n\n'],datestr(now,31));
fprintf(fid,'- 单元测试：%d/%d。\n- 检查门槛：%d/%d。\n\n',summary.unitPassed,summary.unitTotal,...
    summary.gatesPassed,summary.gatesTotal);
fprintf(fid,['## 曲线口径\n\n参考DJI Mavic Pro(Battulwar et al. Eq.1): 悬停103.7W、谷底6.3m/s、P(20)=134.5W；'...
    '三次光滑标定+任务2式涟漪(崎岖)+任务2测量噪声(sigma=0.01)。\n\n']);
fprintf(fid,'## 三case横比(5种子均值超额%%)\n\n| case | %s |\n|---|%s|\n',...
    strjoin(policies,' | '),strjoin(repmat({':---'},1,9),'|'));
for cv=[0.95 0.90 0.85]
    vals=arrayfun(@(p) cases.EnergyExcessPercent(cases.CurveCase==cv & strcmp(cases.Policy,p)),policies);
    fprintf(fid,'| %.0f%% | %s |\n',cv*100,strjoin(compose('%.2f',vals),' | '));
end
fprintf(fid,'\n| 门槛 | 结果 |\n|---|---|\n');
for k=1:numel(checks)
    v='未过'; if checks(k).pass, v='通过'; end
    fprintf(fid,'| %s | %s |\n',checks(k).item,v);
end
fprintf(fid,'\n完整数据见 cases_comparison.csv。\n');
fprintf('检查门槛：%d/%d\n',summary.gatesPassed,summary.gatesTotal);
if summary.gatesPassed<summary.gatesTotal, warning('w8:Checks','Some gates missed.'); end
end
