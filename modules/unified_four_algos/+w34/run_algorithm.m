function [log, info] = run_algorithm(name, scn, c)
%RUN_ALGORITHM 任务3.4调度器：在实际约束对象上用指定策略跑完整一幕。
% 任务3.4设定(用户口径): "先通过首飞全飞拟合速度-功率曲线, 再用 task2 的算法"——
% 曲线未知, 但首飞架次允许全速度域快扫标定。策略集:
%   'hybrid'    首飞全速域标定(冻结曲线)+windinfer式在线风推断+闭式调度
%               (任务3.4主角 = 3.1的Phase A + 2.1的Phase B, 见hybrid_run)
%   'sweepcal'  全速度域快扫标定+在线精化(3.1主角, 对照: 重拟合链+探针)
%   'rl'        仿真器预训练+在线微调REINFORCE(3.1对照, 同样需150步标定)
%   'openloop'  开环控制基线: 固定速度平飞, 量化算法MOE提升
%   'windinfer' 功率调制风推断+闭式调度(已知曲线, oracle参照, 见windinfer_run)
%   'est'       在线风EKF估计+解析调度(已知曲线, oracle参照, 见est_run)
%   'known'     已知风+已知曲线oracle参照(评价侧上界, 非因果策略)
% (2026-09-07全项目精简: task1遗留直接搜索器 tracker/esc/spsa/bayes/qnewton/
% gtrack 已从 2.1/3.1/3.2 删除, 本任务不再收录。)
% 所有算法共享同一条指令就位规则(w34.settled_q): 横比只反映策略差异。
% 算法侧白名单：不传场景真值/曲线/噪声/种子(红线1); 接口与任务6一致
% (plant.q(v,tag)), 对象侧升级不改控制器接口(红线2)。
% 任务3.4曲线未知口径: 因果策略(hybrid/sweepcal/rl)只拿 ctrl_view 白名单
% (剔除曲线/u*/风/噪声真值); windinfer/est/known 依赖已知曲线, 作为 oracle
% 参照下发全量config(评价侧标注)。
pCtrl=w34.ctrl_view(c);
plant=w34.make_plant(scn,c);
n=c.duration;
switch name
    case 'openloop'
        info=w34.openloop_run(plant,pCtrl,n);
    case 'est'
        info=w34.est_run(plant,c,n);          % 已知曲线对照(oracle侧, 全量config)
    case 'windinfer'
        info=w34.windinfer_run(plant,c,n);           % 已知曲线oracle参照(全量config)
    case 'hybrid'
        info=w34.hybrid_run(plant,pCtrl,n);     % 任务3.4主角: 标定(冻结曲线)+风推断
    case 'purerl'
        info=w34.pure_rl_run(plant,pCtrl,n);  % 3.2主角: 纯奖励RL(免扫频/无模型)
    case 'sweepcal'
        info=w34.sweepcal_run(plant,pCtrl,n);   % 对照: 全速度域标定+重拟合链+探针
    case 'rl'
        info=w34.rl_run(plant,pCtrl,n);         % 对照: 仿真器预训练+在线微调
    case 'known'
        info=w34.known_run(plant,c,n,scn);    % 已知风+已知曲线oracle(全量config)
    otherwise
        error('w34:RunAlgorithm','Unknown algorithm: %s (四主角 sweepcal/rl/purerl/hybrid + openloop/windinfer/est/known)',name);
end
info.name=name; info.scenario=scn.kind; info.seed=c.seed;
log=plant.table();
end
