function p = controller_config(c)
%CONTROLLER_CONFIG Search-side whitelist: no curve, no shift truth, no noise.
% 搜索器可见的只有边界、预算与算法自身参数；场景真值(曲线族、平移、噪声、
% 能耗开关)一律不给，保证黑箱口径。
keys={'lower','upper','tol','maxSearchEval','tEval','probeDelta','probePeriod',...
    'slopeThresh','slopeRelease','bracketSpan0','bracketGrow','bracketRetry',...
    'escA','escOmega','escGain','escLpOmega','escWindow','escInitial','gridResolution',...
    'initialSpeed'};
p=struct(); for k=1:numel(keys), p.(keys{k})=c.(keys{k}); end
end
