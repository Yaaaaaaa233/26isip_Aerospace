function c = config(varargin)
%CONFIG 环境风场研究模块设置（TASKS_1_5_ROUTE §3-5 路线口径）。
% 对象侧（空速物理）：飞机沿半径R的圆轨迹飞行，地速 v(t) 为被控量；
%   空速矢量 u = v·t̂(t) + w(t)，t̂=航向单位矢量；功率 P = P0(|u|)。
% 功率曲线沿用仓库三次文献代理（speed_esc 同源）：
%   P0(x)=1−1.5b·x²+b·x³, x=u/V*, b=2(1−P*)，V*=6.3 m/s, P*=0.913。
% 风场三模式（任务3/4/5同一公式的三个特例）：
%   'const' 恒定风 |w|=windSpeed 沿风向角 windDirDeg
%   'sin'   单向正弦风 W(t)=A·sin(ω1·t)+B（任务4）
%   'dual'  双正交风 x:A·sin(ω1t)+B, y:C·sin(ω2t)+D（任务5）
% 黑箱红线：console 只见测量功率/自身指令/航向与时间（红线1）。
c=struct('vLower',2.0,'vUpper',15.0,...
    'Vstar',6.3,'Pstar',0.913,...
    'circlePeriod',80.0,'circleRadius',500.0,...
    'windMode','dual','windSpeed',3.0,...
    'windAmp',2.0,'windOmega',0.08,'windBias',3.0,...
    'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1.0,...
    'windDirDeg',0.0,...
    'noiseSigma',0.005,...
    'tEval',1.0,'duration',400,'tailSteps',60,'seed',1,...
    'estWindow',160,'estLmDamp',1e-3,...          % 在线风估计: 滑窗LM
    'obsDuty',8,'obsDither',0.9,...              % 在线版观测性激励(占空比dither)
    'blindPeriod',80,'blindStep',0.4,...         % 不知风: 匀速在线搜索
    'dpGridN',131,'dpRateMax',0.6,...
    'energyAccounting',true);
baseArgs=varargin;
if ~isempty(baseArgs) && isstruct(baseArgs{1})
    base=baseArgs{1};                      % 以既有config为底再覆盖
    fn=fieldnames(base);
    for k=1:numel(fn), c.(fn{k})=base.(fn{k}); end
    baseArgs(1)=[];
end
assert(mod(numel(baseArgs),2)==0,'wind:Config','Use name/value pairs.');
for k=1:2:numel(baseArgs)
    key=char(baseArgs{k}); assert(isfield(c,key),'wind:Config','Unknown setting: %s',key);
    c.(key)=baseArgs{k+1};
end
assert(any(strcmp(c.windMode,{'const','sin','dual'})),'wind:Config','windMode invalid.');
assert(islogical(c.energyAccounting) && isscalar(c.energyAccounting),'wind:Config','energyAccounting logical.');
positive={'vLower','vUpper','Vstar','Pstar','circlePeriod','circleRadius','windSpeed',...
    'windAmp','windOmega','windBias','windAmpY','windOmegaY','windBiasY',...
    'noiseSigma','tEval','duration','tailSteps','seed','estWindow','estLmDamp',...
    'obsDuty','obsDither','blindPeriod','blindStep','dpGridN','dpRateMax'};
for k=1:numel(positive), validateattributes(c.(positive{k}),{'double'},...
    {'scalar','real','finite','nonnegative'}); end
signed={'windDirDeg'};
for k=1:numel(signed), validateattributes(c.(signed{k}),{'double'},{'scalar','real','finite'}); end
assert(c.vLower>0 && c.vUpper>c.vLower,'wind:Config','Invalid speed bounds.');
assert(c.Pstar>0 && c.Pstar<1 && c.Vstar>0,'wind:Config','Invalid proxy curve anchors.');
assert(c.duration>c.tailSteps,'wind:Config','duration must exceed tailSteps.');
assert(c.estWindow>=12,'wind:Config','estWindow too short for estimation.');
assert(mod(c.obsDuty,1)==0 && mod(c.blindPeriod,1)==0,'wind:Config','Integer periods required.');
end
