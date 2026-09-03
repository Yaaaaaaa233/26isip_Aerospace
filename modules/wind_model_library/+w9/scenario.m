function scn = scenario(kind, c)
%SCENARIO 平移调度 + 任务9风场模型装配(评价侧, 不给搜索器)。
% 平移调度种类与任务6一致, 可与风场叠加：
%   static    无平移(崎岖静态+风致周期偏移, 任务7主口径)
%   jumpUp    第 shiftTime 秒 dx 跳 +jumpUpDx（默认+2.7）
%   jumpDown  第 shiftTime 秒 dx 跳 jumpDownDx（默认-2.3）
%   offset    第 shiftTime 秒 dy 上移 dyOffset（argmin 不变, 考验不误触发）
%   ramp      rampStart..rampEnd 秒 dx 线性慢漂 +rampDx
% 风场装配(wind_field.m 七种模型): 时间类模型直接携带参数; 湍流类
% ('turb'/'composite')在此预生成 Ornstein-Uhlenbeck 序列 —— 用独立种子流
% (seed+917), 生成前后保存/恢复全局RNG状态, 保证确定性且不影响后续
% plant 的测量噪声流。序列覆盖 [0, duration*tEval+2格], 步长0.1s(与对象
% 子步一致), plant/预览按时间线性插值取值。
t1=c.shiftTime;
switch kind
    case 'static',   jumps=zeros(0,3); ramps=zeros(0,3);
    case 'jumpUp',   jumps=[t1 c.jumpUpDx 0];   ramps=zeros(0,3);
    case 'jumpDown', jumps=[t1 c.jumpDownDx 0]; ramps=zeros(0,3);
    case 'offset',   jumps=[t1 0 c.dyOffset];   ramps=zeros(0,3);
    case 'ramp',     jumps=zeros(0,3); ramps=[c.rampStart c.rampEnd c.rampDx];
    otherwise, error('w9:Scenario','Unknown scenario kind: %s',kind);
end
scn=struct('kind',kind,'jumps',jumps,'ramps',ramps,...
    'windAmp',c.windAmp,'windOmega',c.windOmega,'windBias',c.windBias,...
    'windAmpY',c.windAmpY,'windOmegaY',c.windOmegaY,'windBiasY',c.windBiasY,...
    'windDirDeg',c.windDirDeg,...
    'windKind',c.windKind,'squareEdge',c.squareEdge,...
    'turbStd',c.turbStd,'turbTheta',c.turbTheta,...
    'windT',[],'windTurbX',[],'windTurbY',[]);
if any(strcmp(c.windKind,{'turb','composite'}))
    dt=0.1; Tmax=c.duration*c.tEval;
    scn.windT=0:dt:(Tmax+2*dt);
    sg=c.turbStd;
    if strcmp(c.windKind,'turb'), sg=c.windAmp; end   % turb族: A即湍流强度
    sState=rng; rng(c.seed+917);                       % 独立种子流, 不污染全局
    clean=onCleanup(@() rng(sState)); %#ok<NASGU>
    th=c.turbTheta; sX=sg*sqrt(2*th*dt);               % 平稳std(ξ)=sg: σ²/(2θ)=sg²
    Nx=numel(scn.windT);
    tx=zeros(1,Nx); ty=zeros(1,Nx);
    zx=randn(1,Nx-1); zy=randn(1,Nx-1);
    for i=1:Nx-1
        tx(i+1)=tx(i)-th*tx(i)*dt+sX*zx(i);
        ty(i+1)=ty(i)-th*ty(i)*dt+sX*zy(i);
    end
    scn.windTurbX=tx; scn.windTurbY=ty;
end
end
