function [log, info] = run_algorithm(name, scn, c)
%RUN_ALGORITHM 用指定算法对一个平移场景跑完整一幕(共 c.duration 个评估步)。
% name:
%   'grid'    网格扫描后锁定(基线)
%   'ternary' 三分搜索后锁定(基线)
%   'golden'  纯黄金分割后锁定(基线)
%   'brent'   Brent混合搜索后锁定(推荐搜索器, 无监测)
%   'tracker' Brent混合搜索 + 平移监测重夹逼(任务1推荐方案)
%   'esc'     连续极值寻优(在线跟踪基线, 镜像 esc_core.py V1)
% 除 tracker/esc 外均为"搜索后锁定"：搜索结束即停在最优估计上直到预算
% 用尽——它们没有平移监测，平移后的停滞正是 tracker 价值的对照证据。
plant=task1.make_plant(scn,c);
p=task1.controller_config(c);
n=c.duration;
switch name
    case 'grid'
        f=task1.search_query(plant);
        s=task1.grid_scan(f,p.lower,p.upper,p.gridResolution);
        holdRest(plant,s.x,n);
        info=struct('best',s.x,'searchEvals',s.evals,'researchCount',NaN,...
            'brackets',zeros(0,2),'bracketSegs',[0 0]);
    case 'ternary'
        f=task1.search_query(plant);
        s=task1.ternary_search(f,p.lower,p.upper,p.tol,p.maxSearchEval);
        holdRest(plant,s.x,n);
        info=struct('best',s.x,'searchEvals',s.evals,'researchCount',NaN,...
            'brackets',s.brackets,'bracketSegs',[1 s.evals]);
    case 'golden'
        f=task1.search_query(plant);
        s=task1.golden_search(f,p.lower,p.upper,p.tol,p.maxSearchEval);
        holdRest(plant,s.x,n);
        info=struct('best',s.x,'searchEvals',s.evals,'researchCount',NaN,...
            'brackets',s.brackets,'bracketSegs',[1 s.evals]);
    case 'brent'
        f=task1.search_query(plant);
        s=task1.brent_search(f,p.lower,p.upper,p.tol,p.maxSearchEval);
        holdRest(plant,s.x,n);
        info=struct('best',s.x,'searchEvals',s.evals,'researchCount',NaN,...
            'brackets',s.brackets,'bracketSegs',[1 s.evals]);
    case 'tracker'
        info=task1.tracker_run(plant,p,n);
    case 'esc'
        info=task1.esc_run(plant,p,n);
    otherwise
        error('task1:RunAlgorithm','Unknown algorithm: %s',name);
end
info.name=name; info.scenario=scn.kind; info.curve=c.curve;
log=plant.table();

    function holdRest(plant2,v,n2)
        while plant2.count()<n2
            plant2.q(v,'hold'); plant2.amendEstimate(v);
        end
    end
end
