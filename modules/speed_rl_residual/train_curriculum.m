function [agent,stageStats,file] = train_curriculum(stageEpisodes,duration)
%TRAIN_CURRICULUM Continue one TD3 agent through increasingly hard stages.
if nargin<1, stageEpisodes=[10 20 20 20 50 30 50]; end
if nargin<2, duration=120; end
validateattributes(stageEpisodes,{'double'},{'vector','integer','positive','numel',7});
root=fileparts(mfilename('fullpath')); addpath(root);
stages=speedrl.curriculum(duration); adapter=speedrl.make_synthetic_adapter();
baseline=speedrl.make_baseline('fixed'); agent=[]; stageStats=cell(7,1);
previous=rng; cleanup=onCleanup(@()rng(previous));
rng(1000,'twister');
for k=1:7
    c=stages{k}; env=speedrl.make_env(c,adapter,baseline,true);
    if isempty(agent), agent=speedrl.make_agent(env,c); end
    options=rlTrainingOptions('MaxEpisodes',stageEpisodes(k),...
        'MaxStepsPerEpisode',round(duration/c.decisionPeriod),'Verbose',false,'Plots','none',...
        'StopTrainingCriteria','EpisodeCount','StopTrainingValue',stageEpisodes(k));
    [agent,stageStats{k}]=train(agent,env,options);
    fprintf('Completed curriculum stage %d/7: %s\n',k,c.stageName);
end
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
stamp=char(datetime('now','Format','yyyyMMdd_HHmmss'));
file=fullfile(folder,['td3_curriculum_' stamp '.mat']);
save(file,'agent','stageStats','stages','stageEpisodes');
fprintf('Saved curriculum candidate, NOT flight-qualified: %s\n',file);
end
