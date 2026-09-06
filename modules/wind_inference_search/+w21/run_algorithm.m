function [log, info] = run_algorithm(name, scn, c)
%RUN_ALGORITHM 任务2.1调度器：在实际约束对象上用指定策略跑完整一幕。
% 2026-09-07精简: 移除任务1遗留的直接搜索类算法(tracker/esc/spsa/bayes/
% qnewton/gtrack及其私有助手brent_search/search_query/gp_posterior) ——
% 它们不建模风, 在"风致地速最优漂移"设定下样本效率低且与任务2.1主题无关;
% 保留四策略聚焦横比:
%   'windinfer' 功率调制风矢量推断+闭式地速调度(任务2.1主角, 见windinfer_run):
%               无探针dither, 激励来自转圈航向扫描; 窗长自适应+风况判定
%   'openloop'  开环控制基线: 固定速度平飞, 量化算法MOE提升
%   'est'       在线风EKF估计+解析调度跟踪(模型法对照: 需探针dither, 见est_run)
%   'known'     已知风oracle参照(评价侧上界, 非因果策略)
% 所有算法共享同一条指令就位规则(w21.settled_q): 横比只反映策略差异。
% 算法侧白名单：不传场景真值/曲线/噪声/种子(红线1); 接口与任务6一致
% (plant.q(v,tag)), 对象侧升级不改控制器接口(红线2)。
p=c;   % 统一config即白名单(对象真值由plant持有, 不经p传递)
plant=w21.make_plant(scn,c);
n=c.duration;
switch name
    case 'openloop'
        info=w21.openloop_run(plant,p,n);
    case 'est'
        info=w21.est_run(plant,p,n);
    case 'windinfer'
        info=w21.windinfer_run(plant,p,n);
    case 'known'
        info=w21.known_run(plant,p,n,scn);
    otherwise
        error('w21:RunAlgorithm','Unknown algorithm: %s (2026-09-07精简后仅保留 windinfer/openloop/est/known)',name);
end
info.name=name; info.scenario=scn.kind; info.seed=c.seed;
log=plant.table();
end
