function [radTab, latTab] = sweeps(folder, cBase)
%SWEEPS 任务7两项重新评估扫描(用户需求1/2的量化交付):
%   radTab  转弯半径扫描: R ∈ {50,100,150} (需求口径) + 500(任务6旧参考)
%           × 全部策略 × 3种子, 静态+双正交风主口径;
%   latTab  通信时延扫描: τ ∈ {0.1,0.3,0.5} × 全部策略 × 3种子 (R=100)。
% 输出CSV写入folder(给定了才写), 并原样返回表格。
algorithms={'openloop','tracker','esc','spsa','bayes','qnewton','gtrack','est'};
% ---- 转弯半径扫描 ----
rows=cell(0,8);
for R=[50 100 150 500]
    for seed=11:13
        for name=algorithms
            c=w7.config(cBase,'seed',seed,'turnRadius',R);
            scn=w7.scenario('static',c);
            [log,~]=w7.run_algorithm(name{1},scn,c);
            m=w7.mop_moe(log,c);
            rows(end+1,:)={name{1},R,seed,m.MOE_energy,m.MOE.overall,...
                m.energyExcessPercent,m.MOP.finalErr,m.MOP.meanTrackLag}; %#ok<AGROW>
        end
    end
end
radTab=cell2table(rows,'VariableNames',{'Policy','TurnRadius','Seed',...
    'MOE_energy','MOE_overall','EnergyExcessPercent','FinalErr','MeanTrackLag'});
% ---- 通信时延扫描 ----
rows=cell(0,8);
for tau=[0.1 0.3 0.5]
    for seed=11:13
        for name=algorithms
            c=w7.config(cBase,'seed',seed,'turnRadius',100,'latencySec',tau);
            scn=w7.scenario('static',c);
            [log,~]=w7.run_algorithm(name{1},scn,c);
            m=w7.mop_moe(log,c);
            rows(end+1,:)={name{1},tau,seed,m.MOE_energy,m.MOE.overall,...
                m.energyExcessPercent,m.MOP.finalErr,m.MOP.meanTrackLag}; %#ok<AGROW>
        end
    end
end
latTab=cell2table(rows,'VariableNames',{'Policy','LatencySec','Seed',...
    'MOE_energy','MOE_overall','EnergyExcessPercent','FinalErr','MeanTrackLag'});
if nargin>0 && ~isempty(folder)
    if ~exist(folder,'dir'), mkdir(folder); end
    writetable(radTab,fullfile(folder,'radius_sweep.csv'),'Encoding','UTF-8');
    writetable(latTab,fullfile(folder,'latency_sweep.csv'),'Encoding','UTF-8');
end
end
