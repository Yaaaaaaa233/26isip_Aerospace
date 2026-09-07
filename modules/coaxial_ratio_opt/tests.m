function tests = tests()
%TESTS 工作包w11单元测试: MT链真值模型(标定/漂移映射/锚点) + 干扰场七模板 +
% 执行链(时延/限幅/航向积分) + 红线1白名单 + 四主角因果策略 + oracle参照。
% 方法论与口径沿用 speed_esc_matlab/3.4 的 tests_task34(变量: 前飞速度→上下桨转速比)。
tests = functiontests(localfunctions);
end

%% ---------- MT链真值模型(Opazo 2022) ----------
function test_eta_v_closed_form(tc)
% Opazo Eq.(14)/(30) 闭式核验值: eta_v(1)=1.78077 (Leishman 等推力特例倒数)。
tc.verifyEqual(w11.eta_v_of(1.0),1.78077,'AbsTol',1e-4);
tc.verifyEqual(w11.eta_v_of([0.5 2.0]),w11.eta_v_of([0.5 2.0]),'文件应向量化');
end

function test_mt_power_scale(tc)
% 链功率量级: 15kg X8 每臂(悬停 ~36.8N) ≈ 280-300W, 对齐 Opazo Table 2 (~300W@35N)。
c=w11.config();
P=w11.mt_chain([c.rStar0 1.0],c,1.0);
tc.verifyTrue(all(P>200 & P<400),'链功率应在文献量级(200-400W)');
tc.verifyTrue(all(isfinite(P)),'链功率应有限');
end

function test_r_of_etaT_monotone(tc)
% r(etaT)=Omega_u/Omega_l 严格单调增(转速比-推力比映射可反演的前提)。
c=w11.config();
etaT=linspace(0.35,13.0,800);
r=w11.r_of_etaT(etaT,c,c.cdw,1.0);
tc.verifyTrue(all(diff(r)>0),'r(etaT)应严格单调增');
end

function test_calibration_valley(tc)
% 标定核验: cdw 二分标定使 MT 链(gamma=1)的最优桨比 = rStar0 = 0.89(飞试锚点)。
c=w11.config();
[rStar,~]=w11.mt_chain_valley(1.0,c);
tc.verifyEqual(rStar,c.rStar0,'AbsTol',1e-3);
end

function test_drift_map_monotone(tc)
% 漂移映射: gamma↑(下桨下洗惩罚更强) → r* 单调上移; gamma=1 处增量为0。
c=w11.config();
tc.verifyTrue(all(diff(c.drMapD)>0),'dr(gamma)应单调增');
i1=find(abs(c.drMapG-1)<1e-9,1);
tc.verifyEqual(c.drMapD(i1),0,'AbsTol',1e-12);
end

function test_drift_map_values(tc)
% 漂移量级(接口字典口径): gamma=1.08 → Δr≈+0.023(允许0.015-0.045), 水平因子>1。
c=w11.config();
dr=w11.drift_of(1.08,c);
tc.verifyTrue(dr>0.015 && dr<0.045,'恒定干扰漂移量级应适度');
tc.verifyTrue(w11.drift_of(0.90,c)<0,'gamma<1 应使 r* 下移');
tc.verifyGreaterThan(interp1(c.levMapG,c.levMapP,1.08,'pchip'),1.0,...
    '更强干扰应抬高功率水平');
end

%% ---------- 归一化真值曲线 ----------
function test_curve_anchors_exact(tc)
% 锚点精确成立: P(1)=1(等转速参考), P(rStar0)=case(谷底深度), 对三个case族。
for caseV=[0.97 0.95 0.92]
    c=w11.config('ratioCase',caseV);
    tc.verifyEqual(w11.truth_curve(1.0,c),1.0,'AbsTol',1e-9);
    tc.verifyEqual(w11.truth_curve(c.rStar0,c),caseV,'AbsTol',1e-9);
end
end

function test_curve_valley_unique(tc)
% 全局谷底唯一且恰在 rStar0(涟漪补偿后精确); 若网格上存在其他局部极小,
% 须高出谷底显著裕量(涟漪不制造假谷——算法支撑谷底选择的前提)。
c=w11.config();
rr=linspace(c.lower+1e-4,c.upper-1e-4,4001);
Pv=w11.truth_curve(rr,c);
[Pmin,im]=min(Pv);
tc.verifyLessThan(abs(rr(im)-c.rStar0),2e-3,'谷底应在rStar0');
d=sign(diff(Pv)); loc=find(d(1:end-1)<0 & d(2:end)>0)+1;
others=Pv(loc(loc~=im));
tc.verifyTrue(isempty(others) || min(others)>Pmin+3e-3,...
    '次局部极小应高出谷底≥0.3%(假谷裕量)');
end

function test_curve_shifted_valley_exact(tc)
% 平移语义(与速度包"地速曲线随风平移"同构): P=dlev·truth(r−dx) 的谷底恰在 r0+dx。
c=w11.config();
[dx,dlev]=w11.drift_of(1.08,c);
rr=linspace(c.lower+1e-4,c.upper-1e-4,4001);
Pv=dlev*w11.truth_curve(rr-dx,c);
[Pmin,im]=min(Pv);
tc.verifyLessThan(abs(rr(im)-(c.rStar0+dx)),2e-3,'漂移后谷底应精确平移');
tc.verifyEqual(Pmin,dlev*c.ratioCase,'AbsTol',1e-6,'谷底值应=水平因子×case');
end

function test_curve_grad_finite_difference(tc)
c=w11.config();
for x=[0.80 0.89 0.95 1.05 1.15]
    h=1e-6;
    fd=(w11.truth_curve(x+h,c)-w11.truth_curve(x-h,c))/(2*h);
    tc.verifyEqual(w11.truth_curve_grad(x,c),fd,'AbsTol',1e-4);
end
end

function test_fwd_level_anchors(tc)
% 前飞功率水平因子锚点(速度包同款 Hwang 代理): 1 / 0.913@6.3 / 1.297@20。
c=w11.config();
tc.verifyEqual(w11.fwd_level([0 6.3 20],c),[1 0.913 1.297],'AbsTol',1e-9);
end

%% ---------- 干扰场七模板(类比wind_field) ----------
function test_field_templates_values(tc)
g={'gammaAmp',0.05,'gammaOmega',0.4,'gammaBias',0.08,'turbStd',0,'duration',40,'tailSteps',5};
t=[0 1.37 9.1 22.8];
% const: 恒等于 1+B
c=w11.config(g{:},'gammaKind','const'); scn=w11.scenario('static',c);
[gr,ge]=w11.interfer_field(scn,[0 12.3 40],0);
tc.verifyEqual(gr,1.08*ones(1,3),'AbsTol',1e-12);
tc.verifyEqual(ge,gr);
% sin: 闭式
c=w11.config(g{:},'gammaKind','sin'); scn=w11.scenario('static',c);
[gr,~]=w11.interfer_field(scn,t,0);
tc.verifyEqual(gr,1+0.05*sin(0.4*t)+0.08,'AbsTol',1e-12);
% square: 软边方波——峰值=1+B+A, 有界, 连续
c=w11.config(g{:},'gammaKind','square','squareEdge',4); scn=w11.scenario('static',c);
tp=pi/2/0.4;
[gr,~]=w11.interfer_field(scn,tp,0);
tc.verifyEqual(gr,1.13,'AbsTol',1e-9);
tt=0:0.01:40;
[gr,~]=w11.interfer_field(scn,tt,0);
tc.verifyTrue(max(abs(gr-1.08))<=0.05+1e-9,'方波必须有界');
tc.verifyTrue(max(abs(diff(gr)))<=0.05*0.4*(4/tanh(4))*0.01+1e-12,'软边方波应连续');
% triangle: 峰值=1+B+A, 上升段斜率=A·ω·2/π
c=w11.config(g{:},'gammaKind','triangle'); scn=w11.scenario('static',c);
[gr,~]=w11.interfer_field(scn,tp,0);
tc.verifyEqual(gr,1.13,'AbsTol',1e-9);
t2=[0 tp/2 tp];
[gr,~]=w11.interfer_field(scn,t2,0);
slope=(gr(2)-gr(1))/(t2(2)-t2(1));
tc.verifyEqual(slope,0.05*0.4*2/pi,'AbsTol',1e-9);
end

function test_field_turb_deterministic_stationary(tc)
% turb: 确定性(同种子同序列)+平稳统计(std≈gammaAmp, 均值≈0)。
c=w11.config('gammaKind','turb','gammaAmp',0.05,'gammaBias',0,'turbTheta',0.2,...
    'duration',4000,'tailSteps',5);
s1=w11.scenario('static',c); s2=w11.scenario('static',c);
tc.verifyEqual(s1.intTurbX,s2.intTurbX,'同种子湍动序列应相同');
tc.verifyLessThan(abs(std(s1.intTurbX(10000:end))-0.05),0.02,'OU平稳std应≈gammaAmp');
tc.verifyLessThan(abs(mean(s1.intTurbX(10000:end))),0.02,'OU均值应≈0');
end

function test_field_composite_decomposition(tc)
% composite: turbStd=0 时退化为纯sin。
g={'gammaAmp',0.05,'gammaOmega',0.4,'gammaBias',0.08,'duration',200,'tailSteps',5};
c=w11.config(g{:},'gammaKind','composite','turbStd',0); scn=w11.scenario('static',c);
t=[3 17 99];
[gr,~]=w11.interfer_field(scn,t,0);
tc.verifyEqual(gr,1+0.05*sin(0.4*t)+0.08,'AbsTol',1e-12);
end

function test_field_sector_periodic(tc)
% sector: 与时间无关、周期2π、绕 1+B 幅值=A。
c=w11.config('gammaKind','sector','gammaAmp',0.05,'gammaBias',0.08,...
    'duration',40,'tailSteps',5);
scn=w11.scenario('static',c);
[g1,~]=w11.interfer_field(scn,0,0);
[g2,~]=w11.interfer_field(scn,137.9,0);
tc.verifyEqual(g1,g2,'sector应与时间无关');
[g3,~]=w11.interfer_field(scn,0,2*pi);
tc.verifyEqual(g3,g1,'AbsTol',1e-12,'周期2π');
[gpi,~]=w11.interfer_field(scn,0,pi);
tc.verifyEqual(gpi,1.13,'AbsTol',1e-12,'ψ=π: γ=1+B+A');
end

function test_shift_truth_scenarios(tc)
% 场景调度: jumpUp 在 shiftTime 秒 γ 阶跃; ramp 线性慢漂; offset 纯功率dy。
c=w11.config('shiftTime',120,'jumpUpDg',0.06,'rampStart',60,'rampEnd',180,'rampDg',0.04);
scnU=w11.scenario('jumpUp',c);
[d1,~]=w11.shift_truth(scnU,119.5); [d2,~]=w11.shift_truth(scnU,120.5);
tc.verifyEqual(d1,0); tc.verifyEqual(d2,0.06);
scnR=w11.scenario('ramp',c);
[r1,~]=w11.shift_truth(scnR,60); [r2,~]=w11.shift_truth(scnR,120); [r3,~]=w11.shift_truth(scnR,180);
tc.verifyEqual(r2,0.02,'AbsTol',1e-12,'慢漂中点应为一半');
tc.verifyEqual(r3,0.04,'AbsTol',1e-12);
scnO=w11.scenario('offset',c);
[~,dy]=w11.shift_truth(scnO,120.5);
tc.verifyEqual(dy,0.05);
end

%% ---------- 执行链(时延/限幅/航向积分) ----------
function test_plant_latency_impulse(tc)
% 通信时延+桨比限幅: latency=0.3 时首步只走出释放后子步数的行程; latency=0 时立即生效。
c=w11.config('initialRatio',1.0,'openLoopR',0.8,'slewMax',0.15,...
    'latencySec',0.3,'gammaBias',0,'duration',30,'tailSteps',5,'flightMode','fixed');
[log,~]=w11.run_algorithm('openloop',w11.scenario('static',c),c);
tc.verifyEqual(log.ratio(1),1.0-7*0.15*0.1,'AbsTol',1e-9,...
    'τ=0.3: 子步m=4(t=0.3s)释放, m=4..10共7个子步各走slewMax·dts');
c0=w11.config('initialRatio',1.0,'openLoopR',0.8,'slewMax',0.15,...
    'latencySec',0,'gammaBias',0,'duration',30,'tailSteps',5,'flightMode','fixed');
[log0,~]=w11.run_algorithm('openloop',w11.scenario('static',c0),c0);
tc.verifyEqual(log0.ratio(1),0.85,'AbsTol',1e-9,'τ=0: 首步走满 slewMax·tEval');
tc.verifyTrue(all(log0.slewUsed<=c0.slewMax*c0.tEval+1e-9),'限幅仍须成立');
end

function test_plant_slew_limit_all_policies(tc)
% 全策略 |Δr/步| ≤ slewMax·tEval(物理性核验, 用会大幅移动桨比的sweepcal)。
c=w11.config('seed',11,'duration',300,'gammaBias',0.08);
[log,~]=w11.run_algorithm('sweepcal',w11.scenario('static',c),c);
tc.verifyTrue(all(log.slewUsed<=c.slewMax*c.tEval+1e-9),'桨比变化率超限');
end

function test_plant_noise_kept(tc)
% 测量噪声: 相对噪声 σ=1%(任务2模型原样保留)。
c=w11.config('seed',11);
[log,~]=w11.run_algorithm('openloop',w11.scenario('static',c),c);
rel=(log.powerMeas-log.powerTrue)./log.powerTrue;
tc.verifyEqual(std(rel),0.01,'AbsTol',0.004);
tc.verifyEqual(mean(rel),0,'AbsTol',0.005);
end

function test_plant_truth_identity_and_pmin(tc)
% 无干扰static: 功率真值=fwd_level(V)·truth_curve(r) 精确; Emin列=fwd_level·case;
% 最优桨比列恒=rStar0(文献性质: 不随飞行速度/总拉力变)。
c=w11.config('seed',11,'gammaBias',0,'flightMode','fixed','openLoopR',1.0);
[log,~]=w11.run_algorithm('openloop',w11.scenario('static',c),c);
Pexp=w11.fwd_level(c.fwdSpeed,c)*w11.truth_curve(1.0,c);
tc.verifyEqual(log.powerTrue,Pexp*ones(height(log),1),'AbsTol',1e-9);
tc.verifyEqual(log.minPowerTrue,...
    w11.fwd_level(c.fwdSpeed,c)*c.ratioCase*ones(height(log),1),'AbsTol',1e-9);
tc.verifyEqual(log.optimumTrue,c.rStar0*ones(height(log),1),'AbsTol',1e-9);
end

function test_plant_gamma_true_column(tc)
% 恒定干扰: gammaTrue 列=1+B; driftDx 列=Δr(gamma)。
c=w11.config('seed',11,'gammaKind','const','gammaBias',0.08,'duration',30,'tailSteps',5);
[log,~]=w11.run_algorithm('openloop',w11.scenario('static',c),c);
tc.verifyEqual(log.gammaTrue,1.08*ones(height(log),1),'AbsTol',1e-9);
tc.verifyEqual(log.driftDx,w11.drift_of(1.08,c)*ones(height(log),1),'AbsTol',1e-9);
end

function test_heading_integration(tc)
% 航向积分回归: fixed 模式 ψ'=V/R 与指令无关(转速通道与航迹解耦)。
c=w11.config('seed',11,'gammaBias',0,'flightMode','fixed','duration',40,'tailSteps',5);
[log,~]=w11.run_algorithm('openloop',w11.scenario('static',c),c);
n=height(log);
psiExp=rad2deg(cumsum(ones(n,1)*c.fwdSpeed/c.turnRadius)*c.tEval);
tc.verifyEqual(max(abs(mod(log.headingDeg-psiExp+180,360)-180)),0,'AbsTol',1e-6);
end

function test_flight_modes_level(tc)
% 三种飞行模式行: 悬停/前飞/变速 的功率水平因子按 Hwang 代理进入对象。
cH=w11.config('seed',11,'gammaBias',0,'flightMode','hover','duration',30,'tailSteps',5);
[logH,~]=w11.run_algorithm('openloop',w11.scenario('static',cH),cH);
tc.verifyEqual(mean(logH.powerTrue),w11.truth_curve(1.0,cH),'AbsTol',1e-9,...
    '悬停水平因子=1');
cV=w11.config('seed',11,'gammaBias',0,'flightMode','vary','duration',200,'tailSteps',20);
[logV,~]=w11.run_algorithm('openloop',w11.scenario('static',cV),cV);
tc.verifyGreaterThan(std(logV.powerTrue),1e-4,'变速行功率水平应随V波动');
tc.verifyLessThan(std(logV.optimumTrue),1e-12,'文献性质: 最优桨比不随总拉力/速度变化');
end

function test_moe_identity(tc)
c=w11.config('seed',11);
[log,~]=w11.run_algorithm('openloop',w11.scenario('static',c),c);
m=w11.mop_moe(log,c);
tc.verifyEqual(m.MOE_energy,1/(1+m.energyExcessPercent/100),'AbsTol',1e-9);
tc.verifyEqual(m.MOE.overall,m.MOE_energy,'AbsTol',1e-12,'overall=纯能耗口径');
end

%% ---------- 红线1: 白名单与因果结构 ----------
function test_ctrl_view_whitelist(tc)
c0=w11.config();
p=w11.ctrl_view(c0);
drop={'rStar0','ratioCase','chainP1Ref','chainDepth','kappa','rippleA1','rippleL1',...
    'rippleF1','rippleA2','rippleL2','shapeAlpha','shapeBeta','rFine','PFine',...
    'rotorR','diskA','rho','cd','kInd','aT','cdw','etaGrid','rGrid',...
    'drMapG','drMapD','levMapG','levMapP','fwdCoef','noiseSigma','gammaAmp','gammaBias'};
for k=1:numel(drop)
    tc.verifyFalse(isfield(p,drop{k}),'白名单不应包含真值字段');
end
keep={'lower','upper','initialRatio','tEval','turnRadius','latencySec','slewMax',...
    'openLoopR','swLo','swHi','flightMode','fwdSpeed'};
for k=1:numel(keep)
    tc.verifyTrue(isfield(p,keep{k}),'白名单应保留控制器合法知识');
end
end

function test_budget_all_policies(tc)
policies={'openloop','est','interfinfer','hybrid','sweepcal','rl','purerl','known'};
for name=policies
    c=w11.config('seed',11,'duration',400);
    [log,~]=w11.run_algorithm(name{1},w11.scenario('static',c),c);
    tc.verifyEqual(height(log),c.duration,sprintf('%s预算未走满',name{1}));
    tc.verifyTrue(all(isfinite(log.powerMeas)),sprintf('%s出现非有限测量',name{1}));
    tc.verifyTrue(all(log.ratio>=c.lower-1e-9 & log.ratio<=c.upper+1e-9),...
        sprintf('%s实际桨比越界',name{1}));
end
end

%% ---------- oracle 参照(评价侧) ----------
function test_known_zero_excess(tc)
% known(已知γ场+映射): 三种干扰档都应几乎零超额(信息上界)。
for iw={'zero','const'}
    switch iw{1}
        case 'zero', gcfg={'gammaKind','const','gammaBias',0};
        otherwise,   gcfg={'gammaKind','const','gammaBias',0.08};
    end
    c=w11.config('seed',3,'duration',400,gcfg{:});
    [log,~]=w11.run_algorithm('known',w11.scenario('static',c),c);
    m=w11.mop_moe(log,c);
    tc.verifyLessThan(m.energyExcessPercent,0.3,sprintf('known(%s)应≈零超额',iw{1}));
end
end

function test_known_information_value(tc)
% 恒定干扰下 known 与 openloop 的差=信息价值(应接近开环全额损失)。
c=w11.config('seed',3,'gammaKind','const','gammaBias',0.08,'duration',400);
scn=w11.scenario('static',c);
[logK,~]=w11.run_algorithm('known',scn,c);
[logO,~]=w11.run_algorithm('openloop',scn,c);
eK=w11.mop_moe(logK,c).energyExcessPercent;
eO=w11.mop_moe(logO,c).energyExcessPercent;
tc.verifyGreaterThan(eO-eK,3.0,'恒定干扰的信息价值应>3%');
end

function test_interfinfer_const(tc)
% interfinfer(已知曲线oracle): 恒定干扰应反演出 δ̂≈Δr(1.08)。
% 容差口径: 谷底附近功率对δ不敏感(二阶)+涟漪模型失配, 反演偏差~0.01-0.02 是
% 真实可达精度(能耗对其不敏感, 见excess门槛); 干扰况判定允许在噪声下抖动。
c=w11.config('seed',3,'gammaKind','const','gammaBias',0.08,'duration',600);
scn=w11.scenario('static',c);
[log,info]=w11.run_algorithm('interfinfer',scn,c);
m=w11.mop_moe(log,c);
kF=find(isfinite(info.thEst(1,:)),1,'last');
tc.verifyLessThan(abs(info.thEst(1,kF)-w11.drift_of(1.08,c)),0.025,...
    '均匀漂移分量反演误差应<0.025');
tc.verifyLessThan(m.energyExcessPercent,2.5,'interfinfer超额应<2.5%');
tc.verifyTrue(any(ismember(string(info.regime),["恒定干扰","漂移干扰"])),...
    '干扰况判定应已收敛');
end

function test_est_completes(tc)
% est(已知曲线EKF oracle): 预算走满, θ̂ 有界, 超额有界。
c=w11.config('seed',3,'gammaKind','const','gammaBias',0.08,'duration',400);
[log,info]=w11.run_algorithm('est',w11.scenario('static',c),c);
m=w11.mop_moe(log,c);
tc.verifyEqual(height(log),c.duration);
tc.verifyTrue(all(isfinite(info.thEst)),'θ̂ 应有限');
tc.verifyTrue(all(abs(info.thEst)<=0.2),'θ̂ 应有界');
tc.verifyLessThan(m.energyExcessPercent,2.5,'est超额应有界');
end

%% ---------- 四主角(sweepcal/rl/purerl/hybrid) ----------
function test_sweepcal_const(tc)
% 恒定干扰: 标定+精化应找回 r*=0.913(±0.03) 并显著优于开环。
c=w11.config('seed',3,'gammaKind','const','gammaBias',0.08,'duration',800);
scn=w11.scenario('static',c);
[log,info]=w11.run_algorithm('sweepcal',scn,c);
m=w11.mop_moe(log,c);
[logO,~]=w11.run_algorithm('openloop',scn,c);
mO=w11.mop_moe(logO,c);
tc.verifyLessThan(abs(info.rStar-(c.rStar0+w11.drift_of(1.08,c))),0.03,...
    'r̂*辨识误差应<0.03');
tc.verifyLessThan(m.energyExcessPercent,4.5,'能耗超额应<4.5%');
tc.verifyLessThan(m.energyExcessPercent,mO.energyExcessPercent,'应优于开环基线');
tc.verifyEqual(info.calibSteps,c.swSteps,'标定步数应=swSteps');
end

function test_sweepcal_zero_regret(tc)
% 无干扰: 标定应直接找到谷底(0.89)并恒飞; 尾段稳态接近最优。
c=w11.config('seed',3,'gammaKind','const','gammaBias',0,'duration',600);
scn=w11.scenario('static',c);
[log,info]=w11.run_algorithm('sweepcal',scn,c);
m=w11.mop_moe(log,c);
tc.verifyLessThan(m.regretPercent,3.5,'零干扰尾段应接近最优');
tc.verifyLessThan(abs(info.rStar-c.rStar0),0.03,'零干扰r̂*应≈0.89');
end

function test_sweepcal_drift_beats_openloop(tc)
% 漂移干扰(composite): 重拟合链应跟踪漂移, 优于不补偿的开环(提示词指定必查)。
c=w11.config('seed',3,'gammaKind','composite','gammaAmp',0.04,'turbStd',0.015,...
    'duration',800);
scn=w11.scenario('static',c);
[logS,~]=w11.run_algorithm('sweepcal',scn,c);
[logO,~]=w11.run_algorithm('openloop',scn,c);
mS=w11.mop_moe(logS,c); mO=w11.mop_moe(logO,c);
tc.verifyLessThan(mS.energyExcessPercent,mO.energyExcessPercent,...
    '漂移干扰下sweepcal应优于开环');
end

function test_hybrid_const_beats_openloop(tc)
% hybrid(冻结曲线+探针+低频维护): 恒定干扰下成立且优于开环。
c=w11.config('seed',3,'gammaKind','const','gammaBias',0.08,'duration',800);
scn=w11.scenario('static',c);
[log,info]=w11.run_algorithm('hybrid',scn,c);
m=w11.mop_moe(log,c);
[logO,~]=w11.run_algorithm('openloop',scn,c);
mO=w11.mop_moe(logO,c);
tc.verifyLessThan(m.energyExcessPercent,mO.energyExcessPercent,'应优于开环');
tc.verifyLessThan(m.energyExcessPercent,5.0,'恒定干扰超额应<5%');
tc.verifyEqual(info.calibSteps,c.swSteps,'标定步数应=swSteps');
end

function test_hybrid_phase_b_structure(tc)
% 结构核验: 标定步总数=swSteps; Phase B 稳定后不再出现 calib; 标签集合合法。
c=w11.config('seed',3,'gammaKind','const','gammaBias',0.08,'duration',600);
[log,~]=w11.run_algorithm('hybrid',w11.scenario('static',c),c);
tags=string(log.tag);
tc.verifyEqual(sum(tags=='calib'),c.swSteps,'标定步总数应=swSteps');
late=tags(c.swSteps+6:end);
tc.verifyEqual(sum(late=='calib'),0,'Phase B稳定后不应再出现标定步');
tc.verifyTrue(all(ismember(unique(setdiff(tags,{'calib'})),...
    {'infer','probe','hold','settle','refine'})),'其余标签应合法');
tc.verifyGreaterThan(sum(tags=='probe'),10,'探针应按周期存在');
end

function test_rl_completes_and_anneals(tc)
% rl(仿真器预训练+微调): 预算走满/有限/σ退火到位。
c=w11.config('seed',3,'duration',600);
scn=w11.scenario('static',c);
[log,info]=w11.run_algorithm('rl',scn,c);
m=w11.mop_moe(log,c);
tc.verifyEqual(height(log),c.duration,'rl预算未走满');
tc.verifyTrue(all(isfinite(log.powerMeas)),'rl出现非有限测量');
tc.verifyLessThan(info.sigma,c.rlSigma+1e-9,'σ应退火不增');
tc.verifyTrue(isfinite(m.MOE_energy),'rl的MOE应有限');
end

function test_purerl_structural_model_free(tc)
% purerl 结构性无模型: 不输出拟合曲线/显式谷底辨识。
c=w11.config('seed',3,'duration',300);
scn=w11.scenario('static',c);
[~,info]=w11.run_algorithm('purerl',scn,c);
tc.verifyFalse(isfield(info,'coefs'),'纯奖励RL不应输出拟合曲线');
tc.verifyFalse(isfield(info,'rStar'),'纯奖励RL不应输出显式谷底辨识');
tc.verifyTrue(isfield(info,'muB'),'应输出表格策略μ');
end

function test_purerl_const_beats_openloop(tc)
c=w11.config('seed',3,'gammaKind','const','gammaBias',0.08,'duration',800);
scn=w11.scenario('static',c);
[log,~]=w11.run_algorithm('purerl',scn,c);
m=w11.mop_moe(log,c);
[logO,~]=w11.run_algorithm('openloop',scn,c);
mO=w11.mop_moe(logO,c);
tc.verifyLessThan(m.energyExcessPercent,mO.energyExcessPercent,'纯奖励RL应优于开环');
tc.verifyLessThan(m.energyExcessPercent,4.5,'800步时应收敛到<4.5%');
end

function test_purerl_drift_beats_openloop(tc)
c=w11.config('seed',3,'gammaKind','composite','gammaAmp',0.04,'turbStd',0.015,...
    'duration',800);
scn=w11.scenario('static',c);
[log,~]=w11.run_algorithm('purerl',scn,c);
[logO,~]=w11.run_algorithm('openloop',scn,c);
m=w11.mop_moe(log,c); mO=w11.mop_moe(logO,c);
tc.verifyLessThan(m.energyExcessPercent,mO.energyExcessPercent,'漂移下应优于开环');
end

function test_purerl_no_sweep(tc)
% purerl 免扫频: 前150步指令不应出现全比域扫频(远离初始桨比)。
c=w11.config('seed',3,'duration',600);
[log,~]=w11.run_algorithm('purerl',w11.scenario('static',c),c);
early=log.ratioCmd(1:150);
tc.verifyLessThan(max(early),c.initialRatio+c.plSigma0+0.05,'不应出现高比段扫频');
tc.verifyGreaterThan(min(early),c.initialRatio-c.plSigma0-0.05,'不应出现低比段扫频');
end

function test_four_heroes_all_kinds_complete(tc)
% 四主角在七种干扰模板下都能完整跑完(鲁棒性)。
kinds={'const','sin','square','triangle','turb','composite','sector'};
heroes={'sweepcal','rl','purerl','hybrid'};
for kk=1:numel(kinds)
    for hh=1:numel(heroes)
        c=w11.config('seed',11,'duration',250,'tailSteps',5,'gammaKind',kinds{kk},...
            'gammaAmp',0.04,'gammaBias',0.03);
        [log,~]=w11.run_algorithm(heroes{hh},w11.scenario('static',c),c);
        tc.verifyEqual(height(log),250,sprintf('%s×%s预算未走满',kinds{kk},heroes{hh}));
        tc.verifyTrue(all(isfinite(log.powerTrue)),sprintf('%s×%s功率非有限',...
            kinds{kk},heroes{hh}));
    end
end
end

function test_oracles_all_kinds_complete(tc)
% openloop/known/est/interfinfer 在七种模板下预算走满。
kinds={'const','sin','square','triangle','turb','composite','sector'};
pol={'openloop','known','est','interfinfer'};
for kk=1:numel(kinds)
    for pp=1:numel(pol)
        c=w11.config('seed',11,'duration',250,'tailSteps',5,'gammaKind',kinds{kk},...
            'gammaAmp',0.04,'gammaBias',0.03);
        [log,~]=w11.run_algorithm(pol{pp},w11.scenario('static',c),c);
        tc.verifyEqual(height(log),250,sprintf('%s×%s预算未走满',kinds{kk},pol{pp}));
    end
end
end

function test_openloop_zero_baseline_excess(tc)
% 无干扰下开环(r=1)的固有超额 ≈ 1/case−1 ≈ 5.3%(飞试节能口径的物理来源)。
c=w11.config('seed',11,'gammaBias',0,'duration',300,'tailSteps',30);
[log,~]=w11.run_algorithm('openloop',w11.scenario('static',c),c);
m=w11.mop_moe(log,c);
tc.verifyEqual(m.energyExcessPercent,100*(1/c.ratioCase-1),'AbsTol',0.5);
end
