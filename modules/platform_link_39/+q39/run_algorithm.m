function [log, info] = run_algorithm(name, scn, c, opt)
%Q39.RUN_ALGORITHM Q1 调度器(以 3.8 号 +w36/run_algorithm 为基底, 含 3.7 *_pre 分支)。
% 与基底的唯一差异: platform 后端 plant 构造换成 q39.make_platform_plant_l0
% (估计链 plant), purerl 预训练缓存开关由 opt.pretrainCache 控制——
%   ANCHOR(真值锚点幕)开缓存: 复现 moe38 口径(预训练在真值链上离线完成);
%   L0 场景一律关: 预训练回退为在线试飞于同一估计口径 plant(预训练域=部署口径,
%   若沿用真值链缓存模型, 预训练域差会与估计器偏差混淆)。
% 臂函数仍调用 w36.* 原实现(38 号包): 臂只依赖 q/count/amendEstimate/table
% 三原语, 对 plant 实现无感知(红线 2)。算法侧白名单/种子语义不变(红线 1)。
if nargin < 3 || isempty(opt)
    opt = struct('estMode','l0','s1_pct',0,'s2_pct_mps',0,'s4_vpct',0,...
        'dwell_s',0,'pretrainCache',false);
    opt.arms = {};   % struct() 空 cell 陷阱, 见 make_platform_plant_l0
end
useP = strcmp(c.backend,'platform');
if useP
    % 平台就位语义标定配置(2026-09-09/10): 扫频扩展[2,13.5]x100(照抄基底)。
    c.swLo=2.0; c.swHi=13.5; c.swSteps=100;
end
pCtrl=w36.ctrl_view(c);
useP=strcmp(c.backend,'platform');
if useP
    plant=q39.make_platform_plant_l0(scn,c,opt); n=c.evalSeconds;   % 预算按秒
else
    plant=w36.make_plant(scn,c); n=c.duration;
end
switch name
    case 'openloop'
        info=w36.openloop_run(plant,pCtrl,n);
    case 'est'
        info=w36.est_run(plant,c,n);
    case 'windinfer'
        info=w36.windinfer_run(plant,c,n);
    case 'hybrid'
        info=w36.hybrid_run(plant,pCtrl,n);
    case {'sweepcal_pre','hybrid_pre','rl_pre'}
        baseAlg=name(1:numel(name)-4);
        cW=c; cW.seed=c.seed+17;
        if useP
            cW.evalSeconds=c.swSteps*15+300;
            cW.duration=cW.evalSeconds;
            scnW=w36.scenario('static',cW);
            plantW=q39.make_platform_plant_l0(scnW,cW,opt);
            nW=cW.evalSeconds;
        else
            cW.duration=c.swSteps*4+60;
            scnW=w36.scenario('static',cW);
            plantW=w36.make_plant(scnW,cW);
            nW=cW.duration;
        end
        preCal=w36.sweep_phaseA(plantW,pCtrl,nW);
        switch baseAlg
            case 'sweepcal', info=w36.sweepcal_run(plant,pCtrl,n,preCal);
            case 'hybrid',   info=w36.hybrid_run(plant,pCtrl,n,preCal);
            otherwise,       info=w36.rl_run(plant,pCtrl,n,preCal);
        end
    case {'purerl','purerl_scratch'}
        info=w36.pure_rl_run(plant,pCtrl,n);
    case {'purerl_on','purerl_off'}
        if strcmp(name,'purerl_on'), md='on'; else, md='off'; end
        if useP
            M=[];
            if opt.pretrainCache
                M=w36.load_platform_pretrain(c);
            end
            if ~isempty(M)
                info=w36.pure_rl_pre_run(plant,pCtrl,n,md,[],M);
            else
                cW=c; cW.seed=c.seed+17; cW.duration=pCtrl.plWarmMax+50;
                scnW=w36.scenario('static',cW);
                plantW=q39.make_platform_plant_l0(scnW,cW,opt);
                info=w36.pure_rl_pre_run(plant,pCtrl,n,md,plantW);
            end
        else
            cW=c; cW.seed=c.seed+17; cW.duration=pCtrl.plWarmMax+50;
            scnW=w36.scenario('static',cW);
            plantW=w36.make_plant(scnW,cW);
            info=w36.pure_rl_pre_run(plant,pCtrl,n,md,plantW);
        end
    case 'sweepcal'
        info=w36.sweepcal_run(plant,pCtrl,n);
    case 'rl'
        info=w36.rl_run(plant,pCtrl,n);
    case 'known'
        if useP
            info=w36.known_platform_run(plant,c,n);
        else
            info=w36.known_run(plant,c,n,scn);
        end
    otherwise
        error('q39:RunAlgorithm','Unknown algorithm: %s',name);
end
info.name=name; info.scenario=scn.kind; info.seed=c.seed;
if useP
    info.platTruth=plant.truth();
end
log=plant.table();
end
