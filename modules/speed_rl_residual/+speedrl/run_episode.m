function [L,summary] = run_episode(c,strategy,adapter,baseline)
%RUN_EPISODE Fair fixed-duration policy rollout on one seeded scenario.
if nargin<2, strategy='baseline'; end
if nargin<3 || isempty(adapter), adapter=speedrl.make_synthetic_adapter(); end
if nargin<4 || isempty(baseline), baseline=speedrl.make_baseline('fixed'); end
runtimeBaseline=baseline;
if (ischar(strategy) || isstring(strategy)) && strcmp(char(strategy),'fixed')
    runtimeBaseline=speedrl.make_baseline('fixed');
end
[observation,s]=speedrl.reset(c,adapter,runtimeBaseline);
n=round(c.duration/c.decisionPeriod); rows=zeros(n,18);
actor=[];
if ~(ischar(strategy) || isstring(strategy) || isa(strategy,'function_handle'))
    actor=getActor(strategy);
end
for k=1:n
    ctx=speedrl.context(s.sample,s.reference,s.lastDelta,s.previousMean,0,c);
    [base,~]=runtimeBaseline.reference(ctx);
    if ischar(strategy) || isstring(strategy)
        switch char(strategy)
            case 'fixed', action=c.baselineSpeed-base;
            case 'baseline', action=0;
            case 'scripted', action=speedrl.scripted_residual(ctx,base,c);
            otherwise, error('speedrl:Policy','Unknown policy name.');
        end
    elseif isa(strategy,'function_handle')
        action=strategy(observation,ctx,base,c);
    else
        action=getAction(actor,{observation}); if iscell(action), action=action{1}; end
        action=double(action(1));
    end
    [observation,reward,done,s]=speedrl.step(action,s); info=s.lastInfo;
    rows(k,:)=[info.time,info.meanGroundSpeed,info.meanAirSpeed,info.appliedReference,...
        info.baseline,info.requestedResidual,info.meanPower,info.trueMeanPower,reward,...
        info.energyWh,info.meanWindAlong,info.meanWindNormal,s.sample.wind_valid,...
        info.powerCoverage,info.blockedFraction,s.sample.path_phase_rad,info.radialRms,s.sample.soc];
    assert(done==(k==n),'speedrl:Episode','Unexpected episode termination.');
end
names={'time_s','ground_speed_mps','air_speed_mps','reference_mps','baseline_mps',...
    'delta_v_mps','measured_power_w','true_power_w','reward','energy_wh',...
    'wind_tangent_mps','wind_normal_mps','wind_valid','power_coverage',...
    'blocked_fraction','path_phase_rad','radial_rms_m','soc'};
L=array2table(rows,'VariableNames',names);
meanPower=mean(L.true_power_w); energy=sum(L.energy_wh); endurance=c.usableEnergyWh/meanPower;
summary=struct('policy',policy_name(strategy),'seed',c.seed,'windMode',c.windMode,...
    'windObservation',c.windObservation,'trajectory',c.trajectory,'meanPowerW',meanPower,...
    'energyWh',energy,'estimatedEnduranceHours',endurance,...
    'minimumGroundSpeed',min(L.ground_speed_mps),'maximumGroundSpeed',max(L.ground_speed_mps),...
    'rateViolations',sum(abs(diff(L.reference_mps))>c.speedRate*c.decisionPeriod+1e-9),...
    'boundViolations',sum(L.reference_mps<c.speedBounds(1)-1e-9 | L.reference_mps>c.speedBounds(2)+1e-9),...
    'meanBlockedFraction',mean(L.blocked_fraction),'radialRms',sqrt(mean(L.radial_rms_m.^2)),...
    'meanPowerCoverage',mean(L.power_coverage));
end

function name=policy_name(strategy)
if ischar(strategy) || isstring(strategy), name=char(strategy);
elseif isa(strategy,'function_handle'), name='function_handle'; else, name='td3_agent'; end
end
