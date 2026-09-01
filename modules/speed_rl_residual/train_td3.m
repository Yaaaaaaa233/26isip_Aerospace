function [agent,stats,file] = train_td3(episodes,duration,windMode,randomizeWind)
%TRAIN_TD3 Explicit opt-in synthetic training. No hardware access.
if nargin<1, episodes=100; end
if nargin<2, duration=120; end
if nargin<3, windMode='mixed'; end
if nargin<4, randomizeWind=true; end
validateattributes(episodes,{'double'},{'scalar','integer','positive'});
root=fileparts(mfilename('fullpath')); addpath(root);
c=speedrl.config('duration',duration,'windMode',windMode,'randomizeWind',logical(randomizeWind),...
    'windObservation','observable',...
    'trajectory','straight','seed',1000);
adapter=speedrl.make_synthetic_adapter(); baseline=speedrl.make_baseline('fixed');
env=speedrl.make_env(c,adapter,baseline,true); agent=speedrl.make_agent(env,c);
previous=rng; cleanup=onCleanup(@()rng(previous));
rng(1000,'twister');
options=rlTrainingOptions('MaxEpisodes',episodes,'MaxStepsPerEpisode',round(duration/c.decisionPeriod),...
    'Verbose',false,'Plots','none','StopTrainingCriteria','EpisodeCount','StopTrainingValue',episodes,...
    'SaveAgentCriteria','None');
stats=train(agent,env,options);
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
distribution='fixed'; if randomizeWind, distribution='randomized'; end
if episodes==1, name=['td3_smoke_' windMode '_' distribution '.mat'];
else
    stamp=char(datetime('now','Format','yyyyMMdd_HHmmss'));
    name=['td3_candidate_' windMode '_' distribution '_' stamp '.mat'];
end
file=fullfile(folder,name); save(file,'agent','stats','c');
fprintf('Saved synthetic residual TD3 candidate: %s\n',file);
end
