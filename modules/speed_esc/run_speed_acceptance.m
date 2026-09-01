function summary = run_speed_acceptance()
%RUN_SPEED_ACCEPTANCE Functional gates and honest per-scenario performance.
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results','acceptance'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests','test_speed.m'));
writetable(table({unit.Name}',[unit.Passed]',[unit.Failed]',...
    'VariableNames',{'Test','Passed','Failed'}),fullfile(folder,'unit_tests.csv'));
parity=verify_python_parity(); rows=cell(0,13);
for curve={'debug','cubic'}
    for version=1:2
        for initial=[2 10 15], record(speedesc.config('curve',curve{1},'version',version,'initialSpeed',initial),'clean',1); end
    end
    for scenario={'noise','delay','combined','shift'}
        seeds=11:20; if strcmp(scenario{1},'delay'), seeds=11; end
        for seed=seeds
            c=speedesc.config('curve',curve{1},'seed',seed,'shift',strcmp(scenario{1},'shift'));
            if strcmp(scenario{1},'noise'), c.delay=0; end
            if strcmp(scenario{1},'delay'), c.noiseSigma=0; end
            record(c,scenario{1},3);
        end
    end
end
% Different estimators have independent presets. This is a diagnostic, not proof of superiority.
for curve={'debug','cubic'}
    for version=[1 3]
        record(speedesc.config('curve',curve{1},'method','demod','version',version,'seed',11),'demod_comparison',3);
    end
end
cases=cell2table(rows,'VariableNames',{'Curve','Version','Method','Scenario','Seed','InitialSpeed',...
    'RegretPercent','SpeedMeanError','PowerPassed','SpeedPassed','BoundsPassed','FixedBaselineRegret','ReconvergenceSeconds'});
writetable(cases,fullfile(folder,'scenarios.csv'));
simRows=cell(0,4); simErrorText=''; rlErrorText='';
try
    for method={'regression','demod'}
        for version=1:3
            c=speedesc.config('method',method{1},'version',version,'duration',40,'tailSeconds',10,'shiftTime',15);
            data=speedesc.make_inputs(c); data.valid(101:105)=0; data.freeze(201:205)=1;
            a=speedesc.run(c,data); b=speedesc.run_simulink(c,data);
            error=max(abs(a{:,:}-b{:,:}),[],'all'); simRows(end+1,:)={method{1},version,error,error<1e-6}; %#ok<AGROW>
        end
    end
catch err, simErrorText=getReport(err,'extended','hyperlinks','off'); end
simTests=cell2table(simRows,'VariableNames',{'Method','Version','MaximumError','Passed'});
writetable(simTests,fullfile(folder,'simulink_parity.csv'));
rlOK=false;
try
    c=speedesc.config(); env=speedesc.make_rl_env(c); validateEnvironment(env);
    a=reset(env); b=reset(env); assert(isequal(a,b)); count=0; done=false;
    while ~done
        [o,r,done]=step(env,8); assert(all(isfinite(o)) && isfinite(r)); count=count+1;
    end
    assert(count==round(c.duration/c.rlPeriod)); rlOK=true;
catch err, rlErrorText=getReport(err,'extended','hyperlinks','off'); end
recommended=strcmp(cases.Method,'regression');
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),'pythonParityPassed',all(parity.Passed),...
    'simulinkPassed',height(simTests)==6 && all(simTests.Passed),'rlPassed',rlOK,...
    'powerPassed',sum(cases.PowerPassed(recommended)),'powerTotal',sum(recommended),...
    'speedPassed',sum(cases.SpeedPassed(recommended)),'speedTotal',sum(recommended));
summary.functionalPassed=all([unit.Passed]) && summary.pythonParityPassed && summary.simulinkPassed && rlOK;
save(fullfile(folder,'summary.mat'),'summary','cases','simTests','simErrorText','rlErrorText');
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8'); clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 平飞速度ESC整合版：实际验收记录\n\n生成时间：%s\n\n',datestr(now,31));
fprintf(fid,'全部为代理模型，不是X8实测。功能通过与性能达标分开记录。\n\n');
fprintf(fid,'- MATLAB单元测试：%d/%d。\n- 原Python复现：%d，14组。\n- MATLAB/Simulink一致性：%d，6组。\n- RL环境/完整回合：%d，未训练策略。\n',...
    summary.unitPassed,summary.unitTotal,summary.pythonParityPassed,summary.simulinkPassed,summary.rlPassed);
fprintf(fid,'- 默认回归算法功率指标：%d/%d；速度均值误差指标：%d/%d。\n',...
    summary.powerPassed,summary.powerTotal,summary.speedPassed,summary.speedTotal);
fprintf(fid,'\n## 口径\n\n');
fprintf(fid,'无噪声V1/V2功率超额阈值1%%，V3为3%%；实际速度末段均值误差V1/V2为0.5 m/s、V3为0.7 m/s。末段为最后20秒，包含微扰代价。\n\n');
fprintf(fid,'V3种子11–20未用于前期窗口选择；不同工况/算法使用同种子噪声。固定基线与优化器使用相同初始速度、执行响应和参考限速。\n\n');
fprintf(fid,'收敛时刻是后向12.6秒实际速度均值进入容差并连续保持5秒后的确认时刻，不回填为较早样本，也不保证之后永不离开；NaN表示观察期内未确认。\n\n');
fprintf(fid,'| 曲线 | 阶段/场景 | 方法 | 种子 | 初速 | 功率超额%% | 速度误差m/s | 功率通过 | 速度通过 |\n|---|---|---|---:|---:|---:|---:|---|---|\n');
for k=1:height(cases)
    fprintf(fid,'| %s | V%d/%s | %s | %d | %.1f | %.4f | %.4f | %d | %d |\n',...
        cases.Curve{k},cases.Version(k),cases.Scenario{k},cases.Method{k},cases.Seed(k),cases.InitialSpeed(k),...
        cases.RegretPercent(k),cases.SpeedMeanError(k),cases.PowerPassed(k),cases.SpeedPassed(k));
end
fprintf(fid,'\n0表示未达标，1表示达标。经典解调为独立参数的对照案例，不据少量测试宣称任一方法普遍更优。\n');
if ~isempty(simErrorText), fprintf(fid,'\n```text\n%s\n```\n',simErrorText); end
if ~isempty(rlErrorText), fprintf(fid,'\n```text\n%s\n```\n',rlErrorText); end
build_speed_simulink(speedesc.config()); disp(summary);
assert(summary.functionalPassed,'speedesc:Acceptance','Functional checks failed; see report.md.');
if summary.powerPassed<summary.powerTotal || summary.speedPassed<summary.speedTotal
    warning('speedesc:Performance','Some performance targets were missed; they remain in the report.');
end

    function record(c,scenario,threshold)
        data=speedesc.make_inputs(c); m=speedesc.metrics(speedesc.run(c,data),c);
        base=c; base.mode='fixed'; base.fixedReference=c.initialSpeed;
        baseline=speedesc.metrics(speedesc.run(base,data),base);
        speedTolerance=.5; if c.version==3, speedTolerance=.7; end
        rows(end+1,:)={c.curve,c.version,c.method,scenario,c.seed,c.initialSpeed,m.regretPercent,...
            m.speedError,m.regretPercent<=threshold,m.speedError<=speedTolerance,...
            m.boundViolations==0 && m.rateViolations==0,baseline.regretPercent,m.reconvergenceSeconds};
    end
end
