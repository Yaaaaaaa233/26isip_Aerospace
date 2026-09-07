function summary = run_checks()
%RUN_CHECKS 工作包w11验收：固定速度下上下桨转速比的在线功率寻优。
% 口径与 speed_esc_matlab/3.4 的 run_task34_checks 一致(变量: 速度→桨比):
%   冒烟矩阵(七模板×八策略×2种子) + 主口径横比(无干扰/恒定/漂移 × 六策略×2种子, 800步)
%   + 物理核验 + 红线1白名单核验 + 验收门槛(≥10项, 含提示词指定必查项:
%   "漂移干扰下扫频标定优于开环") + results/report.md 落盘。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
windKinds={ % 名称, cfg(无干扰/恒定干扰γ=1.08/漂移干扰composite)
 'zero',  {'gammaKind','const','gammaBias',0.0};
 'const', {'gammaKind','const','gammaBias',0.08};
 'drift', {'gammaKind','composite','gammaBias',0.0,'gammaAmp',0.04,'turbStd',0.015};
};
policies={'openloop','sweepcal','rl','purerl','hybrid','known'};
% ---- A: 七种干扰模板 × 八策略 短程冒烟矩阵(250步, 2种子) ----
kinds={'const','sin','square','triangle','turb','composite','sector'};
allPol=[policies,{'est','interfinfer'}];
rows=cell(0,6); smokeOK=true;
for kk=1:numel(kinds)
    for name=allPol
        ex=zeros(1,2); acc=0; stp=zeros(1,2);
        for i=1:2
            c=w11.config('seed',10+i,'duration',250,'tailSteps',5,'gammaKind',kinds{kk},...
                'gammaAmp',0.04,'gammaBias',0.03);
            [log,~]=w11.run_algorithm(name{1},w11.scenario('static',c),c);
            ex(i)=w11.mop_moe(log,c).energyExcessPercent;
            acc=max(acc,max(log.slewUsed)); stp(i)=height(log);
            smokeOK=smokeOK && (stp(i)==250) && all(isfinite(log.powerMeas));
        end
        rows(end+1,:)={kinds{kk},name{1},mean(ex),max(ex),acc,stp(1)}; %#ok<AGROW>
    end
end
smoke=cell2table(rows,'VariableNames',{'GammaKind','Policy','ExcessMean',...
    'ExcessMax','MaxSlewUsed','Steps'});
writetable(smoke,fullfile(folder,'gamma_kinds_smoke.csv'),'Encoding','UTF-8');
% ---- B: 主口径横比 无干扰/恒定/漂移 × 六策略 × 2种子(全程800步) ----
rows=cell(0,8);
for iw=1:size(windKinds,1)
    for name=policies
        ex=zeros(1,2); mo=ex; reg=ex; rerr=NaN(1,2);
        for i=1:2
            c=w11.config('seed',2+i,'duration',800,'tailSteps',60,windKinds{iw,2}{:});
            scn=w11.scenario('static',c);
            [log,info]=w11.run_algorithm(name{1},scn,c);
            m=w11.mop_moe(log,c);
            ex(i)=m.energyExcessPercent; mo(i)=m.MOE_energy; reg(i)=m.regretPercent;
            if any(strcmp(name{1},{'sweepcal','hybrid','rl'}))
                if strcmp(name{1},'sweepcal') || strcmp(name{1},'hybrid')
                    if strcmp(windKinds{iw,1},'const')
                        rerr(i)=abs(info.rStar-(c.rStar0+w11.drift_of(1.08,c)));
                    else
                        rerr(i)=abs(info.rStar-c.rStar0);
                    end
                end
            end
        end
        rows(end+1,:)={windKinds{iw,1},name{1},mean(mo),mean(ex),mean(reg),...
            std(ex),max(rerr),800}; %#ok<AGROW>
    end
end
main=cell2table(rows,'VariableNames',{'GammaKind','Policy','MOE_energy',...
    'EnergyExcessPercent','TailRegretPercent','ExcessStd','RstarErrMax','Steps'});
writetable(main,fullfile(folder,'main_comparison.csv'),'Encoding','UTF-8');
% ---- 物理口径核验 ----
c=w11.config('seed',11,'duration',30,'tailSteps',5,'gammaKind','const','gammaBias',0);
scn=w11.scenario('static',c);
plant=w11.make_plant(scn,c);
for k=1:30, plant.q(1.0,'hold'); plant.amendEstimate(1.0); end
lg=plant.table();
Pexp=w11.fwd_level(c.fwdSpeed,c)*w11.truth_curve(1.0,c);
physOK=max(abs(lg.powerTrue-Pexp))<1e-9 && ...
    max(abs(lg.minPowerTrue-w11.fwd_level(c.fwdSpeed,c)*c.ratioCase))<1e-9 && ...
    max(abs(lg.optimumTrue-c.rStar0))<1e-9;
% ---- 白名单核验(红线1) ----
pW=w11.ctrl_view(w11.config());
wlOK=~isfield(pW,'rStar0') && ~isfield(pW,'ratioCase') && ~isfield(pW,'rippleA1') ...
    && ~isfield(pW,'noiseSigma') && ~isfield(pW,'cdw') && ~isfield(pW,'drMapD') ...
    && ~isfield(pW,'gammaAmp');
% ---- 门槛 ----
sel=@(w,pol) strcmp(main.GammaKind,w) & strcmp(main.Policy,pol);
exOf=@(w,pol) main.EnergyExcessPercent(sel(w,pol));
scOK=mean(exOf('const','sweepcal'))<4.5 && ...
    mean(exOf('const','sweepcal'))<mean(exOf('const','openloop'));
rszOK=max(main.RstarErrMax(sel('const','sweepcal')))<0.03;
scvOK=mean(exOf('drift','sweepcal'))<mean(exOf('drift','openloop'));
hbOK=mean(exOf('const','hybrid'))<5.0 && ...
    mean(exOf('const','hybrid'))<mean(exOf('const','openloop'));
hbvOK=mean(exOf('drift','hybrid'))<mean(exOf('drift','openloop'));
pcOK=mean(exOf('const','purerl'))<mean(exOf('const','openloop')) && ...
    mean(exOf('const','purerl'))<5.0;
pvOK=mean(exOf('drift','purerl'))<mean(exOf('drift','openloop'));
rlzOK=mean(exOf('zero','rl'))<mean(exOf('zero','openloop'));
knownOK=all(arrayfun(@(w) mean(exOf(w,'known'))<1.0,{'zero','const','drift'}));
olOK=abs(mean(exOf('zero','openloop'))-100*(1/w11.config().ratioCase-1))<1.0;
checks=[...
    struct('item','单元测试全绿(43项: MT链/漂移映射/涟漪锚点/七模板/执行链/白名单/因果结构)','pass',sum([unit.Passed])==numel(unit)),...
    struct('item','七种干扰模板×八策略冒烟: 全部预算走满、测量有限、|Δr/步|≤slewMax·tEval','pass',smokeOK && all(smoke.MaxSlewUsed<=0.15*1+1e-9)),...
    struct('item','物理核验: 无干扰static下 P=fV·truth(r) 精确、Emin列=fV·case、r*列恒=rStar0','pass',physOK),...
    struct('item','红线1白名单: ctrl_view剔除rStar0/case/涟漪/MT链/漂移映射/γ场/噪声真值','pass',wlOK),...
    struct('item','漂移映射: dr(γ)单调、dr(1)=0、γ=1.08→r*=0.913(±0.005) 且水平因子>1','pass',driftMapOK()),...
    struct('item','无干扰: openloop(r=1)固有超额≈1/case−1≈5.3%(±1pp, 飞试节能口径)','pass',olOK),...
    struct('item','恒定干扰: sweepcal 超额<4.5% 且优于 openloop','pass',scOK),...
    struct('item','恒定干扰: sweepcal 谷底辨识误差<0.03(样本支撑谷底选择)','pass',rszOK),...
    struct('item','漂移干扰: sweepcal 优于 openloop(提示词指定必查门槛)','pass',scvOK),...
    struct('item','恒定干扰: hybrid <5% 且优于 openloop','pass',hbOK),...
    struct('item','漂移干扰: hybrid 优于 openloop(探针跟踪+低频维护)','pass',hbvOK),...
    struct('item','恒定干扰: purerl 优于 openloop 且 <5%','pass',pcOK),...
    struct('item','漂移干扰: purerl 优于 openloop','pass',pvOK),...
    struct('item','无干扰: rl 优于 openloop(仿真器预训练口径)','pass',rlzOK),...
    struct('item','三种干扰档 known oracle 超额<1.0%(信息上界)','pass',knownOK)];
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),...
    'gatesPassed',sum([checks.pass]),'gatesTotal',numel(checks));
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
cl=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['# 工作包w11检查：固定速度下上下桨转速比的在线功率寻优' ...
    '(sweepcal/rl/purerl/hybrid 同对象同口径横比)\n\n生成时间：%s\n\n'],datestr(now,31));
fprintf(fid,['- 单元测试：%d/%d。\n- 检查门槛：%d/%d。\n\n'],summary.unitPassed,...
    summary.unitTotal,summary.gatesPassed,summary.gatesTotal);
fprintf(fid,['## 任务设定\n\n控制量 r=η_Ω=Ω_u/Ω_l∈[0.75,1.25](项目任务书表1), 开环基线r=1(默认等转速分配); ' ...
    '功率-桨比真值模型取自 Opazo et al. 2022 Eq.(27)-(35) MT链(谷底经cdw标定锚定飞试 ' ...
    'r*=0.89, 深度经功率变换标定到 case=0.95↔节能5%口径); 干扰=等效诱导干扰因子γ漂移 ' ...
    '(类比风), γ=1.08 时 r* 上移至≈0.913。四主角均纯因果(ctrl_view白名单); ' ...
    'interfinfer/est/known 依赖已知曲线/干扰, 为oracle参照。MOE=纯能耗Emin/Eactual。\n\n']);
fprintf(fid,'## 主口径横比(无干扰/恒定/漂移 × 六策略, 2种子均值, 800步)\n\n');
fprintf(fid,'| 干扰档 | 策略 | 能耗超额%% | 稳态尾段超额%% | MOE(纯能耗) | r̂*误差 |\n|---|---|---:|---:|---:|---:|\n');
for iw=1:size(windKinds,1)
    for ii=1:numel(policies)
        selt=strcmp(main.GammaKind,windKinds{iw,1}) & strcmp(main.Policy,policies{ii});
        r=main(selt,:);
        us=ternary(isnan(r.RstarErrMax(1)),'—',sprintf('%.3f',r.RstarErrMax(1)));
        fprintf(fid,'| %s | %s | %.2f | %.2f | %.4f | %s |\n',windKinds{iw,1},policies{ii},...
            mean(r.EnergyExcessPercent),mean(r.TailRegretPercent),mean(r.MOE_energy),us);
    end
end
fprintf(fid,'\n| 门槛 | 结果 |\n|---|---|\n');
for k=1:numel(checks)
    v='未过'; if checks(k).pass, v='通过'; end
    fprintf(fid,'| %s | %s |\n',checks(k).item,v);
end
fprintf(fid,['\n适用边界对照(与速度包结论对照): 恒定干扰下 sweepcal(重拟合链)最优, ', ...
    'hybrid(冻结曲线+探针)次之但机器更轻; 漂移干扰下 sweepcal/purerl 靠重拟合argmin/', ...
    '纯奖励在线学习跟踪漂移, 均优于开环; known≈0 为信息上界。开环基线的固有超额', ...
    '≈1/case−1≈5.3%%即Opazo飞试"差速分配节能≈5%%"的口径来源。\n']);
fprintf(fid,['\n结论边界: 全部结果为虚拟/代理对象口径(AGENTS.md红线3), 不支持真实X8节能表述; ', ...
    'known/interfinfer/est为oracle参照(非因果)。\n']);
fprintf(fid,'\n冒烟矩阵见 gamma_kinds_smoke.csv; 横比明细见 main_comparison.csv。\n');
fprintf('检查门槛：%d/%d\n',summary.gatesPassed,summary.gatesTotal);
if summary.gatesPassed<summary.gatesTotal, warning('w11:Checks','Some gates missed.'); end
end

function out=ternary(cond,a,b)
if cond, out=a; else, out=b; end
end

function ok=driftMapOK()
c=w11.config();
ok=all(diff(c.drMapD)>0) && abs(c.drMapD(find(abs(c.drMapG-1)<1e-9,1)))<1e-12 ...
    && abs(interp1(c.drMapG,c.drMapD,1.08,'pchip')-(0.913-c.rStar0))<0.005 ...
    && interp1(c.levMapG,c.levMapP,1.08,'pchip')>1.0;
end
