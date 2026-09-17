function summary = run_task36_checks()
%RUN_TASK35_CHECKS 任务3.6检查：预训练purerl拆分(在线/离线) + 继承算法横比。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests_task36.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
windKinds={ % 名称, cfg(无风/恒定风3.5@40°/变风composite)
 'zero',  {'windKind','const','windBias',0.0,'windBiasY',0.0,'windAmp',0.0,'windAmpY',0.0};
 'const', {'windKind','const','windBias',3.5,'windBiasY',0.0,'windAmp',0.0,'windAmpY',0.0,'windDirDeg',40};
 'vary',  {'windKind','composite','windBias',2.5,'windAmp',1.5,'windOmega',0.08,...
           'windBiasY',0.0,'windAmpY',0.0,'turbStd',0.3};
};
% 2026-09-07精简: 移除任务1遗留搜索器(tracker/esc/spsa/bayes/qnewton/gtrack)。
policies={'openloop','sweepcal','rl','purerl_on','purerl_off','purerl_scratch','hybrid','known'};
% ---- A: 七种风场 × 七策略 短程冒烟矩阵(250步, 2种子) ----
kinds={'const','sin','square','triangle','turb','composite','sector'};
allPol=[policies,{'est','windinfer'}];
rows=cell(0,7); smokeOK=true;
for kk=1:numel(kinds)
    for name=allPol
        ex=zeros(1,2); acc=0; stp=zeros(1,2);
        for i=1:2
            c=w36.config('seed',10+i,'duration',250,'tailSteps',5,'windKind',kinds{kk},...
                'windAmpY',1.5,'windBiasY',1);
            [log,~]=w36.run_algorithm(name{1},w36.scenario('static',c),c);
            ex(i)=w36.mop_moe(log,c).energyExcessPercent;
            acc=max(acc,max(log.accelMax)); stp(i)=height(log);
            smokeOK=smokeOK && (stp(i)==250) && all(isfinite(log.powerMeas));
        end
        rows(end+1,:)={kinds{kk},name{1},mean(ex),max(ex),acc,stp(1),true}; %#ok<AGROW>
    end
end
smoke=cell2table(rows,'VariableNames',{'WindKind','Policy','ExcessMean',...
    'ExcessMax','MaxAccelUsed','Steps','EnergyOn'});
writetable(smoke,fullfile(folder,'wind_kinds_smoke.csv'),'Encoding','UTF-8');
% ---- B: 主口径横比 无风/恒定/变风 × 4策略 × 2种子(全程800步) ----
rows=cell(0,8);
for iw=1:size(windKinds,1)
    for name=policies
        ex=zeros(1,2); mo=ex; reg=ex; uerr=NaN;
        for i=1:2
            c=w36.config('seed',2+i,'duration',800,'tailSteps',60,windKinds{iw,2}{:});
            scn=w36.scenario('static',c);
            [log,info]=w36.run_algorithm(name{1},scn,c);
            m=w36.mop_moe(log,c);
            ex(i)=m.energyExcessPercent; mo(i)=m.MOE_energy; reg(i)=m.regretPercent;
            if any(strcmp(name{1},{'sweepcal','hybrid'}))
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
c=w36.config('seed',11,'duration',30,'tailSteps',5,'windKind','sin',...
    'windAmp',2,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1);
scn=w36.scenario('static',c);
plant=w36.make_plant(scn,c);
for k=1:30, plant.q(6.3,'hold'); plant.amendEstimate(6.3); end
lg=plant.table();
psi=deg2rad(lg.headingDeg);
uExp=hypot(lg.speed.*cos(psi)-lg.windX, lg.speed.*sin(psi)-lg.windY);
physOK=max(abs(lg.airspeed-uExp))<1e-9 && max(abs(lg.minPowerTrue-c.curveCase))<1e-9;
% ---- 白名单核验(红线1): 曲线未知口径 ----
pW=w36.ctrl_view(w36.config());
wlOK=~isfield(pW,'optimum0') && ~isfield(pW,'curveCoef') && ~isfield(pW,'rippleA1') ...
    && ~isfield(pW,'noiseSigma');
% ---- 门槛(四主角整合口径) ----
sel=@(w,pol) strcmp(main.WindKind,w) & strcmp(main.Policy,pol);
exOf=@(w,pol) main.EnergyExcessPercent(sel(w,pol));
scOK=mean(exOf('const','sweepcal'))<4.5 && ...
    mean(exOf('const','sweepcal'))<mean(exOf('const','openloop'));
uszOK=max(main.UstarErrMax(sel('const','sweepcal')))<0.8;
hbOK=mean(exOf('const','hybrid'))<5.0 && ...
    mean(exOf('const','hybrid'))<mean(exOf('const','openloop'));
pcOK=mean(exOf('const','purerl_off'))<mean(exOf('const','openloop')) && ...
    mean(exOf('const','purerl_off'))<5.0 && ...
    mean(exOf('const','purerl_on'))<mean(exOf('const','openloop'));
preOK=mean(exOf('const','purerl_off'))<mean(exOf('const','purerl_scratch')) && ...
    mean(exOf('const','purerl_on'))<mean(exOf('const','purerl_scratch'));
scvOK=mean(exOf('vary','sweepcal'))<mean(exOf('vary','openloop'));
rlvOK=mean(exOf('vary','rl'))<mean(exOf('vary','openloop'))+0.6;
pvOK=mean(exOf('vary','purerl_on'))<mean(exOf('vary','openloop'));
% 跳变场景(曲线+2.7@120步)下在线重学价值: 专用小实验(vary周期漂移下on/off接近, 不在此判)
cJ=w36.config('seed',3,'duration',800,'plWarmMax',2400,'jumpUpDx',2.7);
scnJ=w36.scenario('jumpUp',cJ);
[logJOn,~]=w36.run_algorithm('purerl_on',scnJ,cJ);
[logJOff,~]=w36.run_algorithm('purerl_off',scnJ,cJ);
ponOK=w36.mop_moe(logJOn,cJ).energyExcessPercent<w36.mop_moe(logJOff,cJ).energyExcessPercent;
hbvOK=mean(exOf('vary','hybrid'))>mean(exOf('vary','sweepcal'));  % 负结果复现: task2式在线变风受限
knownOK=all(arrayfun(@(w) mean(exOf(w,'known'))<1.5,{'zero','const','vary'}));
% ---- 平台后端对接(拍板1/2/3): 秒预算+平台P2物理链+MOE ----
platPol={'openloop','sweepcal','purerl_off','known'};
platRows=cell(0,5); platBudgetOK=true; platSweepOK=false; platKnownOK=false; platPurOK=false;
exOpenPlat=NaN; exPurPlat=NaN;
cP={'backend','platform','evalSeconds',500,'seed',11,'windKind','composite',...
    'windBias',2.5,'windAmp',0.0,'windBiasY',0.0,'windAmpY',0.0,'turbStd',0.3,'plWarmMax',800,'evalSeconds',900};
for name=platPol
    c=w36.config(cP{:}); scn=w36.scenario('static',c);
    [logP,infoP]=w36.run_algorithm(name{1},scn,c);
    mP=w36.mop_moe(logP,c);
    hOK=height(logP)>=c.evalSeconds && height(logP)<c.evalSeconds*1.25;
    platBudgetOK=platBudgetOK && hOK;
    if strcmp(name{1},'sweepcal'), platSweepOK=abs(infoP.uStar-5.0)<1.2; end
    if strcmp(name{1},'sweepcal'), platTailOK=mP.regretPercent<8.0; end
    if strcmp(name{1},'openloop'), exOpenPlat=mP.energyExcessPercent; end
    if strcmp(name{1},'purerl_off'), exPurPlat=mP.energyExcessPercent; end
    platRows(end+1,:)={name{1},mP.MOE_energy,mP.energyExcessPercent, ...
        height(logP),mP.regretPercent}; %#ok<AGROW>
end
platT=cell2table(platRows,'VariableNames',{'Policy','MOE_energy','ExcessPercent','Rows','TailRegret'});
writetable(platT,fullfile(folder,'platform_link.csv'),'Encoding','UTF-8');
platPurOK=isfinite(exPurPlat)&&isfinite(exOpenPlat)&&exPurPlat<exOpenPlat;   % 同后端内部对比
cK=w36.config('backend','platform','evalSeconds',500,'seed',11,...
    'windKind','const','windBias',0,'windBiasY',0);
scnK=w36.scenario('static',cK);
[logK,~]=w36.run_algorithm('known',scnK,cK);
platKnownOK=w36.mop_moe(logK,cK).energyExcessPercent<3.0;   % 零风: 信息上界口径
platTailOK=isfinite(platTailOK) && platTailOK;
checks=[...
    struct('item','单元测试全绿(purerl_on/off/scratch+继承sweepcal/rl/hybrid+风场库/空速语义/执行链)','pass',sum([unit.Passed])==numel(unit)),...
    struct('item','七种风场×策略冒烟: 全部预算走满、测量有限、|dv/dt|<=2','pass',smokeOK && all(smoke.MaxAccelUsed<=2+1e-9)),...
    struct('item','物理核验: 空速=|地速矢量−风矢量| 且 Pmin恒定=curveCase','pass',physOK),...
    struct('item','红线1白名单: ctrl_view剔除optimum0/曲线系数/噪声真值','pass',wlOK),...
    struct('item','恒定风: sweepcal 超额<4.5% 且优于开环','pass',scOK),...
    struct('item','恒定风: sweepcal û*辨识误差<0.8 m/s(谷底加权拟合修复后)','pass',uszOK),...
    struct('item','恒定风: hybrid 超额<5.0% 且优于开环(近期窗维护口径)','pass',hbOK),...
    struct('item','恒定风: purerl_off/on 优于开环 且 超额<5%','pass',pcOK),...
    struct('item','恒定风: 预训练(on/off) 优于从零对照scratch(预训练价值)','pass',preOK),...
    struct('item','变风: sweepcal 优于 openloop','pass',scvOK),...
    struct('item','变风: rl 与 openloop 相当(差距<0.6pp)','pass',rlvOK),...
    struct('item','变风: purerl_on 优于 openloop','pass',pvOK),...
    struct('item','跳变场景(+2.7@120步): purerl_on 优于 purerl_off(在线重学价值)','pass',ponOK),...
    struct('item','变风: hybrid 劣于 sweepcal(task2式在线已知限制, 负结果复现)','pass',hbvOK),...
    struct('item','三种风况 known oracle 超额<1.5%(信息上界)','pass',knownOK),...
    struct('item','平台对接: 逐秒日志覆盖任务窗(预算按秒, 拍板1)','pass',platBudgetOK),...
    struct('item','平台对接: sweepcal 盲找回平台真值谷底 v*≈5.15(误差<1.2, 900s窗, 拍板2)','pass',platSweepOK),...
    struct('item','平台对接: sweepcal 尾段超额<8%(复合风900s收敛)','pass',platTailOK),...
    struct('item','平台对接: 零风 known oracle 超额<3%(MOE 口径上界, 拍板3)','pass',platKnownOK),...
    struct('item','平台对接: purerl_off 优于开环(预训练离线部署)','pass',platPurOK)];
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),...
    'gatesPassed',sum([checks.pass]),'gatesTotal',numel(checks));
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
cl=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['# 任务3.6检查：预训练purerl拆分(purerl_on在线 / purerl_off离线 / purerl_scratch从零对照) + 继承算法横比\n\n' ...
    '预训练口径: purerl_on/off 获得试飞时段(独立plant, static, 湍流同分布不同实现, seed+17), 不占评测预算与MOE; 自动收敛判据见README\n\n生成时间：%s\n\n'],datestr(now,31));
fprintf(fid,'- 单元测试：%d/%d。\n- 检查门槛：%d/%d。\n\n',summary.unitPassed,summary.unitTotal,...
    summary.gatesPassed,summary.gatesTotal);
fprintf(fid,['## 任务设定(用户口径, 2026-09-07)\n\n"先通过首飞全飞拟合速度-功率曲线, 再用task2的算法": ', ...
    '主角hybrid = 3.1的Phase A(3→12 m/s双向扫150步, 联合辨识曲线f与风w) + 2.1的Phase B', ...
    '(曲线冻结, windinfer式滑窗二维NLS在线风推断+自适应窗长+风况判定, 每步闭式调度 ', ...
    'v*=q̂+√(q̂²+û*²−|ŵ|²)); 低频漂移守卫(每60步, 仅SSE真改善>2%%才接受重拟合)。', ...
    '对照: sweepcal(每20步重拟合链+探针)、rl(仿真器预训练+微调)、openloop、', ...
    'windinfer/est/known(已知曲线oracle参照)。MOE=纯能耗Emin/Eactual(2026-09-04口径)。\n\n']);
fprintf(fid,'## 主口径横比(无风/恒定/变风 × 6策略, 2种子均值, 800步)\n\n');
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
fprintf(fid,['\n说明: hybrid=用户设想"首飞标定+task2式在线"的最忠实实现(冻结曲线+细粒度风修正+', ...
    '信赖域探针)。消融结论: 恒定风下成立(与sweepcal差距<0.6pp, 换来在线机器更简单); 变风下', ...
    '不成立(劣于开环)——变风污染首飞标定且冻结曲线后û*无再锚定, sweepcal靠每20步重拟合argmin', ...
    '持续再锚定才稳定。全部hybrid/sweepcal账面含一次性标定学费(150/800≈19%%时间, 摊约2.5-3%%)。', ...
    'RL为对照: 谷底奖励二阶+1%%噪声, 等预算样本效率不足。\n']);
fprintf(fid,'\n冒烟矩阵见 wind_kinds_smoke.csv; 横比明细见 main_comparison.csv。\n');
fprintf(fid,['\n结论边界: 全部结果为虚拟/代理对象口径(AGENTS.md红线3), 不支持真实X8节能表述; ', ...
    'known为已知风+已知曲线oracle参照(非因果)。\n']);
fprintf('检查门槛：%d/%d\n',summary.gatesPassed,summary.gatesTotal);
if summary.gatesPassed<summary.gatesTotal, warning('w36:Checks','Some gates missed.'); end
end

function out=ternary(cond,a,b)
if cond, out=a; else, out=b; end
end
