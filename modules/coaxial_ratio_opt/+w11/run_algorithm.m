function [log, info] = run_algorithm(name, scn, c)
%RUN_ALGORITHM 工作包w11调度器：在黑箱对象上用指定策略跑完整一幕。
% 任务设定: 固定飞行速度下, 共轴双桨上下桨转速比 r 的分配使总功率最低。
% 曲线(功率-桨比)未知、干扰场 γ 未知, 只能靠"调桨比→功率"黑盒采样。
% 策略集(方法论映射表逐项移植自 speed_esc_matlab/3.4):
%   'sweepcal'    全比域快扫标定+在线精化(主角: 重拟合链+信赖域探针)
%   'hybrid'      首飞标定(冻结曲线)+干扰推断增量修正(主角: 消融视角)
%   'rl'          仿真器预训练+在线微调REINFORCE(对照, 需150步标定)
%   'purerl'      纯奖励RL(免标定对照)
%   'openloop'    开环基线: 固定 r=1(PX4默认等转速分配)
%   'interfinfer' 已知曲线, 滑窗NLS反演干扰场(oracle参照)
%   'est'         已知曲线, EKF跟踪干扰场(oracle参照)
%   'known'       已知γ场+曲线 oracle 上限(非因果)
% 所有算法共享同一条指令就位规则(w11.settled_q): 横比只反映策略差异。
% 红线1: 因果策略(sweepcal/rl/purerl/hybrid)只拿 ctrl_view 白名单(剔除真值);
% interfinfer/est/known 依赖已知曲线/干扰, 由本调度器下发全量config(oracle参照)。
pCtrl=w11.ctrl_view(c);
plant=w11.make_plant(scn,c);
n=c.duration;
switch name
    case 'openloop'
        info=w11.openloop_run(plant,pCtrl,n);
    case 'est'
        info=w11.est_run(plant,c,n);              % oracle参照(全量config)
    case 'interfinfer'
        info=w11.interfinfer_run(plant,c,n);      % oracle参照(全量config)
    case 'hybrid'
        info=w11.hybrid_run(plant,pCtrl,n);
    case 'purerl'
        info=w11.pure_rl_run(plant,pCtrl,n);
    case 'sweepcal'
        info=w11.sweepcal_run(plant,pCtrl,n);
    case 'rl'
        info=w11.rl_run(plant,pCtrl,n);
    case 'known'
        info=w11.known_run(plant,c,n,scn);        % oracle上限(全量config)
    otherwise
        error('w11:RunAlgorithm','Unknown algorithm: %s (四主角 sweepcal/rl/purerl/hybrid + openloop/interfinfer/est/known)',name);
end
info.name=name; info.scenario=scn.kind; info.seed=c.seed;
log=plant.table();
end
