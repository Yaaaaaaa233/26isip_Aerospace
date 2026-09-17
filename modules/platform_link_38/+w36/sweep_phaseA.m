function preCal = sweep_phaseA(warmPlant, p, nW)
%SWEEP_PHASEA 任务3.7: 独立试飞架次上的全速域标定(不计评测预算/MOE)。
% 与 sweepcal/hybrid 的 Phase A、rl 的 Stage A 完全同构(双向扫+联合辨识),
% 但跑在独立的 warmPlant 上——标定能耗记在试飞架次, 评估窗从"已标定好"状态
% 直接开始(对标 purerl 预训练拆分的预算口径, 红线3边界: 表述时注明试飞预算)。
% nW=试飞plant的秒数预算(就位委托制下每探针可能耗时数秒, 平台后端应放宽)。
% 因果口径(红线1): 只用带噪功率+自身指令(航向死推 ψ̂'按经历秒数直乘)+tEval;
% p 为 ctrl_view 白名单。返回 preCal 结构体, 供三个算法的 <alg>_run(…,preCal)。
qs=w36.settled_q(warmPlant,p,1e9);
nUp=ceil(0.6*p.swSteps);
vSw=[linspace(p.swLo,p.swHi,nUp), linspace(p.swHi,p.swLo,p.swSteps-nUp)];
calPsi=zeros(1,p.swSteps); calV=zeros(1,p.swSteps); calP=zeros(1,p.swSteps);
psiUnw=0; kStep=0;
while kStep<p.swSteps && warmPlant.count()<nW
    kStep=kStep+1;
    v=vSw(kStep);
    c0=warmPlant.count();
    Pm=qs(v,'calib');
    if ~isfinite(Pm), kStep=kStep-1; break; end
    psiUnw=psiUnw+(warmPlant.count()-c0)*v/p.turnRadius*p.tEval;
    calPsi(kStep)=psiUnw; calV(kStep)=v; calP(kStep)=Pm;
end
assert(kStep>=30,'w36:SweepPhaseA','标定试飞预算不足(只采到%d点), 请加大试飞时长。',kStep);
[coefs,wSm,fitRms,uLo,uHi,uKept]=w36.fit_curve_wind(calPsi(1:kStep),...
    calV(1:kStep),calP(1:kStep),p);
uStar=w36.curve_argmin(coefs,uLo,uHi,p,uKept);
preCal=struct('calPsi',calPsi,'calV',calV,'calP',calP,'calibSteps',kStep,...
    'coefs',coefs,'wSm',wSm,'fitRms',fitRms,'uLo',uLo,'uHi',uHi,...
    'uKept',uKept,'uKeptCal',uKept,'uStar',uStar,'uArg',uStar);
end
