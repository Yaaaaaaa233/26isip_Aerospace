function p = ctrl_view(c)
%CTRL_VIEW 桨比未知口径的控制器白名单(红线1): 剔除全部曲线/最优点/干扰真值字段。
% 控制器只知道"手动调桨比→仪表盘给功率", 此外只有桨比边界、初始桨比、采样时间、
% 转迹半径R与执行链参数(时延/限幅)。真值最优 rStar0、case 深度、涟漪形状、
% MT链参数、γ 场参数、噪声水平等对象真值一律不下发。
% 已知曲线/干扰的对照策略(interfinfer/est/known)不走本白名单, 由 run_algorithm
% 单独下发全量 config 并在面板/文档中标注为 oracle 参照。
drop = {'rStar0','ratioCase','chainP1Ref','chainDepth','kappa', ...   % 真值最优/深度
    'rippleA1','rippleL1','rippleF1','rippleA2','rippleL2', ...       % 涟漪形状
    'shapeAlpha','shapeBeta','rFine','PFine', ...                     % 真值曲线
    'rotorR','diskA','nBlades','chord','rho','cd','kInd','aT','clalpha', ...  % MT链
    'sigCd8','c2','totThrust','cdw','etaGrid','rGrid', ...
    'drMapG','drMapD','levMapG','levMapP','fwdCoef', ...              % 漂移/水平映射
    'gammaKind','gammaAmp','gammaOmega','gammaBias', ...              % γ 干扰场真值
    'gammaAmpY','gammaOmegaY','gammaBiasY','gammaDirDeg', ...
    'squareEdge','turbStd','turbTheta', ...
    'noiseSigma','impulse','impulseRate','impulseSize', ...           % 测量真值
    'energyAccounting','eps','tailSteps','ifSweepMin','ifEwma'};
p = c;
for k = 1:numel(drop)
    if isfield(p, drop{k}), p = rmfield(p, drop{k}); end
end
end
