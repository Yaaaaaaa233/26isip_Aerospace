function c = config(varargin)
%CONFIG Defaults for a dimensionless, constant-thrust proxy experiment.
c = struct('Ts',0.05,'duration',600,'initialRatio',1.2,...
    'lower',0.75,'upper',1.25,'tau',0.25,'rateLimit',0.05,...
    'amplitude',0.02,'frequency',0.1,'hpOmega',0.05,...
    'lpOmega',0.05,'gain',0.003,'noiseSigma',0,'delay',0,...
    'seed',1,'stage','esc','scenario','stationary','fixedReference',0.95,...
    'optimalRatio',0.9,'shiftedOptimalRatio',1.05,'shiftTime',300,...
    'curvature',4,'rlPeriod',1);
if nargin == 1 && isstruct(varargin{1})
    u = varargin{1}; names = fieldnames(u);
    for k = 1:numel(names)
        assert(isfield(c,names{k}),'ratioesc:Config','Unknown setting: %s',names{k});
        c.(names{k}) = u.(names{k});
    end
elseif nargin > 0
    assert(mod(nargin,2)==0,'ratioesc:Config','Use name/value pairs.');
    for k = 1:2:nargin
        key = char(varargin{k});
        assert(isfield(c,key),'ratioesc:Config','Unknown setting: %s',key);
        c.(key) = varargin{k+1};
    end
end
ratioesc.validate_config(c);
end
