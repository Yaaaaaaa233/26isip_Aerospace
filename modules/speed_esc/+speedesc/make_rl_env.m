function env = make_rl_env(c)
if nargin<1, c=speedesc.config(); end
observation=rlNumericSpec([24 1]); observation.Name='speed_power_history';
action=rlNumericSpec([1 1],'LowerLimit',c.lower,'UpperLimit',c.upper);
action.Name='speed_reference_mps';
env=rlFunctionEnv(observation,action,@speedesc.rl_step,@()speedesc.rl_reset(c));
end
