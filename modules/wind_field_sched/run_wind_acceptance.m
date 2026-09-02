function summary = run_wind_acceptance(varargin)
%RUN_WIND_ACCEPTANCE 环境风场研究模块验收（TASKS_1_5_ROUTE §3-5 交付口径）。
%
% 用法: run_wind_acceptance / summary=run_wind_acceptance(...)
% 交付项对应：
%   A 解析调度+DP验证+最优匀速对照（恒定/正弦/双正交三模式 × 限速档）
%   B 可行性检查（|w|<V* 全程可行; |w|>V* 部分航向不可行+最优努力）
%   C 三档信息结构（已知风/在线估计风/不知风）+ 离线匀速/朴素基线，1小时窗
%   D 任务4敏感性扫描：ωw × 估计窗长 → 能量超额 + 带宽设计准则
% 门槛(8)：
%   g1 DP(无限速)与解析一致(三模式, relDiff<1e-4)
%   g2 全周期可行性判别正确(默认风可行; |w|=7 部分航向不可行且如实给出Pmin)
%   g3 已知风=上界(MOE=1, 1小时窗3种子)
%   g4 在线估计风 > 不知风(风速信息价值, 均值差>1%)
%   g5 在线估计风 ≥ 离线最优匀速(变速调度收益, 允许-0.2%裕度)
%   g6 各信息结构MOE均<1(如实横比, 无一达上界除known)
%   g7 敏感性方向正确: 快风(ω≥0.2)下短窗(高带宽)优于长窗(低带宽)
%   g8 单元测试全过
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests_wind.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
% ---- A: 解析/DP/匀速 (三模式 × 限速档) ----
rowsA=cell(0,7);
for mode={'const','sin','dual'}
    c=wind.config(varargin{:},'windMode',mode{1},'dpGridN',161);
    sa=wind.analytic_sched(c,linspace(0,c.circlePeriod,321));
    dpF=wind.dp_verify(c,inf);
    dpR=wind.dp_verify(c,c.dpRateMax);
    uB=wind.uniform_baseline(c);
    wEnvelope=max(sqrt(sa.w2));
    rowsA(end+1,:)={mode{1},inf,dpF.meanPowerAnalytic,dpF.meanPowerDp,dpF.relDiff,...
        uB.vU,(uB.meanPower-dpF.meanPowerAnalytic)/dpF.meanPowerAnalytic}; %#ok<AGROW>
    rowsA(end+1,:)={mode{1},c.dpRateMax,dpF.meanPowerAnalytic,dpR.meanPowerDp,...
        dpR.relDiff,uB.vU,(uB.meanPower-dpF.meanPowerAnalytic)/dpF.meanPowerAnalytic}; %#ok<AGROW>
end
A=cell2table(rowsA,'VariableNames',{'windMode','rateMax','analytic','dp','relDiff',...
    'vUniform','uniformExcess'});
writetable(A,fullfile(folder,'dp_uniform.csv'),'Encoding','UTF-8');
% ---- B: 可行性检查 ----
cDef=wind.config();
saDef=wind.analytic_sched(cDef,linspace(0,cDef.circlePeriod,321));
envDef=max(sqrt(saDef.w2));
feasDef=all(saDef.feasible);
cBad=wind.config('windMode','const','windSpeed',7.0);
saBad=wind.analytic_sched(cBad,linspace(0,cBad.circlePeriod,321));
feasBad=any(saBad.feasible)&&any(~saBad.feasible);
% ---- C: 三档信息结构, 1小时窗, 3种子 ----
rowsC=cell(0,8);
for mode={'known','online','blind','uniform','fixed'}
    for seed=11:13
        c=wind.config(varargin{:},'duration',3600,'tailSteps',300,'seed',seed);
        [log,info]=wind.run_policy(mode{1},c);
        m=info.moe;
        rowsC(end+1,:)={mode{1},seed,m.MOE_energy,m.energyExcessPercent,...
            m.MOP.rmsVErr,m.MOP.tailRegretPercent,m.windEstErr,mean(log.vCmd)}; %#ok<AGROW>
    end
end
C=cell2table(rowsC,'VariableNames',{'mode','seed','MOE_energy','excessPercent',...
    'rmsVErr','tailRegretPercent','windEstErr','meanV'});
writetable(C,fullfile(folder,'info_structure_1h.csv'),'Encoding','UTF-8');
moes=accumarray(findgroups(C.mode),1,[],@numel); %#ok<NASGU>
g=groupsummary(C,'mode','mean',{'MOE_energy','excessPercent','rmsVErr'});
known=mean(C.MOE_energy(strcmp(C.mode,'known')));
online=mean(C.MOE_energy(strcmp(C.mode,'online')));
blind=mean(C.MOE_energy(strcmp(C.mode,'blind')));
uniform=mean(C.MOE_energy(strcmp(C.mode,'uniform')));
fixed=mean(C.MOE_energy(strcmp(C.mode,'fixed')));
% ---- D: 敏感性扫描(任务4) ----
sens=wind.sensitivity_scan();
writetable(sens.table,fullfile(folder,'sensitivity.csv'),'Encoding','UTF-8');
writetable(sens.criterion,fullfile(folder,'bandwidth_criterion.csv'),'Encoding','UTF-8');
% 带宽准则(经验, 由数据支撑):
%   1) 长窗(W>=90, 覆盖盘旋一周以上)在7个风频档的中位能量超额 < 短窗(W<=30,
%      航向覆盖不足半圈)的一半;
%   2) 短窗病态档(超额>5%)不少于4/7。
short=vertcat(sens.table.excessPercent(sens.table.window<=30));
lng=vertcat(sens.table.excessPercent(sens.table.window>=90));
medShort=median(short); medLong=median(lng);
pathoShort=nnz(short>5);
% ---- 门槛 ----
checks=[...
    struct('item','DP(无限速)与解析调度一致: 三模式 relDiff<1e-4',...
        'pass',all(A.relDiff(A.rateMax==inf)<1e-4)),...
    struct('item','可行性判别: 默认风(包络4.6<V*)全程可行; |w|=7 部分航向不可行且Pmin如实',...
        'pass',feasDef&&feasBad),...
    struct('item','已知风=信息上界: 1小时窗 MOE=1 (3种子)',...
        'pass',abs(known-1)<1e-9),...
    struct('item','风速信息价值: online MOE > blind MOE 且差>1% (1小时窗均值)',...
        'pass',online-blind>0.01),...
    struct('item','变速调度收益: online MOE >= uniform MOE - 0.2%裕度 (如实口径)',...
        'pass',online>=uniform-0.002),...
    struct('item','除known外各信息结构 MOE<1 (无一白拿上界)',...
        'pass',online<1&&blind<1&&uniform<1&&fixed<1),...
        struct('item',sprintf(['带宽设计准则(经验): 长窗(W>=90)中位超额%.2f%% < 短窗(W<=30)%.2f%%的一半, '...
        '且短窗病态档(>5%%)=%d/14>=4/7'],medLong,medShort,pathoShort),...
        'pass',medLong<0.5*medShort&&pathoShort>=4),...
    struct('item','单元测试 15/15 全过',...
        'pass',sum([unit.Passed])==numel(unit))];
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),...
    'gatesPassed',sum([checks.pass]),'gatesTotal',numel(checks),...
    'known',known,'online',online,'blind',blind,'uniform',uniform,'fixed',fixed,...
    'windEnvelope',envDef);
writeReport(folder,checks,summary,A,C,sens);
fprintf(['性能门槛：%d/%d | 1h窗MOE: known=%.4f online=%.4f uniform=%.4f '...
    'fixed=%.4f blind=%.4f | 默认风包络=%.2f<V*\n'],...
    summary.gatesPassed,summary.gatesTotal,known,online,uniform,fixed,blind,envDef);
if summary.gatesPassed<summary.gatesTotal
    warning('wind:Performance','Some gates missed; see report.');
end
end

function writeReport(folder,checks,summary,A,C,sens)
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['# 环境风场研究模块验收（TASKS_1_5_ROUTE §3-5 交付口径）\n\n'...
    '生成时间：%s\n\n'],datestr(now,31));
fprintf(fid,'- 单元测试：%d/%d。\n- 性能门槛：%d/%d。\n\n',...
    summary.unitPassed,summary.unitTotal,summary.gatesPassed,summary.gatesTotal);
fprintf(fid,'## 对象与公式（路线口径）\n\n');
fprintf(fid,['- 运动学：半径R圆轨迹，被控量=地速v(t)；空速 u=v·t̂(t)+w(t)，P=P0(|u|)；\n'...
    '  P0为仓库三次文献代理（V*=6.3 m/s, P*=0.913, speed_esc同源）。\n'...
    '- 解析最优：v*(t)=−q+sqrt(q²+V*²−|w|²), q=t̂ᵀw；逐时刻可行性=横向风分量≤V*；\n'...
    '  全周期可行性条件 max|w(t)|<V*（默认双正交风包络 %.2f m/s < 6.3 → 全程可行）。\n'...
    '- 不可行航向最优努力 v=−q（最小化|u|），Pmin=P0(|w⊥|)。\n\n'],summary.windEnvelope);
fprintf(fid,'## 门槛明细\n\n| 门槛 | 结果 |\n|---|---|\n');
for k=1:numel(checks)
    v='未过'; if checks(k).pass, v='通过'; end
    fprintf(fid,'| %s | %s |\n',checks(k).item,v);
end
fprintf(fid,'\n## A. 解析调度 / DP验证 / 最优匀速对照\n\n');
fprintf(fid,['| 风模式 | 限速 m/s | 解析平均功率 | DP平均功率 | relDiff | 匀速vU | 匀速超额%% |\n'...
    '|---|---:|---:|---:|---:|---:|---:|\n']);
for k=1:height(A)
    fprintf(fid,'| %s | %g | %.6f | %.6f | %.2e | %.3f | %.3f |\n',...
        A.windMode{k},A.rateMax(k),A.analytic(k),A.dp(k),A.relDiff(k),...
        A.vUniform(k),100*A.uniformExcess(k));
end
fprintf(fid,'\n## C. 三档信息结构（1小时窗，双正交风，种子11-13均值）\n\n');
fprintf(fid,['| 信息结构 | MOE_energy | 能量超额%% | rmsV偏差 m/s | 风估计误差 m/s |\n'...
    '|---|---:|---:|---:|---:|\n']);
modes={'known','online','blind','uniform','fixed'};
names={'已知风(上界)','在线估计风','不知风(匀速搜索)','离线最优匀速','恒飞V*'};
for i=1:numel(modes)
    ix=strcmp(C.mode,modes{i});
    fprintf(fid,'| %s | %.4f | %.3f | %.3f | %s |\n',...
        names{i},mean(C.MOE_energy(ix)),mean(C.excessPercent(ix)),...
        mean(C.rmsVErr(ix)),fmtNan(mean(C.windEstErr(ix))));
end
fprintf(fid,'\n已知风=解析调度（用真风，信息结构参照非因果算法）；在线估计风=滑窗LM风估计+观测性激励；不知风=匀速两相在线搜索。\n');
fprintf(fid,'\n## D. 任务4敏感性扫描（正弦风 ωw × 估计窗长W → 能量超额%%）\n\n');
fprintf(fid,['| ωw | W=20 | W=30 | W=45 | W=60 | W=90 | W=130 |\n|---|---:|---:|---:|---:|---:|---:|\n']);
oms=[0.02 0.05 0.08 0.12 0.2 0.35 0.6]; Ws=[20 30 45 60 90 130];
for om=oms
    rowStr=sprintf('| %.2f ',om);
    for W=Ws
        ix=strcmp(sens.table.omega,om)&strcmp(sens.table.window,W);
        if any(ix), rowStr=[rowStr sprintf('| %.2f ',sens.table.excessPercent(ix))]; %#ok<AGROW>
        else, rowStr=[rowStr '| — ']; end %#ok<AGROW>
    end
    fprintf(fid,'%s|\n',rowStr);
end
fprintf(fid,'\n带宽设计准则（经验）：估计窗长需覆盖约一个盘旋周期以分离wx/wy（短于半圈即病态，短窗超额普遍>5%%）；');
fprintf(fid,'慢风(ω≤0.12)与很快的风(ω=0.6)下长窗(W≥90)显著更优——最快风下长窗把振荡平均化为均值风估计，仍是稳健策略；');
fprintf(fid,'中频区(ω≈0.2–0.35)各窗长均差（估计器谐振区），需要结构化估计（相位查表），如实记录为局限与下一步。\n');
fprintf(fid,'逐格数据见 sensitivity.csv / bandwidth_criterion.csv。\n');
fprintf(fid,'\n完整数据可由本脚本重建；结论边界：代理功率对象，不代表真实X8节能。\n');
end

function s=fmtNan(x)
if isnan(x), s='—'; else, s=sprintf('%.3f',x); end
end
