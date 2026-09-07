function scn = scenario(kind, c)
%SCENARIO 场景装配(评价侧, 不给搜索器): γ 调度 + 干扰场模板 + 飞行模式 + 湍动序列。
% 场景种类(类比任务6, 变量为干扰因子γ):
%   static    无调度(干扰场模板+飞行模式本身, 主口径)
%   jumpUp    第 shiftTime 秒 γ 阶跃 +jumpUpDg（默认+0.06, r* 上移≈0.03）
%   jumpDown  第 shiftTime 秒 γ 阶跃 jumpDownDg（默认-0.05）
%   offset    第 shiftTime 秒 纯功率水平上移 dyOffset（r* 不变, 考验不误触发）
%   ramp      rampStart..rampEnd 秒 γ 线性慢漂 +rampDg
% 飞行模式(c.flightMode): hover(V=0) / fixed(V=fwdSpeed) / vary(V=fwdSpeed+varyAmp·sin)。
%   V(t) 与指令无关(航迹/转速通道解耦), 故每子步的 (t,ψ) 可预生成。
% 湍动序列('turb'/'composite'): 独立种子流(seed+917)预生成 Ornstein-Uhlenbeck,
%   保存/恢复全局RNG, 确定性且不污染 plant 测量噪声流; 步长0.1s, 运行期线性插值。
t1=c.shiftTime;
switch kind
    case 'static',   jumps=zeros(0,2); ramps=zeros(0,3); dys=zeros(0,2);
    case 'jumpUp',   jumps=[t1 c.jumpUpDg];   ramps=zeros(0,3); dys=zeros(0,2);
    case 'jumpDown', jumps=[t1 c.jumpDownDg]; ramps=zeros(0,3); dys=zeros(0,2);
    case 'offset',   jumps=zeros(0,2); ramps=zeros(0,3); dys=[t1 c.dyOffset];
    case 'ramp',     jumps=zeros(0,2); ramps=[c.rampStart c.rampEnd c.rampDg]; dys=zeros(0,2);
    otherwise, error('w11:Scenario','Unknown scenario kind: %s',kind);
end
scn=struct('kind',kind,'jumps',jumps,'ramps',ramps,'dys',dys,...
    'flightMode',c.flightMode,'fwdSpeed',c.fwdSpeed,'varyAmp',c.varyAmp,...
    'varyOmega',c.varyOmega,'turnRadius',c.turnRadius,...
    'gammaAmp',c.gammaAmp,'gammaOmega',c.gammaOmega,'gammaBias',c.gammaBias,...
    'gammaKind',c.gammaKind,'squareEdge',c.squareEdge,...
    'turbStd',c.turbStd,'turbTheta',c.turbTheta,'gammaDirDeg',c.gammaDirDeg,...
    'intT',[],'intTurbX',[]);
if any(strcmp(c.gammaKind,{'turb','composite'}))
    dt=0.1; Tmax=c.duration*c.tEval;
    scn.intT=0:dt:(Tmax+2*dt);
    sg=c.turbStd;
    if strcmp(c.gammaKind,'turb')      % turb族: A=湍动强度(2026-09-07口径移植)
        sg=c.gammaAmp;
    end
    sState=rng; rng(c.seed+917);       % 独立种子流, 不污染全局
    clean=onCleanup(@() rng(sState)); %#ok<NASGU>
    th=c.turbTheta; sX=sg*sqrt(2*th*dt);               % 平稳std(ξ)=σ
    Nx=numel(scn.intT);
    tx=zeros(1,Nx);
    zx=randn(1,Nx-1);
    for i=1:Nx-1
        tx(i+1)=tx(i)-th*tx(i)*dt+sX*zx(i);
    end
    scn.intTurbX=tx;
end
end
