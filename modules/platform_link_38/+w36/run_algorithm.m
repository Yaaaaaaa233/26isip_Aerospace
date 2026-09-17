function [log, info] = run_algorithm(name, scn, c)
%RUN_ALGORITHM 任务3.6调度器：在实际约束对象上用指定策略跑完整一幕。
% 任务3.6设定(用户口径): "先通过首飞全飞拟合速度-功率曲线, 再用 task2 的算法"——
% 曲线未知, 但首飞架次允许全速度域快扫标定。策略集:
%   'hybrid'    首飞全速域标定(冻结曲线)+windinfer式在线风推断+闭式调度
%               (任务3.6主角 = 3.1的Phase A + 2.1的Phase B, 见hybrid_run)
%   'sweepcal'  全速度域快扫标定+在线精化(3.1主角, 对照: 重拟合链+探针)
%   'rl'        仿真器预训练+在线微调REINFORCE(3.1对照, 同样需150步标定)
%   'purerl_on'  预训练在线RL: 试飞时段预训练收敛→评估期继续小幅在线修正(3.5主角)
%   'purerl_off' 预训练离线RL: 试飞时段预训练收敛→评估期冻结策略纯执行(3.5主角)
%   'purerl_scratch' 从零在线RL对照(=3.4原purerl, 无预训练, 量化预训练价值)
%   'openloop'  开环控制基线: 固定速度平飞, 量化算法MOE提升
%   'windinfer' 功率调制风推断+闭式调度(已知曲线, oracle参照, 见windinfer_run)
%   'est'       在线风EKF估计+解析调度(已知曲线, oracle参照, 见est_run)
%   'known'     已知风+已知曲线oracle参照(评价侧上界, 非因果策略)
% (2026-09-07全项目精简: task1遗留直接搜索器 tracker/esc/spsa/bayes/qnewton/
% gtrack 已从 2.1/3.1/3.2 删除, 本任务不再收录。)
% 所有算法共享同一条指令就位规则(w36.settled_q): 横比只反映策略差异。
% 算法侧白名单：不传场景真值/曲线/噪声/种子(红线1); 接口与任务6一致
% (plant.q(v,tag)), 对象侧升级不改控制器接口(红线2)。
% 任务3.6曲线未知口径: 因果策略(hybrid/sweepcal/rl)只拿 ctrl_view 白名单
% (剔除曲线/u*/风/噪声真值); windinfer/est/known 依赖已知曲线, 作为 oracle
% 参照下发全量config(评价侧标注)。
useP=strcmp(c.backend,'platform');
if useP
    % 平台就位语义标定配置(2026-09-09/10, 数据源一致性): 平台慢俯仰+湍流下,
    % 扫频扩展[2,13.5]保证强风最优下潜区有样本(抗联合辨识退化), 探针100控制
    % 就位等待学费; 本地代理维持原[3,12]x150(已调优, 零改动)。
    c.swLo=2.0; c.swHi=13.5; c.swSteps=100;
end
pCtrl=w36.ctrl_view(c);
useP=strcmp(c.backend,'platform');
if useP
    plant=w36.make_platform_plant(scn,c); n=c.evalSeconds;   % 预算按秒
else
    plant=w36.make_plant(scn,c); n=c.duration;
end
switch name
    case 'openloop'
        info=w36.openloop_run(plant,pCtrl,n);
    case 'est'
        info=w36.est_run(plant,c,n);          % 已知曲线对照(oracle侧, 全量config)
    case 'windinfer'
        info=w36.windinfer_run(plant,c,n);           % 已知曲线oracle参照(全量config)
    case 'hybrid'
        info=w36.hybrid_run(plant,pCtrl,n);     % 任务3.6主角: 标定(冻结曲线)+风推断
    case {'sweepcal_pre','hybrid_pre','rl_pre'}
        % 任务3.7 "已标定好"模式: 标定移到独立试飞架次(不占评测预算/MOE),
        % 评估窗从标定完毕状态直接开始——与 purerl 预训练拆分同一预算口径。
        % 试飞场景=static、同分布不同实现(seed+17), 不泄漏评测段真值;
        % 本地/平台两种数据源都走同一逻辑(平台plant放宽试飞秒数预算, 就位委托制
        % 下每个扫频探针可能耗时数秒)。
        baseAlg=name(1:numel(name)-4);          % 去掉 '_pre'
        cW=c; cW.seed=c.seed+17;
        if useP
            cW.evalSeconds=c.swSteps*15+300;    % 平台试飞预算(秒): 探针就位耗时数秒/个
            cW.duration=cW.evalSeconds;         % (make_platform_plant 内部按 evalSeconds 推导)
            scnW=w36.scenario('static',cW);
            plantW=w36.make_platform_plant(scnW,cW);
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
        info=w36.pure_rl_run(plant,pCtrl,n);  % 从零在线对照(=3.4原purerl, 无预训练)
    case {'purerl_on','purerl_off'}
        % 3.5主角: 预训练在试飞时段(独立plant实例, 不占评测预算, 不进评价表/MOE)。
        % 试飞场景=static、湍流同分布不同实现(scenario seed+17), 不泄漏评测段真值。
        % 2026-09-09 数据源一致性修复: 原先无条件用本地代理plant预训练, 学到的是
        % 代理曲线(谷底6.3/深度0.90), 部署到平台(谷底5.15/深度0.727)存在系统性
        % 偏移。现本地后端维持原路径; 平台后端预训练改在平台plant上进行——默认
        % 复合风场景优先取缓存模型(make_platform_pretrain 离线生成), 其余风场
        % 配置回退为平台plant在线预训练(慢但正确)。
        if strcmp(name,'purerl_on'), md='on'; else, md='off'; end
        if useP
            M=w36.load_platform_pretrain(c);
            if ~isempty(M)
                info=w36.pure_rl_pre_run(plant,pCtrl,n,md,[],M);
            else
                cW=c; cW.seed=c.seed+17; cW.duration=pCtrl.plWarmMax+50;
                scnW=w36.scenario('static',cW);
                plantW=w36.make_platform_plant(scnW,cW);
                info=w36.pure_rl_pre_run(plant,pCtrl,n,md,plantW);
            end
        else
            cW=c; cW.seed=c.seed+17; cW.duration=pCtrl.plWarmMax+50;   % 试飞段预算=预训练上限
            scnW=w36.scenario('static',cW);
            plantW=w36.make_plant(scnW,cW);
            info=w36.pure_rl_pre_run(plant,pCtrl,n,md,plantW);
        end
    case 'sweepcal'
        info=w36.sweepcal_run(plant,pCtrl,n);   % 对照: 全速度域标定+重拟合链+探针
    case 'rl'
        info=w36.rl_run(plant,pCtrl,n);         % 对照: 仿真器预训练+在线微调
    case 'known'
        if useP
            info=w36.known_platform_run(plant,c,n);
        else
            info=w36.known_run(plant,c,n,scn);
        end    % 已知风+已知曲线oracle(全量config)
    otherwise
        error('w36:RunAlgorithm','Unknown algorithm: %s (purerl_on/purerl_off/purerl_scratch + 继承: sweepcal/rl/hybrid/openloop/windinfer/est/known)',name);
end
info.name=name; info.scenario=scn.kind; info.seed=c.seed;
if useP
    % 平台参照束(2026-09-09 数据源一致性): demo参考线/ylim/换算随数据源切换,
    % 全部取自平台权威真值(红线1: 只进评价侧与显示, 控制器不可读)。
    info.platTruth=plant.truth();
end
log=plant.table();
end
