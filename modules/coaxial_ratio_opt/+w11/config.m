function c = config(varargin)
%CONFIG 工作包w11配置：固定速度下上下桨转速比的在线功率寻优。
% 对象: 每对共轴桨(定桨距变转速)在给定总拉力下的功率-桨比曲线。控制量
%   r = eta_Omega = Omega_u/Omega_l (上桨转速/下桨转速, Opazo 2022与项目任务书口径),
%   定义域 [0.75, 1.25](项目任务书表1仿真试验边界), 开环基线 r=1(等转速, PX4默认分配)。
% 真值模型(见 mt_chain.m / truth_curve.m 与 README"模型来源"):
%   Opazo et al. 2022 Eq.(27)-(35) MT链: 给定 eta_T 闭式解上下桨转速与功率;
%   下桨有效下洗系数 cdw 经标定使链最优 r*_mt = rStar0 = 0.89 (Opazo Sec V.C 飞试:
%   最小总电流在 eta_Omega≈0.89);
%   深度经功率变换 kappa 标定到 case 族(谷底/等转速功率比): 纯气动链谷底仅≈0.15%,
%   飞试口径(含电机/ESC效率与默认分配损失)节能≈4-5% → case∈{0.97,0.95,0.92},默认0.95;
%   漂移映射 dr(gamma)=r*_mt(gamma)-r*_mt(1) 与功率水平因子 Plev(gamma) 取自MT链数值
%   (gamma=等效诱导干扰因子, 乘在下桨有效下洗与诱导功率上; gamma=1基准标定态)。
%   归一化真值: P*(r;t) = Plev(gamma(t))·[S(r-dr(gamma)) + rip(r-dr(gamma)-rStar0)]
%   S=shape2(功率变换+仿射微调, S(1)=1, S(r0)=case), rip=双余弦涟漪(谷底补偿,
%   定义在r空间, 与速度包任务2同构)。argmin 精确= rStar0+dr(gamma), 值精确= Plev·case。
% 干扰场(interfer_field.m 七种模板, 类比wind_field): const/sin/square/triangle/
%   turb/composite/sector; sector 以积分航向为自变量(类比随航向的姿态/来流不对称)。
% 执行链(类比任务7): 通信时延0-0.5s FIFO + 桨比变化率限幅 |dr/dt|<=slewMax
%   (电机+ESC转速通道惯性) + 就位规则(settled_q, 与速度包同机制)。
% 飞行模式(flightMode): 'hover'(V=0) / 'fixed'(V=fwdSpeed) / 'vary'(V=fwdSpeed+波动),
%   V 只通过 (a) 总拉力配平 T=sqrt((mg)^2+(rho V^2 CdA)^2) 与 (b) 前飞功率水平因子
%   c_fwd(V)(速度包同款 Hwang 代理: P(6.3)/P(0)=0.913) 进入功率水平;
%   文献性质(Opazo): 最优桨比不随总拉力变化 → 变速行不改 r*, 只改功率水平。
% 方法论: 曲线/干扰未知(黑箱"调桨比→功率"), 四主角 sweepcal/rl/purerl/hybrid 纯因果
%   (ctrl_view 白名单), interfinfer/est/known 为已知曲线/干扰 oracle 参照;
%   MOE=Emin/Eactual(2026-09-04口径); 3×3表(悬停/前飞固定/变速 × 无干扰/恒定/漂移)。
c=struct('lower',0.75,'upper',1.25,'rStar0',0.89,...
    'ratioCase',0.95,...
    'rippleA1',0.005,'rippleL1',0.18,'rippleF1',pi,...
    'rippleA2',0.003,'rippleL2',0.06,'rippleF2',pi,...
    'noiseSigma',0.01,'impulse',false,'impulseRate',0.03,'impulseSize',0.10,...
    'tEval',1.0,'duration',600,'tailSteps',60,'seed',1,...
    'eps',0.02,...
    'initialRatio',1.0,'openLoopR',1.0,...
    'latencySec',0.3,'slewMax',0.15,'subSteps',10,...
    'flightMode','fixed','fwdSpeed',6.0,'varyAmp',2.0,'varyOmega',0.08,...
    'turnRadius',100,...
    'shiftTime',120,'jumpUpDg',0.06,'jumpDownDg',-0.05,'dyOffset',0.05,...
    'rampStart',60,'rampEnd',180,'rampDg',0.04,...
    'swLo',0.76,'swHi',1.24,'swSteps',150,'swRefitEvery',20,'swWinMax',220,...
    'ucProbeDelta',0.015,'ucProbeEvery',15,'ucGain',0.30,'ucB0',1.0,'ucThr',0.90,...
    'rlSigma',0.017,'rlSigmaMin',0.007,'rlLr',0.200,...
    'plSigma0',0.065,'plSigmaMin',0.030,'plLr',10.0,'plKern',1,'plHold',2,'plBins',12,...
    'hyRefitEvery',60,'hySseMargin',0.998,'hyInterfEvery',10,...
    'ifSweepMin',0.8,'ifEwma',0.5,...
    'estDither',0.02,'estQa',0.02,'estRmis',0.02,'estStepClamp',0.02,...
    'gammaAmp',0.0,'gammaOmega',0.08,'gammaBias',0.0,...
    'gammaAmpY',0.0,'gammaOmegaY',0.13,'gammaBiasY',0.0,...
    'gammaDirDeg',0,...
    'gammaKind','const','squareEdge',4.0,'turbStd',0.015,'turbTheta',0.2,...
    'energyAccounting',true);
if ~isempty(varargin) && isstruct(varargin{1})   % 支持以struct为基底覆盖
    base=varargin{1}; fn=fieldnames(base);
    for kb=1:numel(fn), c.(fn{kb})=base.(fn{kb}); end
    varargin(1)=[];
end
assert(mod(numel(varargin),2)==0,'w11:Config','Use name/value pairs.');
for k=1:2:numel(varargin)
    key=char(varargin{k}); assert(isfield(c,key),'w11:Config','Unknown setting: %s',key);
    c.(key)=varargin{k+1};
end
assert(islogical(c.energyAccounting) && isscalar(c.energyAccounting),...
    'w11:Config','energyAccounting must be logical.');
assert(islogical(c.impulse) && isscalar(c.impulse),'w11:Config','impulse must be logical.');
positive={'tEval','duration','tailSteps','eps','initialRatio','openLoopR',...
    'latencySec','slewMax','subSteps','fwdSpeed','varyAmp','varyOmega','turnRadius',...
    'shiftTime','dyOffset','rampStart','rampEnd','rampDg',...
    'rippleA1','rippleL1','rippleA2','rippleL2','noiseSigma','impulseRate','impulseSize',...
    'seed','gammaAmp','gammaBias','gammaAmpY','gammaBiasY','turbStd',...
    'estDither','estQa','estRmis','estStepClamp',...
    'ifSweepMin','ifEwma','swLo','swHi','swSteps','swRefitEvery','swWinMax',...
    'ucProbeDelta','ucProbeEvery','ucGain','ucB0','ucThr',...
    'rlSigma','rlSigmaMin','rlLr',...
    'plSigma0','plSigmaMin','plLr','plKern','plHold','plBins',...
    'hyInterfEvery','hyRefitEvery','hySseMargin'};
for k=1:numel(positive), validateattributes(c.(positive{k}),{'double'},...
    {'scalar','real','finite','nonnegative'}); end
signed={'jumpUpDg','jumpDownDg','gammaDirDeg','gammaOmega','gammaOmegaY'};
for k=1:numel(signed), validateattributes(c.(signed{k}),{'double'},{'scalar','real','finite'}); end
assert(ischar(c.gammaKind) && any(strcmp(c.gammaKind,...
    {'const','sin','square','triangle','turb','composite','sector'})),...
    'w11:Config','gammaKind must be const/sin/square/triangle/turb/composite/sector.');
assert(c.squareEdge>=0.5,'w11:Config','squareEdge must be >=0.5.');
assert(c.turbStd>=0 && c.turbTheta>0,'w11:Config','turbStd>=0, turbTheta>0.');
assert(any(abs(c.ratioCase-[0.97 0.95 0.92])<1e-12),'w11:Config',...
    'ratioCase must be 0.97 / 0.95 / 0.92 (谷底/等转速功率比).');
assert(c.lower>=0.7 && c.upper>c.lower && c.rStar0>c.lower && c.rStar0<c.upper,...
    'w11:Config','Invalid bounds/rStar0.');
assert(c.upper-c.lower>=0.4,'w11:Config','ratio domain too narrow.');
% ---- 有效范围(工程口径, 类比任务7) ----
assert(c.latencySec>=0 && c.latencySec<=0.5,'w11:Config','latencySec in [0,0.5] s.');
assert(c.slewMax>=0.02 && c.slewMax<=1.0,'w11:Config','slewMax in [0.02,1.0] r/s.');
assert(c.subSteps>=10 && mod(c.subSteps,1)==0,'w11:Config','subSteps integer >=10.');
assert(c.duration>c.tailSteps,'w11:Config','duration too short.');
assert(any(strcmp(c.flightMode,{'hover','fixed','vary'})),'w11:Config',...
    'flightMode must be hover/fixed/vary.');
% ================= 真值模型标定(确定性, 无随机数; 详见 mt_chain/truth_curve) ================
% ---- MT链物理常数(Opazo Table 1 / Sec IV; 15kg X8 每臂, 悬停总拉力对齐台架35N档) ----
c.rotorR=0.3112;                 % 桨半径 m (31.12 cm)
c.diskA=pi*c.rotorR^2;           % 桨盘面积 m²
c.nBlades=2;                     % KDE-CF245-DP 双叶 (X8 用桨)
c.chord=0.04;                    % 平均弦长 m (~4.0 cm)
c.rho=1.1849;                    % 空气密度 kg/m³ (论文测试间)
c.cd=0.0094;                     % Nb=2 剖面阻力系数 (论文 Sec IV.B 拟合)
c.kInd=1.15;                     % 诱导功率因子 (论文取值)
c.aT=6.2e-4;                     % T=aT·Ω² 拟合 N·s²/rad² (Fig.7a: 120N@4200RPM)
c.clalpha=2*pi;                  % 升力线斜率 /rad
c.sigCd8=(c.nBlades*c.chord/(pi*c.rotorR))*c.cd/8.0;  % sigma·cd/8 (sigma=0.0818, Table 1)
c.c2=c.nBlades*c.rho*c.clalpha*c.rotorR^2/4.0;        % 下桨BET积分二次式一次项系数
c.totThrust=15.0*9.81/4;         % 每臂总拉力 N (悬停配平 ≈36.8 N)
% 1) 下桨有效下洗系数 cdw: 二分标定使 MT 链最优 r*_mt(gamma=1) = rStar0 (飞试0.89锚点)
c.cdw = w11.calibrate_cdw(c);
% 2) r→η_T 反演网格(γ=1, 已标定 cdw; r(η_T) 严格单调增)
c.etaGrid=linspace(0.30,14.0,1600);
c.rGrid=w11.r_of_etaT(c.etaGrid,c,c.cdw,1.0);
assert(all(diff(c.rGrid)>0),'w11:Config','r(etaT) must be strictly increasing.');
% 3) 漂移映射: gamma 网格上 r*_mt(gamma) 与功率水平因子 Plev(gamma)
gGrid=linspace(0.85,1.20,36);
rStarG=zeros(size(gGrid)); P1G=zeros(size(gGrid));
for ig=1:numel(gGrid)
    [rStarG(ig),P1G(ig)]=w11.mt_chain_valley(gGrid(ig),c);
end
i1=find(abs(gGrid-1)<1e-12,1); P1base=P1G(i1); rStar1=rStarG(i1);
PminBase=w11.mt_chain(rStar1,c,1.0);          % 链在谷底的功率(γ=1)
kappa=log(c.ratioCase)/log(PminBase/P1base);  % 深度标定指数(飞试4-5%口径)
c.drMapG=gGrid(:).'; c.drMapD=(rStarG-rStar1);      % gamma → Δr* (锚定在 rStar0, 增量取链)
c.levMapG=gGrid(:).'; c.levMapP=(P1G/P1base).^kappa;% gamma → 功率水平因子
c.kappa=kappa; c.chainDepth=PminBase/P1base;        % 记录: 纯气动链深度(诊断/README)
c.chainP1Ref=P1base;
% 仿射微调(吸收涟漪在两锚点的取值, 使 P(rStar0)=case 与 P(1)=1 精确成立):
rip1 = c.rippleA1*cos(2*pi*(1-c.rStar0)/c.rippleL1 + c.rippleF1) ...
     + c.rippleA2*cos(2*pi*(1-c.rStar0)/c.rippleL2 + c.rippleF2);
c.shapeAlpha = (c.ratioCase - 1 + c.rippleA1 + c.rippleA2 + rip1)/(c.ratioCase - 1);
c.shapeBeta  = 1 - rip1 - c.shapeAlpha;

% 4) 归一化真值曲线(γ=1 形状, 含涟漪与仿射补偿) 精细表(运行期线性插值)
nf=4001; c.rFine=linspace(c.lower,c.upper,nf);
c.PFine=w11.truth_curve(c.rFine,c);
assert(all(isfinite(c.PFine)),'w11:Config','Truth curve non-finite.');
[~,im0]=min(c.PFine);
assert(abs(c.rFine(im0)-c.rStar0)<2e-3,'w11:Config','Truth valley must sit at rStar0.');
% 5) 前飞功率水平因子(速度包同款 Hwang 代理锚点: P(6.3)/P(0)=0.913, P(20)/P(0)=1.297)
%    文献性质(Opazo Sec IV): 功率-桨比形状与最优点不随总拉力变化 → 飞行模式行
%    (悬停/前飞固定/变速)只通过本因子改变功率水平, 不移动 r*。
Vf=[0 6.3 20]; Pf=[1 0.913 1.297];
M=[0 0 0 1; 6.3^3 6.3^2 6.3 1; 3*6.3^2 2*6.3 1 0; 20^3 20^2 20 1];
c.fwdCoef=(M\[1; 0.913; 0; 1.297]).';
assert(max(abs(polyval(c.fwdCoef,Vf)-Pf))<1e-9,'w11:Config','fwd factor anchors.');
end
