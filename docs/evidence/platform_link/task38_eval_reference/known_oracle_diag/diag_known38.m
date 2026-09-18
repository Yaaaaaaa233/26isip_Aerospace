function diag_known38
%DIAG_KNOWN38 (2026-09-11) 为什么平台 known(oracle) 只有 0.917 而本地是 0.999?
% 对照实验: A=现行 known_platform_run(死推航向+朴素转向 v*=u*+wt)
%           B=真航向+完整闭式解   v*=q+sqrt(q^2+u*^2-|w|^2)  (oracle 评价侧允许真值)
% 各 3600s, 逐秒落盘, 分解 excess。
stage='C:\Users\WJQ\AppData\Local\Temp\t38_exp';
addpath(stage);
R='D:\王健祺\大学本科文件资料\大二暑\航空器\控制寻优\26isip_Aerospace';
addpath(fullfile(R,'models','plane')); addpath(fullfile(R,'harness'));
clear functions; rehash; rehash toolboxcache;
W=3600;
c=w36.config('backend','platform','evalSeconds',W,'seed',11, ...
    'windKind','composite','windBias',2.5,'windAmp',0,'windAmpY',0,'turbStd',0.3);
scn=w36.scenario('static',c);
plant=w36.make_platform_plant(scn,c);
tf=plant.truth();

% ---------- A: 现行 known_platform_run(原样) ----------
[L,Ainfo]=w36.run_algorithm('known',scn,c);
mA=w36.mop_moe(L,c);
% ---------- B: 真航向 + 完整闭式解 ----------
qs=w36.settled_q(plant,c,W);
t0=plant.count(); k=0;
while plant.count()<W
    k=k+1;
    t=plant.count();
    pt=plant.phase();                       % 真实相位(评价侧, oracle 允许)
    [Wx,Wy]=plant.windAt(t,pt);
    q= Wx*cos(pt)+Wy*sin(pt);
    w2=Wx^2+Wy^2;
    v=q+sqrt(max(0,q^2+tf.vStarAir^2-w2));
    v=min(max(v,c.lower+0.3),c.upper-0.3);
    qs(v,'known');
end
while plant.count()<W
    plant.q(v,'hold'); plant.amendEstimate(v);
end
LB=plant.table();
mB=w36.mop_moe(LB,c);

% ---------- 汇总 ----------
vA=mean(L.powerTrue); eA=100*(vA-mean(L.minPowerTrue))/mean(L.minPowerTrue);
vB=mean(LB.powerTrue); eB=100*(vB-mean(LB.minPowerTrue))/mean(LB.minPowerTrue);
fprintf('KNOWN_A naive/dead-reckon : MOE=%.4f excess=%.2f%%\n', 1/(1+eA/100), eA);
fprintf('KNOWN_B true-phase/closed : MOE=%.4f excess=%.2f%%\n', 1/(1+eB/100), eB);
% 死推航向 vs 真实相位 的漂移(A臂重放: psi_dead=cumsum(v_cmd/R))
vd=L.speedCmd(:); nA=numel(vd);
psiDead=cumsum(vd/c.turnRadius*c.tEval);
truePh=L.headingDeg(:)*pi/180;
dphi=wrapToPi(psiDead(2:end)'-truePh(2:end));
fprintf('PHI drift end=%.2f rad (%.2f rev) | mean|dphi|=%.2f rad\n', ...
    dphi(end), dphi(end)/(2*pi), mean(abs(dphi)));
% A臂空气速偏差分布(相对 u*)
ua=L.airspeed(:); B2=tailidx(nA,600);
fprintf('AIRSPD A: mean_err_vs_ustar=%+.3f m/s |err|>1m/s frac=%.1f%%\n', ...
    mean(ua)-tf.vStarAir, mean(abs(ua-tf.vStarAir)>1));
writetable(L(2:end,:),fullfile(stage,'diag_knownA_persec.csv'));
writetable(LB(2:end,:),fullfile(stage,'diag_knownB_persec.csv'));
disp('DIAG38_DONE');
    function i=tailidx(n,m), i=max(1,n-m+1); end
end
