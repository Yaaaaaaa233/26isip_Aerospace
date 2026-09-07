function p = ctrl_view(c)
%CTRL_VIEW 曲线未知口径的控制器白名单(红线1): 剔除全部曲线/最优点/对象真值字段。
% 任务3.3设定: 控制器只知道"手动调速度→仪表盘给功率", 此外只有速度边界、初始速度、
% 采样时间、轨迹半径R与执行链参数(时延/限幅)。曲线形状f、空速最优点u*(=optimum0)、
% 标定锚点、噪声水平等对象真值一律不下发。
% 已知曲线的对照策略(windinfer/est/known)不走本白名单, 由 run_algorithm 单独下发全量
% config 并在面板/文档中标注为 oracle 参照。
drop = {'curveCoef','curveCase','pHover','p20', ...     % 曲线标定
    'rippleA1','rippleL1','rippleF1','rippleA2','rippleL2', ...  % 涟漪形状
    'optimum0', ...                                     % 空速最优点(核心未知量)
    'noiseSigma','impulse','impulseRate','impulseSize', ...      % 测量真值
    'energyAccounting','eps','tailSteps','T','wiSweepMin','wiEwma'};
% (2026-09-07精简后 config 已不含任务1搜索器参数 tol/maxSearchEval/gridResolution)
p = c;
for k = 1:numel(drop)
    if isfield(p, drop{k}), p = rmfield(p, drop{k}); end
end
end
