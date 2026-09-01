function env = make_env(c,adapter,baseline,training)
%MAKE_ENV R2022b rlFunctionEnv with local deterministic seed cycling.
if nargin<1, c=speedrl.config(); end
if nargin<2 || isempty(adapter), adapter=speedrl.make_synthetic_adapter(); end
if nargin<3 || isempty(baseline), baseline=speedrl.make_baseline('fixed'); end
if nargin<4, training=false; end
obs=rlNumericSpec([18*c.history 1]); obs.Name='measured_residual_context_history';
act=rlNumericSpec([1 1],'LowerLimit',c.deltaBounds(1),'UpperLimit',c.deltaBounds(2));
act.Name='delta_speed_mps'; counter=0;
env=rlFunctionEnv(obs,act,@speedrl.step,@resetLocal);
    function [o,s]=resetLocal()
        cc=c; cc.training=logical(training);
        if training, cc.seed=mod(c.seed+counter,2^32); counter=counter+1; end
        [o,s]=speedrl.reset(cc,adapter,baseline);
    end
end
