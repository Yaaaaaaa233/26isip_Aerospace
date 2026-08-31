function summary = run_acceptance()
%RUN_ACCEPTANCE Reproducible acceptance, including failures in the report.
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results','acceptance'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests','test_core.m'));
unitTable=table({unit.Name}',[unit.Passed]',[unit.Failed]',[unit.Incomplete]',...
    'VariableNames',{'Test','Passed','Failed','Incomplete'});
writetable(unitTable,fullfile(folder,'unit_tests.csv'));
rows=cell(0,10); lastLog=[]; lastConfig=[];
for initial=[0.8 1 1.2]
    c=ratioesc.config('initialRatio',initial); record('no_noise',c,1);
end
for seed=1:10
    c=ratioesc.config('noiseSigma',0.02,'seed',seed); record('noise_only',c,3);
    c=ratioesc.config('delay',0.5,'seed',seed); record('delay_only',c,3);
    c=ratioesc.config('noiseSigma',0.02,'delay',0.5,'seed',seed); record('noise_delay',c,3);
end
c=ratioesc.config('scenario','shift'); record('shift_clean',c,3);
c=ratioesc.config('scenario','shift','noiseSigma',0.02,'delay',0.5); record('shift_noisy',c,3);
cases=cell2table(rows,'VariableNames',{'Scenario','InitialRatio','Seed','ExcessPercent',...
    'ThresholdPercent','Passed','BoundViolations','ConvergenceSeconds','ReconvergenceSeconds','FixedOneExcessPercent'});
writetable(cases,fullfile(folder,'scenarios.csv'));
save(fullfile(folder,'scenarios.mat'),'cases');
simErrors=[]; simOK=false; simMessage='';
try
    for scenario={'stationary','shift'}
        c=ratioesc.config('scenario',scenario{1},'noiseSigma',0.02,'delay',0.5);
        data=ratioesc.make_inputs(c); a=ratioesc.run(c,data); b=ratioesc.run_simulink(c,data);
        errors=max(abs(a{:,:}-b{:,:}),[],1); simErrors=[simErrors;errors]; %#ok<AGROW>
    end
    simOK=all(simErrors(:,[2 3 4 5 6])<1e-6,'all');
    writematrix(simErrors,fullfile(folder,'simulink_max_absolute_errors.csv'));
catch err
    simMessage=getReport(err,'extended','hyperlinks','off');
end
rlOK=false; rlMessage='';
try
    c=ratioesc.config('noiseSigma',0.02,'delay',0.5);
    env=ratioesc.make_rl_env(c); validateEnvironment(env);
    stream=RandStream('mt19937ar','Seed',123); observation=reset(env); count=0; done=false;
    while ~done
        action=c.lower+(c.upper-c.lower)*rand(stream);
        [observation,reward,done]=step(env,action); %#ok<ASGLU>
        assert(all(isfinite(observation)) && isfinite(reward)); count=count+1;
    end
    rlOK=count==round(c.duration/c.rlPeriod);
catch err
    rlMessage=getReport(err,'extended','hyperlinks','off');
end
summary=struct('unitPassed',all([unit.Passed]),'noNoisePassed',all(cases.Passed(strcmp(cases.Scenario,'no_noise'))),...
    'combinedPassed',sum(cases.Passed(strcmp(cases.Scenario,'noise_delay'))),...
    'driftPassed',all(cases.Passed(startsWith(cases.Scenario,'shift'))),...
    'simulinkPassed',simOK,'rlPassed',rlOK);
summary.allPassed=summary.unitPassed && summary.noNoisePassed && summary.combinedPassed>=9 && ...
    summary.driftPassed && summary.simulinkPassed && summary.rlPassed;
save(fullfile(folder,'summary.mat'),'summary','simMessage','rlMessage','simErrors');
writeReport();
ratioesc.export_run(lastLog,lastConfig,fullfile(folder,'dynamic_example'),true);
build_simulink(ratioesc.config());
disp(summary);
assert(summary.allPassed,'ratioesc:Acceptance','Some acceptance checks failed. See results/acceptance/report.md.');

    function record(name,c,threshold)
        log=ratioesc.run(c); m=ratioesc.metrics(log,c);
        baseline=c; baseline.stage='feedback'; baseline.fixedReference=1;
        base=ratioesc.metrics(ratioesc.run(baseline),baseline);
        ok=m.finalExcessPercent<=threshold && m.boundViolations==0;
        rows(end+1,:)={name,c.initialRatio,c.seed,m.finalExcessPercent,threshold,ok,...
            m.boundViolations,m.convergenceTime,m.reconvergenceTime,base.finalExcessPercent};
        lastLog=log; lastConfig=c;
        fprintf('%s initial=%.2f seed=%d excess=%.4f%% pass=%d\n',name,c.initialRatio,c.seed,m.finalExcessPercent,ok);
    end
    function writeReport()
        fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8'); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
        fprintf(fid,'# 转速比ESC自动验收报告\n\n生成时间：%s\n\n',datestr(now,31));
        fprintf(fid,'对象为恒推力假设下的归一化功率代理模型，非实测，不构成真实X8节能或偏航稳定性证据。\n\n');
        fprintf(fid,'## 汇总\n\n| 检查 | 实际结果 |\n|---|---|\n');
        fprintf(fid,'| 单元测试 | %d / %d 通过 |\n',sum([unit.Passed]),numel(unit));
        fprintf(fid,'| 无噪声三个初值 | %s |\n',yes(summary.noNoisePassed));
        fprintf(fid,'| 2%%噪声 + 0.5 s延迟 | %d / 10 通过，要求至少9次 |\n',summary.combinedPassed);
        fprintf(fid,'| 运行中最优点变化 | %s |\n',yes(summary.driftPassed));
        fprintf(fid,'| MATLAB/Simulink一致性 | %s |\n',yes(summary.simulinkPassed));
        if ~isempty(simErrors), fprintf(fid,'| 转速比/参考/功率最大绝对差 | %.12g |\n',max(simErrors(:,[2 3 4 5 6]),[],'all')); end
        fprintf(fid,'| RL环境验证与完整回合 | %s，未训练策略 |\n',yes(summary.rlPassed));
        fprintf(fid,'\n## 场景结果\n\n| 工况 | 初值 | 种子 | 最后100 s超额功率 / %% | 固定1.0基线 / %% | 通过 |\n|---|---:|---:|---:|---:|---|\n');
        for k=1:height(cases)
            fprintf(fid,'| %s | %.2f | %d | %.5f | %.5f | %s |\n',cases.Scenario{k},...
                cases.InitialRatio(k),cases.Seed(k),cases.ExcessPercent(k),cases.FixedOneExcessPercent(k),yes(cases.Passed(k)));
        end
        fprintf(fid,'\n## 评价口径与局限\n\n');
        fprintf(fid,'- 超额功率使用对象真实归一化功率，而非带噪声测量值；包含微扰代价。最优功率为1。\n');
        fprintf(fid,'- 噪声标准差0.02，以固定参考功率1为基准；每步独立，使用指定随机种子。\n');
        fprintf(fid,'- 收敛时间为完整50 s后向均值达到3%%阈值且此后不再越线的时刻；未收敛记NaN。该指标由离线评价器计算。\n');
        fprintf(fid,'- Simulink一致性测试覆盖健康测量下的静态工况和最优点变化，均含噪声与延迟。冻结及无效数据恢复单独验证MATLAB控制器API。\n');
        fprintf(fid,'- RL验证只证明环境可运行，不证明学习效果。未建模总推力/偏航动态，不能报告相关约束已经验证。\n');
        fprintf(fid,'- 交互面板与导出检查另见 results/ui_qa；本表不以算法测试代替图形界面检查。\n');
        if ~isempty(simMessage), fprintf(fid,'\n## Simulink错误\n```text\n%s\n```\n',simMessage); end
        if ~isempty(rlMessage), fprintf(fid,'\n## RL错误\n```text\n%s\n```\n',rlMessage); end
    end
end

function value=yes(ok)
if ok, value='通过'; else, value='未通过'; end
end
