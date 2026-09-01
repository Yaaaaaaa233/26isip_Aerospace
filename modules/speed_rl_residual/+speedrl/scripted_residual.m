function delta = scripted_residual(ctx,base,c)
%SCRIPTED_RESIDUAL Observable-wind reference only; it is NOT a learned policy.
if ~ctx.windValid
    desired=base;
else
    along=ctx.windAlong; normal=ctx.windNormal;
    desired=along+sqrt(max(c.optimumAirSpeed^2-normal^2,0));
end
desired=min(max(desired,c.speedBounds(1)),c.speedBounds(2));
delta=min(max(desired-base,c.deltaBounds(1)),c.deltaBounds(2));
end
