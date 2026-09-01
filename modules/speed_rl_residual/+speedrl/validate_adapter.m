function [state,sample] = validate_adapter(adapter,c)
%VALIDATE_ADAPTER Check the public teammate-facing contract.
assert(isstruct(adapter) && isfield(adapter,'reset') && isfield(adapter,'step') && ...
    isa(adapter.reset,'function_handle') && isa(adapter.step,'function_handle'),...
    'speedrl:Adapter','Adapter needs reset and step function handles.');
[state,sample]=adapter.reset(c.seed,c); speedrl.validate_sample(sample);
[state,sample]=adapter.step(state,c.baselineSpeed,c.Ts); speedrl.validate_sample(sample);
end
