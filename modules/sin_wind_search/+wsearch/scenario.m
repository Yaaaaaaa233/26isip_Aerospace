function scn = scenario(kind, c)
%SCENARIO 平移调度(评价侧, 不给搜索器)。种类(与统一程序一致, 可与风场叠加)：
%   static    无平移(崎岖静态+风场周期偏移, 任务3主口径)
%   jumpUp    第 shiftTime 秒 dx 跳 +jumpUpDx（默认+2.7）
%   jumpDown  第 shiftTime 秒 dx 跳 jumpDownDx（默认-2.3）
%   offset    第 shiftTime 秒 dy 上移 dyOffset（argmin 不变, 考验不误触发）
%   ramp      rampStart..rampEnd 秒 dx 线性慢漂 +rampDx
t1=c.shiftTime;
switch kind
    case 'static',   jumps=zeros(0,3); ramps=zeros(0,3);
    case 'jumpUp',   jumps=[t1 c.jumpUpDx 0];   ramps=zeros(0,3);
    case 'jumpDown', jumps=[t1 c.jumpDownDx 0]; ramps=zeros(0,3);
    case 'offset',   jumps=[t1 0 c.dyOffset];   ramps=zeros(0,3);
    case 'ramp',     jumps=zeros(0,3); ramps=[c.rampStart c.rampEnd c.rampDx];
    otherwise, error('wsearch:Scenario','Unknown scenario kind: %s',kind);
end
scn=struct('kind',kind,'jumps',jumps,'ramps',ramps,...
    'windAmp',c.windAmp,'windOmega',c.windOmega,'windBias',c.windBias,...
    'circlePeriod',c.circlePeriod,...
    'windDirDeg',c.windDirDeg,'windDxGain',c.windDxGain,'windDyGain',c.windDyGain);
end
