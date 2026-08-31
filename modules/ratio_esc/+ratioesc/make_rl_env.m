function env = make_rl_env(c)
%MAKE_RL_ENV MATLAB R2022b-compatible rlFunctionEnv adapter, no training.
if nargin<1, c=ratioesc.config(); end
observation=rlNumericSpec([4 1],'LowerLimit',[0;0;-Inf;-Inf],...
    'UpperLimit',[1;1;Inf;Inf]);
observation.Name='measured_state';
observation.Description='normalized actual ratio, normalized applied reference, mean measured J, delta J';
action=rlNumericSpec([1 1],'LowerLimit',c.lower,'UpperLimit',c.upper);
action.Name='eta_omega_reference';
env=rlFunctionEnv(observation,action,@ratioesc.rl_step,@()ratioesc.rl_reset(c));
end
