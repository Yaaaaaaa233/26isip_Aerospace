function validate_config(c)
positive = {'Ts','duration','tau','rateLimit','amplitude','frequency',...
    'hpOmega','lpOmega','gain','curvature','rlPeriod'};
for k = 1:numel(positive)
    validateattributes(c.(positive{k}),{'double'},{'scalar','real','finite','positive'});
end
numeric = {'lower','upper','initialRatio','fixedReference','optimalRatio',...
    'shiftedOptimalRatio','shiftTime','noiseSigma','delay','seed'};
for k = 1:numel(numeric)
    validateattributes(c.(numeric{k}),{'double'},{'scalar','real','finite'});
end
assert(c.lower<c.upper && 2*c.amplitude<c.upper-c.lower,'ratioesc:Config','Invalid bounds/amplitude.');
for name = {'initialRatio','fixedReference','optimalRatio','shiftedOptimalRatio'}
    x=c.(name{1});
    assert(x>=c.lower && x<=c.upper,'ratioesc:Config','Ratio outside experiment bounds.');
end
assert(c.noiseSigma>=0 && c.delay>=0 && c.delay<c.duration,'ratioesc:Config','Invalid measurement settings.');
assert(c.seed>=0 && c.seed==floor(c.seed),'ratioesc:Config','Seed must be a nonnegative integer.');
assert(c.frequency*c.Ts<0.5,'ratioesc:Config','Dither must be below Nyquist.');
for x = [c.duration c.delay c.rlPeriod]
    assert(abs(x/c.Ts-round(x/c.Ts))<1e-8,'ratioesc:Config','Times must be integer sample multiples.');
end
assert(any(strcmp(c.stage,{'static','feedback','dither','esc','rl'})),'ratioesc:Config','Unknown stage.');
assert(any(strcmp(c.scenario,{'stationary','shift'})),'ratioesc:Config','Unknown scenario.');
end
