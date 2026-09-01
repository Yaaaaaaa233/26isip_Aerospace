function c = config(varargin)
%CONFIG Task-1 settings: instant-jump black-box search on a shifting curve.
% 全部为算法与评价侧参数；曲线、平移真值与噪声属于场景(+task1.scenario)，
% 控制器侧接口见 +task1/controller_config.m 白名单。
%
% energyAccounting 是"是否考虑搜索能耗"的开关：
%   true  = 计入寻优过程本身消耗的能量，用于评分与验收(续航纪录口径)；
%   false = 只评价定位精度与稳态指标，能耗列记 NaN、能耗阈值不参与判定。
c=struct('curve','cubic','optimum0',NaN,'initialSpeed',10,...
    'lower',0,'upper',20,'minimumRatio',0.913,...
    'tEval',1.0,'duration',400,'tol',0.02,'maxSearchEval',60,'eps',0.05,...
    'energyAccounting',true,'tailSteps',60,...
    'probeDelta',0.5,'probePeriod',10,'slopeThresh',0.002,'slopeRelease',0.0005,...
    'bracketSpan0',3.0,'bracketGrow',2.0,'bracketRetry',2,...
    'escA',0.5,'escOmega',0.5,'escGain',NaN,'escLpOmega',0.5,'escWindow',NaN,...
    'escInitial',10,'gridResolution',0.2);
assert(mod(nargin,2)==0,'task1:Config','Use name/value pairs.');
for k=1:2:nargin
    key=char(varargin{k}); assert(isfield(c,key),'task1:Config','Unknown setting: %s',key);
    c.(key)=varargin{k+1};
end
assert(any(strcmp(c.curve,{'debug','cubic'})),'task1:Config','Unknown curve.');
assert(islogical(c.energyAccounting) && isscalar(c.energyAccounting),...
    'task1:Config','energyAccounting must be a logical scalar.');
if isnan(c.optimum0), if strcmp(c.curve,'debug'), c.optimum0=6; else, c.optimum0=6.3; end, end
if isnan(c.escGain), if strcmp(c.curve,'debug'), c.escGain=22; else, c.escGain=4; end, end
if isnan(c.escWindow), c.escWindow=max(4,ceil(pi/(c.escOmega*c.tEval))); end
positive={'tEval','duration','tol','maxSearchEval','eps','tailSteps','probeDelta',...
    'probePeriod','slopeThresh','slopeRelease','bracketSpan0','bracketGrow','bracketRetry',...
    'escA','escOmega','escGain','escLpOmega','escWindow','escInitial','gridResolution'};
for k=1:numel(positive), validateattributes(c.(positive{k}),{'double'},...
    {'scalar','real','finite','positive'}); end
for name={'lower','upper','optimum0','initialSpeed'}
    validateattributes(c.(name{1}),{'double'},{'scalar','real','finite'}); end
validateattributes(c.minimumRatio,{'double'},{'scalar','>',0,'<',1});
assert(c.lower>=0 && c.upper>c.lower,'task1:Config','Invalid bounds.');
assert(c.optimum0>=c.lower && c.optimum0<=c.upper,'task1:Config','Base optimum outside bounds.');
assert(c.initialSpeed>=c.lower && c.initialSpeed<=c.upper,'task1:Config','Initial speed outside bounds.');
assert(c.escInitial>=c.lower+c.escA && c.escInitial<=c.upper-c.escA,...
    'task1:Config','ESC initial center must leave dither margin.');
assert(c.duration>c.tailSteps && c.duration>c.maxSearchEval,...
    'task1:Config','Horizon must exceed evaluation budget and tail window.');
assert(c.slopeRelease<c.slopeThresh,'task1:Config','slopeRelease must be below slopeThresh.');
assert(c.probeDelta>0 && 2*c.probeDelta<c.upper-c.lower,'task1:Config','Invalid probe delta.');
assert(c.gridResolution<c.upper-c.lower,'task1:Config','Grid resolution too coarse for bounds.');
assert(c.escOmega*c.tEval<pi,'task1:Config','Dither period must span multiple samples.');
end
