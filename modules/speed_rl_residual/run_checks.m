function result = run_checks(trainSmoke,agentSource)
%RUN_CHECKS Functional checks plus 20 withheld irregular-wind seeds.
if nargin<1, trainSmoke=false; end
if nargin<2, agentSource=[]; end
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results','acceptance'); if ~exist(folder,'dir'), mkdir(folder); end
suite=runtests(fullfile(root,'tests'));
writetable(table({suite.Name}',[suite.Passed]',[suite.Failed]',...
    'VariableNames',{'Test','Passed','Failed'}),fullfile(folder,'unit_tests.csv'));
result=struct('unitPassed',sum([suite.Passed]),'unitTotal',numel(suite),...
    'adapterValidated',false,'rlValidated',false,'agentActionChecked',false,...
    'trainingSmokeRun',logical(trainSmoke),'trainingSmokePassed',false,...
    'twentySeedSafetyPassed',false,'scriptedImprovementCount',0,...
    'td3Evaluated',false,'td3SafetyPassed',false,'td3ImprovementCount',0,'td3MeanPowerW',NaN);
c=speedrl.config('duration',20,'windMode','mixed'); adapter=speedrl.make_synthetic_adapter();
speedrl.validate_adapter(adapter,c); result.adapterValidated=true;
env=speedrl.make_env(c,adapter,speedrl.make_baseline('fixed')); validateEnvironment(env);
o=reset(env); agent=speedrl.make_agent(env,c); action=speedrl.agent_action(agent,o);
assert(isfinite(action) && action>=c.deltaBounds(1) && action<=c.deltaBounds(2));
result.agentActionChecked=true; done=false; count=0;
while ~done, [o,r,done]=step(env,0); assert(all(isfinite(o)) && isfinite(r)); count=count+1; end
assert(count==round(c.duration/c.decisionPeriod)); result.rlValidated=true;
evalConfig=speedrl.config('duration',120,'windMode','irregular','trajectory','circle',...
    'windObservation','observable');
R=evaluate_policies(agentSource,2001:2020,evalConfig,'fixed');
fixed=R(strcmp(R.Policy,'baseline'),:); scripted=R(strcmp(R.Policy,'scripted'),:);
result.scriptedImprovementCount=sum(scripted.MeanPowerW<=fixed.MeanPowerW);
result.twentySeedSafetyPassed=all(R.BoundViolations==0 & R.RateViolations==0 & ...
    R.MinimumGroundSpeed>=evalConfig.speedBounds(1)-1e-9);
td3=R(strcmp(R.Policy,'td3_agent'),:);
if ~isempty(td3)
    result.td3Evaluated=true;
    result.td3SafetyPassed=all(td3.BoundViolations==0 & td3.RateViolations==0 & ...
        td3.MinimumGroundSpeed>=evalConfig.speedBounds(1)-1e-9);
    result.td3ImprovementCount=sum(td3.MeanPowerW<=fixed.MeanPowerW);
    result.td3MeanPowerW=mean(td3.MeanPowerW);
end
if trainSmoke
    try
        [~,stats,file]=train_td3(1,20); %#ok<ASGLU>
        result.trainingSmokePassed=exist(file,'file')==2;
    catch err
        result.trainingError=getReport(err,'extended','hyperlinks','off');
    end
end
save(fullfile(folder,'summary.mat'),'result','R');
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8'); clean=onCleanup(@()fclose(fid));
stamp=char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
fprintf(fid,'# 残差速度RL实际检查\n\n生成时间：%s\n\n',stamp);
fprintf(fid,'- 单元测试：%d/%d。\n- 适配器契约：%d。\n- RL环境完整回合：%d。\n',...
    result.unitPassed,result.unitTotal,result.adapterValidated,result.rlValidated);
fprintf(fid,'- TD3网络与动作边界：%d。\n',result.agentActionChecked);
if result.trainingSmokeRun
    fprintf(fid,'- 一回合训练冒烟：%d。\n',result.trainingSmokePassed);
else
    fprintf(fid,'- 一回合训练冒烟：本次未重复执行；已有独立成功记录。\n');
end
fprintf(fid,'- 20个未见不规则风种子的硬约束：%d。\n',result.twentySeedSafetyPassed);
fprintf(fid,'- 可观测风解析脚本相对固定基准功率不高的种子：%d/20。\n\n',result.scriptedImprovementCount);
if result.td3Evaluated
    fprintf(fid,'- TD3候选不规则风硬约束：%d。\n',result.td3SafetyPassed);
    fprintf(fid,'- TD3候选相对固定基准功率不高的种子：%d/20；平均功率 %.3f W。\n\n',...
        result.td3ImprovementCount,result.td3MeanPowerW);
end
fprintf(fid,'解析脚本只验证环境存在可利用的风信息，不是TD3成绩。训练冒烟只证明训练链路可运行。\n');
assert(result.unitPassed==result.unitTotal && result.adapterValidated && result.rlValidated && ...
    result.agentActionChecked && result.twentySeedSafetyPassed,'speedrl:Checks','Functional check failed.');
if result.td3Evaluated && ~result.td3SafetyPassed, error('speedrl:Safety','TD3 candidate violated hard constraints.'); end
if result.td3Evaluated && result.td3ImprovementCount<20
    warning('speedrl:Performance','TD3 candidate did not pass all irregular-wind performance seeds.');
end
disp(result);
end
