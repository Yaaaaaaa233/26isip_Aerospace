function M = load_platform_pretrain(c)
%LOAD_PLATFORM_PRETRAIN 平台后端purerl缓存模型加载(2026-09-09 数据源一致性)。
% 仅当当前风场配置与模型训练配置完全一致时命中(复合风默认参数: B=2.5,A=C=0,
% σ=0.3), 返回模型结构体 muB/bBase/sigma/warm元信息; 其余风场配置返回[],
% 由 run_algorithm 回退为平台plant在线预训练(慢但正确)。
% 模型由 make_platform_pretrain 一次性离线生成: static圆周 + 复合风默认参数
% (试飞湍流实现 seed+17), 预训练全程在平台plant上进行——与评估同一数据源。
M=[];
here=fileparts(fileparts(mfilename('fullpath')));
cands={fullfile(here,'pretrained','pretrain_platform_composite.mat'), ...
       fullfile(tempdir,'t36_pretrain_platform_composite.mat')};   % ASCII暂存通道(绕中文路径解析)
f='';
for k=1:numel(cands)
    if isfile(cands{k}), f=cands{k}; break; end
end
if isempty(f), return; end
S=load(f,'model','meta');
w=S.meta.wind;
cur=[c.windKind,c.windAmp,c.windOmega,c.windBias,c.windBiasY,c.windAmpY, ...
     c.windOmegaY,c.turbStd,c.turbTheta,c.windDirDeg];
tr =[w.windKind,w.windAmp,w.windOmega,w.windBias,w.windBiasY,w.windAmpY, ...
     w.windOmegaY,w.turbStd,w.turbTheta,w.windDirDeg];
if isequal(cur,tr)
    M=S.model;
end
end
