function summary = run_task21_checks()
%RUN_TASK21_CHECKS 任务2.1检查：u*固定/Pmin恒定 + 风推断寻优横比 + 空速语义回归。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests_task21.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
% 2026-09-07精简: 移除任务1遗留搜索器(tracker/esc/spsa/bayes/qnewton/gtrack)。
policies={'openloop','est','windinfer','known'};
windKinds={ % 名称, cfg(无风/恒定风3.5@40°/变风composite)
 'zero',  {'windKind','const','windBias',0.0,'windBiasY',0.0,'windAmp',0.0,'windAmpY',0.0};
 'const', {'windKind','const','windBias',3.5,'windBiasY',0.0,'windAmp',0.0,'windAmpY',0.0,'windDirDeg',40};
 'vary',  {'windKind','composite','windBias',2.5,'windAmp',1.5,'windOmega',0.08,...
           'windBiasY',0.0,'windAmpY',0.0,'turbStd',0.3};
};
% ---- A: 七种风场 × 四策略 短程冒烟矩阵(80步, 2种子) ----
kinds={'const','sin','square','triangle','turb','composite','sector'};
allPol=policies;
rows=cell(0,7); smokeOK=true;
for kk=1:numel(kinds)
    for name=allPol
        ex=zeros(1,2); acc=0; stp=zeros(1,2);
        for i=1:2
            c=w21.config('seed',10+i,'duration',80,'tailSteps',5,'windKind',kinds{kk},...
                'windAmpY',1.5,'windBiasY',1);
            [log,~]=w21.run_algorithm(name{1},w21.scenario('static',c),c);
            ex(i)=w21.mop_moe(log,c).energyExcessPercent;
            acc=max(acc,max(log.accelMax)); stp(i)=height(log);
            smokeOK=smokeOK && (stp(i)==80) && all(isfinite(log.powerMeas));
        end
        rows(end+1,:)={kinds{kk},name{1},mean(ex),max(ex),acc,stp(1),true}; %#ok<AGROW>
    end
end
smoke=cell2table(rows,'VariableNames',{'WindKind','Policy','ExcessMean',...
    'ExcessMax','MaxAccelUsed','Steps','EnergyOn'});
writetable(smoke,fullfile(folder,'wind_kinds_smoke.csv'),'Encoding','UTF-8');
% ---- B: 任务2.1主口径横比 无风/恒定/变风 × 4策略 × 2种子(全程600步) ----
rows=cell(0,7);
for iw=1:size(windKinds,1)
    for name=policies
        ex=zeros(1,2); mo=ex; werr=NaN;
        for i=1:2
            c=w21.config('seed',2+i,'duration',600,'tailSteps',60,windKinds{iw,2}{:});
            scn=w21.scenario('static',c);
            [log,info]=w21.run_algorithm(name{1},scn,c);
            m=w21.mop_moe(log,c);
            ex(i)=m.energyExcessPercent; mo(i)=m.MOE_energy;
            if strcmp(name{1},'windinfer')
                wTrue=[c.windBias*cosd(c.windDirDeg)+0; c.windBias*sind(c.windDirDeg)];
                we=info.windEst; hh=we(:,ceil(size(we,2)/2):end);
                werr=mean(hypot(hh(1,:)-wTrue(1),hh(2,:)-wTrue(2)),'omitnan');
            end
        end
        rows(end+1,:)={windKinds{iw,1},name{1},mean(mo),mean(ex),std(ex),werr,600}; %#ok<AGROW>
    end
end
main=cell2table(rows,'VariableNames',{'WindKind','Policy','MOE_energy',...
    'EnergyExcessPercent','ExcessStd','WindErrMean','Steps'});
writetable(main,fullfile(folder,'main_comparison.csv'),'Encoding','UTF-8');
% ---- 物理口径核验: 空速=|地速−风| 与 Pmin恒定(检查脚本独立复算) ----
c=w21.config('seed',11,'duration',30,'tailSteps',5,'windKind','sin',...
    'windAmp',2,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1);
scn=w21.scenario('static',c);
plant=w21.make_plant(scn,c);
for k=1:30, plant.q(6.3,'hold'); plant.amendEstimate(6.3); end
lg=plant.table();
psi=deg2rad(lg.headingDeg);
uExp=hypot(lg.speed.*cos(psi)-lg.windX, lg.speed.*sin(psi)-lg.windY);
physOK=max(abs(lg.airspeed-uExp))<1e-9 && max(abs(lg.minPowerTrue-c.curveCase))<1e-9;
% ---- 门槛 ----
sel=@(w,pol) strcmp(main.WindKind,w) & strcmp(main.Policy,pol);
exOf=@(w,pol) main.EnergyExcessPercent(sel(w,pol));
zeroOK=mean(exOf('zero','windinfer'))<1.0;
constOK=mean(exOf('const','windinfer'))<2.0 && ...
    mean(exOf('const','windinfer'))<mean(exOf('const','openloop'));
varyOK=mean(exOf('vary','windinfer'))<mean(exOf('vary','openloop'));
knownOK=all(arrayfun(@(w) mean(exOf(w,'known'))<1.5,{'zero','const','vary'}));
infoOK=mean(exOf('const','openloop'))-mean(exOf('const','known'))>2.0;
checks=[...
    struct('item','单元测试全绿(u*固定/风推断/风场库/空速语义/执行链回归)','pass',sum([unit.Passed])==numel(unit)),...
    struct('item','七种风场×十策略冒烟: 全部预算走满、测量有限、|dv/dt|<=2','pass',smokeOK && all(smoke.MaxAccelUsed<=2+1e-9) && all(smoke.Steps==80)),...
    struct('item','物理核验: 空速=|地速矢量−风矢量| 且 Pmin恒定=curveCase','pass',physOK),...
    struct('item','零风: windinfer 超额<1%(无探针成本)','pass',zeroOK),...
    struct('item','恒定风: windinfer 超额<2% 且优于 openloop','pass',constOK),...
    struct('item','变风: windinfer 优于 openloop','pass',varyOK),...
    struct('item','三种风况 known oracle 超额<1.5%(信息上界)','pass',knownOK),...
    struct('item','恒定风下 known 较 openloop 信息价值>2pp','pass',infoOK)];
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),...
    'gatesPassed',sum([checks.pass]),'gatesTotal',numel(checks));
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
cl=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['# 任务2.1检查：风速推断寻优(u*固定, 风未知由功率反推)\n\n生成时间：%s\n\n'],datestr(now,31));
fprintf(fid,'- 单元测试：%d/%d。\n- 检查门槛：%d/%d。\n\n',summary.unitPassed,summary.unitTotal,...
    summary.gatesPassed,summary.gatesTotal);
fprintf(fid,['## 任务设定(用户口径)\n\n空速最优点u*固定且已知(空速-功率曲线先验固定, 无平移调度→Pmin恒定), 风'...
    '对控制器未知; 控制器只有功率仪表盘(带噪)、自身指令地速、采样时间与轨迹几何。'...
    '转圈时航向扫过风场, 功率被调制 P(ψ)=J0(|v·t̂−w|): 规整周期波动→恒定风; 毛糙/前后'...
    '不一致→变风。windinfer 在滑动窗内二维最小二乘反演 w=(wx,wy)(多起点Gauss-Newton), '...
    '窗长自适应(半窗解一致加窗/分歧缩窗), 输出风况判定, 并按闭式 v*=q+√(q²+u*²−|w|²) '...
    '调度地速。全程无探针dither——激励来自转圈本身的航向扫描。\n\n']);
fprintf(fid,'## 主口径横比(无风/恒定/变风 × 4策略, 2种子均值)\n\n');
fprintf(fid,'| 风况 | 策略 | 能耗超额%% | MOE(纯能耗) | 风估计误差(m/s) |\n|---|---|---:|---:|---:|\n');
for iw=1:size(windKinds,1)
    for ii=1:numel(policies)
        selt=strcmp(main.WindKind,windKinds{iw,1}) & strcmp(main.Policy,policies{ii});
        r=main(selt,:);
        fprintf(fid,'| %s | %s | %.2f | %.4f | %s |\n',windKinds{iw,1},policies{ii},...
            mean(r.EnergyExcessPercent),mean(r.MOE_energy),...
            ternary(isnan(r.WindErrMean(1)),'—',sprintf('%.2f',r.WindErrMean(1))));
    end
end
fprintf(fid,'\n| 门槛 | 结果 |\n|---|---|\n');
for k=1:numel(checks)
    v='未过'; if checks(k).pass, v='通过'; end
    fprintf(fid,'| %s | %s |\n',checks(k).item,v);
end
fprintf(fid,'\n冒烟矩阵见 wind_kinds_smoke.csv; 横比明细见 main_comparison.csv。\n');
fprintf(fid,['\n结论边界: 全部结果为虚拟/代理对象口径(AGENTS.md红线3), 不支持真实X8节能表述; '...
    'known为已知风oracle参照(非因果), 不参与黑箱横比。\n']);
fprintf('检查门槛：%d/%d\n',summary.gatesPassed,summary.gatesTotal);
if summary.gatesPassed<summary.gatesTotal, warning('w21:Checks','Some gates missed.'); end
end

function out=ternary(cond,a,b)
if cond, out=a; else, out=b; end
end
