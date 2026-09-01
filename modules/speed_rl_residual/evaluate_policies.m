function R = evaluate_policies(agentSource,seeds,c,baselineKind)
%EVALUATE_POLICIES Fixed, baseline, and optional TD3 on identical seeds.
if nargin<1, agentSource=[]; end
if nargin<2 || isempty(seeds), seeds=2001:2020; end
if nargin<3 || isempty(c), c=speedrl.config('windMode','irregular','trajectory','circle'); end
if nargin<4, baselineKind='fixed'; end
agent=[];
if ischar(agentSource) || isstring(agentSource)
    saved=load(agentSource,'agent'); agent=saved.agent;
elseif ~isempty(agentSource), agent=agentSource;
end
adapter=speedrl.make_synthetic_adapter(); policies={'fixed','baseline','scripted'};
if ~isempty(agent), policies{end+1}=agent; end
rows=cell(0,14);
for seed=seeds
    cc=c; cc.seed=seed;
    for k=1:numel(policies)
        baseline=speedrl.make_baseline(baselineKind);
        [~,m]=speedrl.run_episode(cc,policies{k},adapter,baseline);
        rows(end+1,:)={m.policy,seed,m.meanPowerW,m.energyWh,m.estimatedEnduranceHours,...
            m.minimumGroundSpeed,m.maximumGroundSpeed,m.rateViolations,m.boundViolations,...
            m.meanBlockedFraction,m.radialRms,m.meanPowerCoverage,c.windMode,c.windObservation}; %#ok<AGROW>
    end
end
R=cell2table(rows,'VariableNames',{'Policy','Seed','MeanPowerW','EnergyWh','EnduranceHours',...
    'MinimumGroundSpeed','MaximumGroundSpeed','RateViolations','BoundViolations',...
    'BlockedFraction','RadialRms','PowerCoverage','WindMode','WindObservation'});
folder=fullfile(fileparts(mfilename('fullpath')),'results'); if ~exist(folder,'dir'), mkdir(folder); end
writetable(R,fullfile(folder,'policy_evaluation.csv'));
writetable(R,fullfile(folder,sprintf('policy_evaluation_%s_%s.csv',c.windMode,c.windObservation)));
end
