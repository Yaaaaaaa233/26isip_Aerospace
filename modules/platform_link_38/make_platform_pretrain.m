%MAKE_PLATFORM_PRETRAIN 平台后端purerl预训练模型一次性离线生成(2026-09-09)。
% 场景: static圆周 + 复合风默认参数(B=2.5, A=C=0, σ=0.3, θ=0.2) + 平台plant
% (与评估同一数据源——数据源一致性修复的配套)。试飞湍流实现 seed+17, 不占
% 评测预算。产物: pretrained/pretrain_platform_composite.mat
%   model: muB/bBase/sigma + warm元信息   meta: 训练配置与日期
% 用法: MATLAB 命令行 cd 到本目录后运行  make_platform_pretrain
%       或从 ASCII 暂存目录运行并显式传入模块目录: make_platform_pretrain('<模块目录>')
% 耗时约30-60分钟(平台plant逐秒推进, 每秒=100个0.01s内层步)。
function make_platform_pretrain(outDir)
if nargin<1 || isempty(outDir)
    outDir=fileparts(mfilename('fullpath'));   % 常规: 本模块所在目录
end
here=fileparts(mfilename('fullpath'));
addpath(here); clear functions; rehash;
% 仓库根探测(2026-09-09): 从ASCII暂存目录运行时, make_platform_plant 的相对
% 候选够不到仓库——这里依据模块目录(outDir)显式定位并挂载平台包。
repoCands={fullfile(outDir,'..','..','26isip_Aerospace'), ...
           fullfile(outDir,'..','..','..','26isip_Aerospace'), ...
           outDir};
repoRoot='';
for i=1:numel(repoCands)
    if isfile(fullfile(repoCands{i},'models','plane','+plane','config.m'))
        repoRoot=repoCands{i}; break;
    end
end
assert(~isempty(repoRoot),'未找到26isip_Aerospace仓库根(需含 models/plane/+plane/config.m)。');
addpath(fullfile(repoRoot,'models','plane'));   % 平台 P2 对象(+plane)
addpath(fullfile(repoRoot,'harness'));          % 平台评价真值(+harness)
fprintf('[pretrain] repoRoot=%s\n', repoRoot);
c=w36.config('backend','platform','windKind','composite','windBias',2.5,'seed',1);
c.plWarmMax=8000;   % 就位委托制下每次探测消耗数秒, 按秒计的暖机上限相应放大(平台预训练专用, 本地不变)
fprintf('[pretrain] 场景=static圆周+复合风默认(B=%.1f,A=%.1f,C=%.1f,σ=%.1f) seed暖机=%d\n', ...
    c.windBias,c.windAmp,c.windBiasY,c.turbStd,c.seed+17);
scnE=w36.scenario('static',c);
plantE=w36.make_platform_plant(scnE,c);            % 评估plant(占位, n=1)
pCtrl=w36.ctrl_view(c);
cW=c; cW.seed=c.seed+17;
scnW=w36.scenario('static',cW);
plantW=w36.make_platform_plant(scnW,cW);           % 试飞plant(平台, 同数据源)
info=w36.pure_rl_pre_run(plantE,pCtrl,1,'off',plantW);
model=struct('muB',info.muPre,'bBase',info.bBasePre,'sigma',info.sigmaPre, ...
    'warmSteps',info.warmupSteps,'warmBlocks',info.warmBlocks, ...
    'blkMeanP',info.warmBlockP,'blkMeanDB',info.warmBlockDB);
wind=struct('windKind',c.windKind,'windAmp',c.windAmp,'windOmega',c.windOmega, ...
    'windBias',c.windBias,'windBiasY',c.windBiasY,'windAmpY',c.windAmpY, ...
    'windOmegaY',c.windOmegaY,'turbStd',c.turbStd,'turbTheta',c.turbTheta, ...
    'windDirDeg',c.windDirDeg);
meta=struct('backend','platform','scenario','static+circle','wind',wind, ...
    'warmSteps',info.warmupSteps,'warmConverged',info.warmConverged, ...
    'warmBlocks',info.warmBlocks,'seedWarm',c.seed+17,'date',datestr(now,31));
if ~exist(fullfile(outDir,'pretrained'),'dir'), mkdir(fullfile(outDir,'pretrained')); end
save(fullfile(outDir,'pretrained','pretrain_platform_composite.mat'),'model','meta','-v7');
copyfile(fullfile(outDir,'pretrained','pretrain_platform_composite.mat'), ...
         fullfile(tempdir,'t36_pretrain_platform_composite.mat'));   % ASCII通道: 供暂存运行的demo加载
fprintf('[pretrain] 完成: warmSteps=%d converged=%d blocks=%d\n', ...
    info.warmupSteps, info.warmConverged, info.warmBlocks);
fprintf('[pretrain] muB(12桶)=[%s]\n', sprintf('%.2f ',info.muPre));
fprintf('[pretrain] 已保存 %s 与 tempdir 副本\n', fullfile(outDir,'pretrained'));
end
