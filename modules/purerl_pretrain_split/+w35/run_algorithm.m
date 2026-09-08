function [log, info] = run_algorithm(name, scn, c)
%RUN_ALGORITHM 任务3.5调度器：在实际约束对象上用指定策略跑完整一幕。
% 任务3.5设定(用户口径): "先通过首飞全飞拟合速度-功率曲线, 再用 task2 的算法"——
% 曲线未知, 但首飞架次允许全速度域快扫标定。策略集:
%   'hybrid'    首飞全速域标定(冻结曲线)+windinfer式在线风推断+闭式调度
%               (任务3.5主角 = 3.1的Phase A + 2.1的Phase B, 见hybrid_run)
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
% 所有算法共享同一条指令就位规则(w35.settled_q): 横比只反映策略差异。
% 算法侧白名单：不传场景真值/曲线/噪声/种子(红线1); 接口与任务6一致
% (plant.q(v,tag)), 对象侧升级不改控制器接口(红线2)。
% 任务3.5曲线未知口径: 因果策略(hybrid/sweepcal/rl)只拿 ctrl_view 白名单
% (剔除曲线/u*/风/噪声真值); windinfer/est/known 依赖已知曲线, 作为 oracle
% 参照下发全量config(评价侧标注)。
pCtrl=w35.ctrl_view(c);
plant=w35.make_plant(scn,c);
n=c.duration;
switch name
    case 'openloop'
        info=w35.openloop_run(plant,pCtrl,n);
    case 'est'
        info=w35.est_run(plant,c,n);          % 已知曲线对照(oracle侧, 全量config)
    case 'windinfer'
        info=w35.windinfer_run(plant,c,n);           % 已知曲线oracle参照(全量config)
    case 'hybrid'
        info=w35.hybrid_run(plant,pCtrl,n);     % 任务3.5主角: 标定(冻结曲线)+风推断
    case {'purerl','purerl_scratch'}
        info=w35.pure_rl_run(plant,pCtrl,n);  % 从零在线对照(=3.4原purerl, 无预训练)
    case {'purerl_on','purerl_off'}
        % 3.5主角: 预训练在试飞时段(独立plant实例, 不占评测预算, 不进评价表/MOE)。
        % 试飞场景=static、湍流同分布不同实现(scenario seed+17), 不泄漏评测段真值。
        cW=c; cW.seed=c.seed+17; cW.duration=pCtrl.plWarmMax+50;   % 试飞段预算=预训练上限
        scnW=w35.scenario('static',cW);
        plantW=w35.make_plant(scnW,cW);
        if strcmp(name,'purerl_on'), md='on'; else, md='off'; end
        info=w35.pure_rl_pre_run(plant,pCtrl,n,md,plantW);
    case 'sweepcal'
        info=w35.sweepcal_run(plant,pCtrl,n);   % 对照: 全速度域标定+重拟合链+探针
    case 'rl'
        info=w35.rl_run(plant,pCtrl,n);         % 对照: 仿真器预训练+在线微调
    case 'known'
        info=w35.known_run(plant,c,n,scn);    % 已知风+已知曲线oracle(全量config)
    otherwise
        error('w35:RunAlgorithm','Unknown algorithm: %s (purerl_on/purerl_off/purerl_scratch + 继承: sweepcal/rl/hybrid/openloop/windinfer/est/known)',name);
end
info.name=name; info.scenario=scn.kind; info.seed=c.seed;
log=plant.table();
end
