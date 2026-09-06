function [log, info] = run_algorithm(name, scn, c)
%RUN_ALGORITHM 任务3.2调度器：在实际约束对象上用指定策略跑完整一幕。
% 2026-09-07精简: 移除任务1遗留的直接搜索类算法(tracker/esc/spsa/bayes/
% qnewton/gtrack及其私有助手brent_search/search_query/gp_posterior) ——
% 它们不建模"曲线未知", 谷底二阶信息+1%噪声下样本效率低; 保留:
%   'purerl'    纯奖励RL(任务3.2主角, 免扫频免模型, 见pure_rl_run)
%   'sweepcal'  全速度域快扫标定+在线精化(对照, 需150步标定, 见sweepcal_run)
%   'rl'        仿真器预训练+在线微调REINFORCE(对照, 需150步, 见rl_run)
%   'openloop'  开环控制基线: 固定速度平飞, 量化算法MOE提升
%   'windinfer' 功率调制风推断+闭式调度(已知曲线, oracle参照, 见windinfer_run)
%   'est'       在线风EKF估计+解析调度(已知曲线, oracle参照, 见est_run)
%   'known'     已知风+已知曲线oracle参照(评价侧上界, 非因果策略)
% 所有算法共享同一条指令就位规则(w32.settled_q): 横比只反映策略差异。
% 算法侧白名单：不传场景真值/曲线/噪声/种子(红线1); 接口与任务6一致
% (plant.q(v,tag)), 对象侧升级不改控制器接口(红线2)。
% 任务3.2曲线未知口径: 因果策略只拿 ctrl_view 白名单(剔除曲线/u*/风/噪声真值);
% windinfer/est/known 依赖已知曲线, 作为 oracle 参照下发全量config(评价侧标注)。
pCtrl=w32.ctrl_view(c);
plant=w32.make_plant(scn,c);
n=c.duration;
switch name
    case 'openloop'
        info=w32.openloop_run(plant,pCtrl,n);
    case 'est'
        info=w32.est_run(plant,c,n);          % 已知曲线对照(oracle侧, 全量config)
    case 'windinfer'
        info=w32.windinfer_run(plant,c,n);           % 已知曲线oracle参照(全量config)
    case 'purerl'
        info=w32.pure_rl_run(plant,pCtrl,n);    % 任务3.2主角: 纯奖励RL(无扫频无模型)
    case 'sweepcal'
        info=w32.sweepcal_run(plant,pCtrl,n);   % 对照: 全速度域标定+在线精化(需150步)
    case 'rl'
        info=w32.rl_run(plant,pCtrl,n);         % 对照: 仿真器预训练+在线微调(需150步)
    case 'known'
        info=w32.known_run(plant,c,n,scn);    % 已知风+已知曲线oracle(全量config)
    otherwise
        error('w32:RunAlgorithm','Unknown algorithm: %s (2026-09-07精简后仅保留 purerl/sweepcal/rl/openloop/windinfer/est/known)',name);
end
info.name=name; info.scenario=scn.kind; info.seed=c.seed;
log=plant.table();
end
