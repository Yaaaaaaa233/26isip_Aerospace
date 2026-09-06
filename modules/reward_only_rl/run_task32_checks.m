function summary = run_task32_checks()
%RUN_TASK32_CHECKS 任务3.2检查：纯奖励RL(无扫频/无模型) + sweepcal/rl对照 + 鲁棒性回归。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests_task32.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
windKinds={ % 名称, cfg(无风/恒定风3.5@40°/变风composite)
 'zero',  {'windKind','const','windBias',0.0,'windBiasY',0.0,'windAmp',0.0,'windAmpY',0.0};
 'const', {'windKind','const','windBias',3.5,'windBiasY',0.0,'windAmp',0.0,'windAmpY',0.0,'windDirDeg',40};
 'vary',  {'windKind','composite','windBias',2.5,'windAmp',1.5,'windOmega',0.08,...
           'windBiasY',0.0,'windAmpY',0.0,'turbStd',0.3};
};
policies={'openloop','sweepcal','rl','purerl','known'};
% ---- A: 七种风场 × 策略 短程冒烟矩阵(250步, 2种子) ----
kinds={'const','sin','square','triangle','turb','composite','sector'};
allPol={'openloop','qnewton','sweepcal','rl','purerl','est'};
rows=cell(0,7); smokeOK=true;
for kk=1:numel(kinds)
    for ii=1:numel(allPol)
        name=allPol{ii};
        ex=zeros(1,2); acc=0; stp=zeros(1,2);
        for i=1:2
            c=w32.config('seed',10+i,'duration',250,'tailSteps',5,'windKind',kinds{kk},...
                'windAmpY',1.5,'windBiasY',1);
            [log,~]=w32.run_algorithm(name,w32.scenario('static',c),c);
            ex(i)=w32.mop_moe(log,c).energyExcessPercent;
            acc=max(acc,max(log.accelMax)); stp(i)=height(log);
            smokeOK=smokeOK && (stp(i)==250) && all(isfinite(log.powerMeas));
        end
        rows(end+1,:)={kinds{kk},name,mean(ex),max(ex),acc,stp(1),true}; %#ok<AGROW>
    end
end
smoke=cell2table(rows,'VariableNames',{'WindKind','Policy','ExcessMean',...
    'ExcessMax','MaxAccelUsed','Steps','EnergyOn'});
writetable(smoke,fullfile(folder,'wind_kinds_smoke.csv'),'Encoding','UTF-8');
% ---- B: 主口径横比 无风/恒定/变风 × 5策略 × 2种子(全程1200步) ----
rows=cell(0,8);
for iw=1:size(windKinds,1)
    for ii=1:numel(policies)
        name=policies{ii};
        ex=zeros(1,2); mo=ex; reg=ex; muAmp=NaN;
        for i=1:2
            c=w32.config('seed',2+i,'duration',1200,'tailSteps',60,windKinds{iw,2}{:});
            scn=w32.scenario('static',c);
            [log,info]=w32.run_algorithm(name,scn,c);
            m=w32.mop_moe(log,c);
            ex(i)=m.energyExcessPercent; mo(i)=m.MOE_energy; reg(i)=m.regretPercent;
            if strcmp(name,'purerl')
                muAmp=max(muAmp,max(info.muB)-min(info.muB));
            end
        end
        rows(end+1,:)={windKinds{iw,1},name,mean(mo),mean(ex),mean(reg),...
            std(ex),muAmp,1200}; %#ok<AGROW>
    end
end
main=cell2table(rows,'VariableNames',{'WindKind','Policy','MOE_energy',...
    'EnergyExcessPercent','TailRegretPercent','ExcessStd','MuProfileAmp','Steps'});
writetable(main,fullfile(folder,'main_comparison.csv'),'Encoding','UTF-8');
% ---- 物理口径核验 ----
c=w32.config('seed',11,'duration',30,'tailSteps',5,'windKind','sin',...
    'windAmp',2,'windBias',3,'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1);
scn=w32.scenario('static',c);
plant=w32.make_plant(scn,c);
for k=1:30, plant.q(6.3,'hold'); plant.amendEstimate(6.3); end
lg=plant.table();
psi=deg2rad(lg.headingDeg);
uExp=hypot(lg.speed.*cos(psi)-lg.windX, lg.speed.*sin(psi)-lg.windY);
physOK=max(abs(lg.airspeed-uExp))<1e-9 && max(abs(lg.minPowerTrue-c.curveCase))<1e-9;
% ---- 白名单核验(红线1): 曲线未知口径 ----
pW=w32.ctrl_view(w32.config());
wlOK=~isfield(pW,'optimum0') && ~isfield(pW,'curveCoef') && ~isfield(pW,'rippleA1') ...
    && ~isfield(pW,'noiseSigma');
% ---- 门槛 ----
sel=@(w,pol) strcmp(main.WindKind,w) & strcmp(main.Policy,pol);
exOf=@(w,pol) main.EnergyExcessPercent(sel(w,pol));
scOK=mean(exOf('const','sweepcal'))<4.5 && ...
    mean(exOf('const','sweepcal'))<mean(exOf('const','openloop'));
pcOK=mean(exOf('const','purerl'))<mean(exOf('const','openloop')) && ...
    mean(exOf('const','purerl'))<5.0;
pvOK=mean(exOf('vary','purerl'))<mean(exOf('vary','openloop'));
pampOK=max(main.MuProfileAmp(sel('const','purerl')))>2.0;
knownOK=all(arrayfun(@(w) mean(exOf(w,'known'))<1.5,{'zero','const','vary'}));
checks=[...
    struct('item','单元测试全绿(白名单/纯奖励RL/对照策略/风场库/空速语义/执行链)','pass',sum([unit.Passed])==numel(unit)),...
    struct('item','七种风场×策略冒烟: 全部预算走满、测量有限、|dv/dt|<=2','pass',smokeOK && all(smoke.MaxAccelUsed<=2+1e-9)),...
    struct('item','物理核验: 空速=|地速矢量−风矢量| 且 Pmin恒定=curveCase','pass',physOK),...
    struct('item','红线1白名单: ctrl_view剔除optimum0/曲线系数/噪声真值','pass',wlOK),...
    struct('item','恒定风: sweepcal(需150步标定) 超额<4.5% 且优于开环','pass',scOK),...
    struct('item','恒定风: purerl(免标定) 优于 openloop 且超额<5%','pass',pcOK),...
    struct('item','恒定风: purerl 学到地速补偿轮廓(幅值>2 m/s)','pass',pampOK),...
    struct('item','变风: purerl 优于 openloop','pass',pvOK),...
    struct('item','三种风况 known oracle 超额<1.5%(信息上界)','pass',knownOK)];
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),...
    'gatesPassed',sum([checks.pass]),'gatesTotal',numel(checks));
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
cl=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['# 任务3.2检查：纯奖励强化学习(无扫频/无模型) + sweepcal/rl对照\n\n生成时间：%s\n\n'],datestr(now,31));
fprintf(fid,['> 负责人：王健祺 | AI协助：ZCode | 证据等级：proxy（虚拟代理对象；红线3：不支持真实X8节能表述）' ...
    ' | 复跑入口：模块目录内 `run_task32_checks`、`table_3x3`\n\n']);
fprintf(fid,'- 单元测试：%d/%d。\n- 检查门槛：%d/%d。\n\n',summary.unitPassed,summary.unitTotal,...
    summary.gatesPassed,summary.gatesTotal);
fprintf(fid,['## 任务设定(用户口径)\n\n曲线未知且不做全速域扫频标定(省掉3.1的150步标定学费): 控制器只靠', ...
    '"调速度→功率→奖励"纯在线学习(pure_rl_run): 大幅值对偶探索(σ=1.2→0.5)+邻域共享核更新+', ...
    '分航向桶基线+表格型actor(12航向桶)。sweepcal(需150步标定)与rl(需150步+仿真器预训练)为对照。', ...
    'MOE=纯能耗Emin/Eactual(2026-09-04口径)。\n\n']);
fprintf(fid,'## 主口径横比(无风/恒定/变风 × 5策略, 2种子均值, 1200步)\n\n');
fprintf(fid,'| 风况 | 策略 | 能耗超额%% | 稳态尾段超额%% | MOE(纯能耗) | μ轮廓幅值 |\n|---|---|---:|---:|---:|---:|\n');
for iw=1:size(windKinds,1)
    for ii=1:numel(policies)
        selt=strcmp(main.WindKind,windKinds{iw,1}) & strcmp(main.Policy,policies{ii});
        r=main(selt,:);
        ma=ternary(isnan(r.MuProfileAmp(1)),'—',sprintf('%.2f',r.MuProfileAmp(1)));
        fprintf(fid,'| %s | %s | %.2f | %.2f | %.4f | %s |\n',windKinds{iw,1},policies{ii},...
            mean(r.EnergyExcessPercent),mean(r.TailRegretPercent),mean(r.MOE_energy),ma);
    end
end
fprintf(fid,'\n| 门槛 | 结果 |\n|---|---|\n');
for k=1:numel(checks)
    v='未过'; if checks(k).pass, v='通过'; end
    fprintf(fid,'| %s | %s |\n',checks(k).item,v);
end
fprintf(fid,['\n说明: sweepcal账面含一次性标定学费(150/1200≈12.5%%时间); purerl全程无扫频、\n'...
    '无模型、无u*知识, 大幅值探索本身有功率代价——它是"免标定可学习"的可行性证明, \n'...
    '稳态精度低于标定法是信息论意义下的诚实代价(谷底奖励二阶+1%%噪声)。\n']);
fprintf(fid,'\n冒烟矩阵见 wind_kinds_smoke.csv; 横比明细见 main_comparison.csv。\n');
fprintf('检查门槛：%d/%d\n',summary.gatesPassed,summary.gatesTotal);
if summary.gatesPassed<summary.gatesTotal, warning('w32:Checks','Some gates missed.'); end
end

function out=ternary(cond,a,b)
if cond, out=a; else, out=b; end
end
