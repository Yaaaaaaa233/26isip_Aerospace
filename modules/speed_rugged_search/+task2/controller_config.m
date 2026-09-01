function p = controller_config(c)
%CONTROLLER_CONFIG Search-side whitelist: no curve truth, no noise, no seed.
% 搜索器可见：边界、预算、扫描/滤波/多起点/精调/ESC 参数与初始速度；
% 崎岖项参数、噪声、种子、能耗开关一律不给(黑箱口径)。
keys={'lower','upper','tol','maxSearchEval','tEval','scanN','filterMethod',...
    'filterW','K','minSep','refineSpan','repeats','initialSpeed',...
    'escA','escOmega','escGain','escLpOmega','escWindow','gridResolution'};
p=struct(); for k=1:numel(keys), p.(keys{k})=c.(keys{k}); end
end
