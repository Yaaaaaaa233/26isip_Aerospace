function c = config(varargin)
%CONFIG SI-unit speed ESC settings. All values are simulation parameters.
c=struct('version',3,'curve','cubic','method','regression','mode','esc',...
    'Ts',0.1,'duration',120,'initialSpeed',10,'lower',0,'upper',20,...
    'tau',2,'noiseSigma',0.02,'delay',0.5,'seed',1,'shift',true,...
    'shiftTime',60,'optimum',NaN,'shiftedOptimum',9,'minimumRatio',0.913,...
    'amplitude',0.5,'omega',0.5,'gain',NaN,'hpOmega',0.1,'lpOmega',NaN,...
    'window',NaN,'minimumSpeedStd',0.025,'gradientLimit',1,...
    'centerRate',0.8,'referenceRate',1,'maxAge',2,'fixedReference',10,...
    'tailSeconds',20,'settlingWindow',12.6,'settlingHold',5,'rlPeriod',1);
assert(mod(nargin,2)==0,'speedesc:Config','Use name/value pairs.');
for k=1:2:nargin
    key=char(varargin{k}); assert(isfield(c,key),'speedesc:Config','Unknown setting: %s',key);
    c.(key)=varargin{k+1};
end
assert(any(c.version==[1 2 3]) && isscalar(c.version),'speedesc:Config','Version must be 1, 2 or 3.');
assert(any(strcmp(c.curve,{'debug','cubic'})) && any(strcmp(c.method,{'regression','demod'})) && ...
    any(strcmp(c.mode,{'esc','dither','fixed'})),'speedesc:Config','Unknown curve/method/mode.');
if isnan(c.optimum), if strcmp(c.curve,'debug'), c.optimum=6; else, c.optimum=6.3; end, end
if isnan(c.gain)
    if strcmp(c.method,'regression')
        if strcmp(c.curve,'debug'), c.gain=22; else, c.gain=8; end
    else
        if strcmp(c.curve,'debug'), c.gain=8; else, c.gain=2; end
    end
end
if isnan(c.lpOmega), if strcmp(c.method,'regression'), c.lpOmega=2; else, c.lpOmega=0.05; end, end
if c.version<3, c.noiseSigma=0; c.delay=0; c.shift=false; end
positive={'Ts','duration','tau','amplitude','omega','gain','hpOmega','lpOmega',...
    'minimumSpeedStd','gradientLimit','centerRate','referenceRate','maxAge',...
    'tailSeconds','settlingWindow','settlingHold','rlPeriod'};
for k=1:numel(positive), validateattributes(c.(positive{k}),{'double'},{'scalar','real','finite','positive'}); end
if isnan(c.window), c.window=round(2*pi/(c.omega*c.Ts)); end
validateattributes(c.window,{'double'},{'scalar','integer','>=',4,'<=',10000});
for name={'delay','noiseSigma'}, validateattributes(c.(name{1}),{'double'},{'scalar','real','finite','nonnegative'}); end
validateattributes(c.seed,{'double'},{'scalar','integer','>=',0,'<=',2^32-1});
validateattributes(c.minimumRatio,{'double'},{'scalar','>',0,'<',1});
for name={'lower','upper','initialSpeed','fixedReference','optimum','shiftedOptimum','shiftTime'}
    validateattributes(c.(name{1}),{'double'},{'scalar','real','finite'});
end
assert(c.lower>=0 && c.upper>c.lower && 2*c.amplitude<c.upper-c.lower,'speedesc:Config','Invalid bounds/dither.');
assert(c.initialSpeed>=c.lower && c.initialSpeed<=c.upper && c.fixedReference>=c.lower && ...
    c.fixedReference<=c.upper,'speedesc:Config','Initial/fixed reference outside bounds.');
assert(c.optimum>0 && c.optimum>=c.lower && c.optimum<=c.upper && c.shiftedOptimum>0 && ...
    c.shiftedOptimum>=c.lower && c.shiftedOptimum<=c.upper,'speedesc:Config','Invalid proxy optimum.');
assert(c.duration>=c.tailSeconds && c.Ts*c.window<c.duration,'speedesc:Config','Run is shorter than evaluation/warmup.');
assert(c.maxAge>=c.delay,'speedesc:Config','maxAge must cover the configured delay.');
assert(~c.shift || (c.shiftTime>0 && c.shiftTime<c.duration-c.tailSeconds),...
    'speedesc:Config','Shift must leave a full evaluation window.');
ratios=[c.duration,c.delay,c.shiftTime,c.rlPeriod]/c.Ts;
assert(all(abs(ratios-round(ratios))<1e-8),'speedesc:Config','Time values must be integer Ts multiples.');
end
