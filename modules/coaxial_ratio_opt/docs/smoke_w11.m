%SMOKE_W11 模型层冒烟: 标定数值 + 真值曲线锚点 + 矩阵运行
c=w11.config();
fprintf('== 标定结果 ==\n');
fprintf('cdw=%.5f  chainDepth=%.4f  kappa=%.3f\n',c.cdw,c.chainDepth,c.kappa);
fprintf('shapeAlpha=%.4f shapeBeta=%.4f\n',c.shapeAlpha,c.shapeBeta);
fprintf('dr(1.08)=%+.4f  Plev(1.08)=%.4f  dr(0.90)=%+.4f\n',...
    w11.drift_of(1.08,c), interp1(c.levMapG,c.levMapP,1.08,'pchip'), w11.drift_of(0.90,c));
fprintf('== 真值曲线锚点 ==\n');
fprintf('P(1)=%.6f (期望1)  P(0.89)=%.6f (期望%.2f)\n',w11.truth_curve(1.0,c),w11.truth_curve(c.rStar0,c),c.ratioCase);
rr=linspace(0.75,1.25,2001); Pv=w11.truth_curve(rr,c);
[Pmin,im]=min(Pv);
fprintf('fine argmin=%.4f (期望0.89)  Pmin=%.6f\n',rr(im),Pmin);
fprintf('P(0.75)=%.4f  P(1.25)=%.4f\n',w11.truth_curve(0.75,c),w11.truth_curve(1.25,c));
fprintf('== 短程运行 ==\n');
cfg=w11.config('seed',3,'duration',300,'tailSteps',30,'gammaKind','const','gammaBias',0.08);
scn=w11.scenario('static',cfg);
tic;
[log,info]=w11.run_algorithm('sweepcal',scn,cfg);
t1=toc;
m=w11.mop_moe(log,cfg);
fprintf('sweepcal(300步, %0.1fs): 超额=%.2f%%  r̂*=%.4f (真值 %.4f)  calib=%d\n',...
    t1,m.energyExcessPercent,info.rStar,cfg.rStar0+w11.drift_of(1.08,cfg),info.calibSteps);
[logO,~]=w11.run_algorithm('openloop',scn,cfg);
mO=w11.mop_moe(logO,cfg);
fprintf('openloop: 超额=%.2f%% (期望≈%.2f%%)\n',mO.energyExcessPercent,100*(1/cfg.ratioCase-1));
[logK,~]=w11.run_algorithm('known',scn,cfg);
mK=w11.mop_moe(logK,cfg);
fprintf('known: 超额=%.3f%%\n',mK.energyExcessPercent);
cfg2=w11.config('seed',3,'duration',600,'tailSteps',60,'gammaKind','composite','gammaAmp',0.04);
scn2=w11.scenario('static',cfg2);
tic;
[logP,~]=w11.run_algorithm('purerl',scn2,cfg2);
t2=toc;
mP=w11.mop_moe(logP,cfg2);
[logO2,~]=w11.run_algorithm('openloop',scn2,cfg2);
mO2=w11.mop_moe(logO2,cfg2);
fprintf('purerl(600步, %0.1fs): 超额=%.2f%% vs openloop=%.2f%%\n',t2,mP.energyExcessPercent,mO2.energyExcessPercent);
fprintf('SMOKE DONE\n');
