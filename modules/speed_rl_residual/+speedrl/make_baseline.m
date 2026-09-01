function baseline = make_baseline(kind)
%MAKE_BASELINE Pure measured-context reference provider.
if nargin<1, kind='fixed'; end
switch kind
    case 'fixed', fn=@fixed;
    case 'wind_analytic', fn=@windAnalytic;
    otherwise, error('speedrl:Baseline','Unknown baseline: %s',kind);
end
baseline=struct('name',kind,'reference',fn);
end

function [v,info]=fixed(ctx)
v=ctx.baselineDefault; info=struct('method','fixed','usedWind',false);
end

function [v,info]=windAnalytic(ctx)
used=ctx.windValid;
if used
    along=dot(ctx.windNE,ctx.tangentNE);
    normal=dot(ctx.windNE,[-ctx.tangentNE(2);ctx.tangentNE(1)]);
    v=along+sqrt(max(ctx.optimumAirSpeed^2-normal^2,0));
else
    v=ctx.baselineDefault;
end
v=min(max(v,ctx.speedBounds(1)),ctx.speedBounds(2));
info=struct('method','wind_analytic','usedWind',used);
end
