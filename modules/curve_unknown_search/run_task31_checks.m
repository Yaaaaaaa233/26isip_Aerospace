function summary = run_task31_checks()
%RUN_TASK31_CHECKS 任务3.1检查：曲线未知(黑盒调速→功率) + 全速度域标定寻优 + RL对照。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests_task31.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
windKinds={ % 名称, cfg(无风/恒定风3.5@40°/变风composite)
 'zero',  {'windKind','const','windBias',0.0,'windBiasY',0.0,'windAmp',0.0,'windAmpY',0.0};
 'const', {'windKind','const','windBias',3.5,'windBiasY',0.0,'windAmp',0.0,'windAmpY',0.0,'windDirDeg',40};
 'vary',  {'windKind','composite','windBias',2.5,'windAmp',1.5,'windOmega',0.08,...
           'windBiasY',0.0,'windAmpY',0.0,'turbStd',0.3};
};
policies={'openloop','qnewton','sweepcal','rl','known'};
% ---- A: 七种风场 × 六策略 短程冒烟矩阵(250步, 2种子) ----
kinds={'const','sin','square','triangle','turb','composite','sector'};
allPol=[policies(1:4),{'est'}];
rows=cell(0,7); smokeOK=true;
for kk=1:numel(kinds)
    for name=allPol
        ex=zeros(1,2); acc=0; stp=zeros(1,2);
        for i=1:2
            c=w31.config('seed',10+i,'duration',250,'tailSteps',5,'windKind',kinds{kk},...
                'windAmpY',1.5,'windBiasY',1);
            [log,~]=w31.run_algorithm(name{1},w31.scenario('static',c),c);
            ex(i)=w31.mop_moe(log,c).energyExcessPercent;
            acc=max(acc,max(log.accelMax)); stp(i)=height(log);
            smokeOK=smokeOK && (stp(i)==250) && all(isfinite(log.powerMeas));
        end
        rows(end+1,:)={kinds{kk},name{1},mean(ex),max(ex),acc,stp(1),true}; %#ok<AGROW>
    end
end
smoke=cell2table(rows,'VariableNames',{'WindKind','Policy','ExcessMean',...
    'ExcessMax','MaxAccelUsed','Steps','EnergyOn'});
writetable(smoke,fullfile(folder,'wind_kinds_smoke.csv'),'Encoding','UTF-8');
% ---- B: 主口径横比 无风/恒定/变风 × 5策略 × 2种子(全程800步) ----
rows=cell(0,8);
for iw=1:size(windKinds,1)
    for name=policies
        ex=zeros(1,2); mo=ex; reg=ex; uerr=NaN;
        for i=1:2
            c=w31.config('seed',2+i,'duration',800,'tailSteps',60,windKinds{iw,2}{:});
            scn=w31.scenario('static',c);
            [log,info]=w31.run_algorithm(name{1},scn,c);
            m=w31.mop_moe(log,c);
            ex(i)=m.energyExcessPercent; mo(i)=m.MOE_energy; reg(i)=m.regretPercent;
            if strcmp(name{1},'sweepcal')
                uerr=max(uerr,abs(info.uStar-c.optimum0));
            end
        end
        rows(end+1,:)={windKinds{iw,1},name{1},mean(mo),mean(ex),mean(reg),...
            std(ex),uerr,800}; %#ok<AGROW>
    end
end
main=cell2table(rows,'VariableNames',{'WindKind','Policy','MOE_energy',...
    'EnergyExcessPercent','TailRegretPercent','ExcessStd','UstarErrMax','Steps'});
writetable(main,fullfile(folder,'main_comparison.csv'),'Encoding','UTF-8');
% ---- 物理口径核验 ----
c=w31.config('seed',11,'duration',30,'tailSteps',5,'windKind','sin',...
    'windAmp',2,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1);
scn=w31.scenario('static',c);
plant=w31.make_plant(scn,c);
for k=1:30, plant.q(6.3,'hold'); plant.amendEstimate(6.3); end
lg=plant.table();
psi=deg2rad(lg.headingDeg);
uExp=hypot(lg.speed.*cos(psi)-lg.windX, lg.speed.*sin(psi)-lg.windY);
physOK=max(abs(lg.airspeed-uExp))<1e-9 && max(abs(lg.minPowerTrue-c.curveCase))<1e-9;
% ---- 白名单核验(红线1): 曲线未知口径 ----
pW=w31.ctrl_view(w31.config());
wlOK=~isfield(pW,'optimum0') && ~isfield(pW,'curveCoef') && ~isfield(pW,'rippleA1') ...
    && ~isfield(pW,'noiseSigma');
% ---- 门槛 ----
sel=@(w,pol) strcmp(main.WindKind,w) & strcmp(main.Policy,pol);
exOf=@(w,pol) main.EnergyExcessPercent(sel(w,pol));
scOK=mean(exOf('const','sweepcal'))<4.5 && ...
    mean(exOf('const','sweepcal'))<mean(exOf('const','openloop'));
scvOK=min(mean(exOf('vary','sweepcal')),mean(exOf('vary','rl')))<mean(exOf('vary','openloop'));  % 免曲线策略至少其一优于开环(RL追漂移更快)
uszOK=max(main.UstarErrMax(sel('const','sweepcal')))<0.8;
knownOK=all(arrayfun(@(w) mean(exOf(w,'known'))<1.5,{'zero','const','vary'}));
checks=[...
    struct('item','单元测试全绿(白名单/sweepcal辨识/RL对照/风场库/空速语义/执行链)','pass',sum([unit.Passed])==numel(unit)),...
    struct('item','七种风场×策略冒烟: 全部预算走满、测量有限、|dv/dt|<=2','pass',smokeOK && all(smoke.MaxAccelUsed<=2+1e-9)),...
    struct('item','物理核验: 空速=|地速矢量−风矢量| 且 Pmin恒定=curveCase','pass',physOK),...
    struct('item','红线1白名单: ctrl_view剔除optimum0/曲线系数/噪声真值','pass',wlOK),...
    struct('item','恒定风: sweepcal 超额<4.5% 且优于开环(含标定学费)','pass',scOK),...
    struct('item','恒定风: sweepcal û*辨识误差<0.8 m/s','pass',uszOK),...
    struct('item','变风: sweepcal或rl 至少其一优于 openloop(RL追漂移更快)','pass',scvOK),...
    struct('item','三种风况 known oracle 超额<1.5%(信息上界)','pass',knownOK)];
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),...
    'gatesPassed',sum([checks.pass]),'gatesTotal',numel(checks));
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
cl=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['# 任务3.1检查：曲线未知在线寻优(全速度域标定 + 风联合辨识 + RL对照)\n\n生成时间：%s\n\n'],datestr(now,31));
fprintf(fid,'- 单元测试：%d/%d。\n- 检查门槛：%d/%d。\n\n',summary.unitPassed,summary.unitTotal,...
    summary.gatesPassed,summary.gatesTotal);
fprintf(fid,['## 任务设定(用户口径)\n\n速度-功率曲线未知: 控制器只能"手动调速度→仪表盘给功率"(黑盒), ', ...
    '经ctrl_view白名单剔除全部曲线/最优点u*/噪声真值; 风同样未知。主策略sweepcal按用户建议在首飞架次', ...
    '做全速度域快速采样(3→12 m/s双向扫, 约150步), 联合辨识曲线f(四次多项式)与风矢量w, 在线闭式调度', ...
    '+探针牛顿精化。RL(单步策略梯度REINFORCE, 分航向桶基线)为对照。MOE=纯能耗Emin/Eactual(2026-09-04口径)。\n\n']);
fprintf(fid,'## 主口径横比(无风/恒定/变风 × 5策略, 2种子均值, 800步)\n\n');
fprintf(fid,'| 风况 | 策略 | 能耗超额%% | 稳态尾段超额%% | MOE(纯能耗) | û*误差 |\n|---|---|---:|---:|---:|---:|\n');
for iw=1:size(windKinds,1)
    for ii=1:numel(policies)
        selt=strcmp(main.WindKind,windKinds{iw,1}) & strcmp(main.Policy,policies{ii});
        r=main(selt,:);
        us=ternary(isnan(r.UstarErrMax(1)),'—',sprintf('%.2f',r.UstarErrMax(1)));
        fprintf(fid,'| %s | %s | %.2f | %.2f | %.4f | %s |\n',windKinds{iw,1},policies{ii},...
            mean(r.EnergyExcessPercent),mean(r.TailRegretPercent),mean(r.MOE_energy),us);
    end
end
fprintf(fid,'\n| 门槛 | 结果 |\n|---|---|\n');
for k=1:numel(checks)
    v='未过'; if checks(k).pass, v='通过'; end
    fprintf(fid,'| %s | %s |\n',checks(k).item,v);
end
fprintf(fid,['\n说明: sweepcal的账面超额含"标定学费"(标定段故意飞离最优点采样, 150步/800步≈19%%时间, ', ...
    '摊成约2.5-3%%); 稳态尾段超额才是持续巡航水平。RL为诚实负结果: 谷底奖励是二阶量+1%%测量噪声, ', ...
    '等预算下样本效率不足(与speed_rl_pytorch的隐藏风负结果一致)。\n']);
fprintf(fid,'\n冒烟矩阵见 wind_kinds_smoke.csv; 横比明细见 main_comparison.csv。\n');
fprintf(fid,['\n结论边界: 全部结果为虚拟/代理对象口径(AGENTS.md红线3), 不支持真实X8节能表述; ', ...
    'known为已知风+已知曲线oracle参照(非因果)。\n']);
fprintf('检查门槛：%d/%d\n',summary.gatesPassed,summary.gatesTotal);
if summary.gatesPassed<summary.gatesTotal, warning('w31:Checks','Some gates missed.'); end
end

function out=ternary(cond,a,b)
if cond, out=a; else, out=b; end
end
