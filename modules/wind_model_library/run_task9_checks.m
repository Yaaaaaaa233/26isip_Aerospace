function summary = run_task9_checks()
%RUN_TASK9_CHECKS 任务9检查：风场模型库(七种) + 空速语义 + 曲线case回归 + 风场×策略横比。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
unit=runtests(fullfile(root,'tests_task9.m'));
fprintf('单元测试：%d/%d 通过\n',sum([unit.Passed]),numel(unit));
wind={'windAmp',2,'windOmega',0.08,'windBias',3,...
      'windAmpY',1.5,'windOmegaY',0.13,'windBiasY',1};
policies={'openloop','tracker','esc','spsa','bayes','qnewton','gtrack','est','known'};
% ---- A: 七种风场 × 九策略 短程冒烟矩阵(60步, 2种子) ----
kinds={'const','sin','square','triangle','turb','composite','sector'};
rows=cell(0,7); smokeOK=true;
for kk=1:numel(kinds)
    for name=policies
        ex=zeros(1,2); acc=0; stp=zeros(1,2);
        for i=1:2
            c=w9.config('seed',10+i,'duration',60,'tailSteps',5,'windKind',kinds{kk},wind{:});
            [log,~]=w9.run_algorithm(name{1},w9.scenario('static',c),c);
            ex(i)=w9.mop_moe(log,c).energyExcessPercent;
            acc=max(acc,max(log.accelMax)); stp(i)=height(log);
            smokeOK=smokeOK && (stp(i)==60) && all(isfinite(log.powerMeas));
        end
        rows(end+1,:)={kinds{kk},name{1},mean(ex),max(ex),acc,stp(1),true}; %#ok<AGROW>
    end
end
smoke=cell2table(rows,'VariableNames',{'WindKind','Policy','ExcessMean',...
    'ExcessMax','MaxAccelUsed','Steps','EnergyOn'});
writetable(smoke,fullfile(folder,'wind_kinds_smoke.csv'),'Encoding','UTF-8');
% ---- B: 主口径横比 sin/composite/sector × {openloop,qnewton,known} × 3 case × 3种子(全程400步) ----
mainKinds={'sin','composite','sector'};
mainPols={'openloop','qnewton','known'};
rows=cell(0,8);
for kk=1:numel(mainKinds)
    for name=mainPols
        for caseV=[0.95 0.90 0.85]
            ex=zeros(1,3); mo=ex; acc=0; stp=0;
            for i=1:3
                c=w9.config('seed',10+i,'curveCase',caseV,...
                    'windKind',mainKinds{kk},wind{:});
                [log,~]=w9.run_algorithm(name{1},w9.scenario('static',c),c);
                m=w9.mop_moe(log,c);
                ex(i)=m.energyExcessPercent; mo(i)=m.MOE_energy;
                acc=max(acc,max(log.accelMax)); stp=height(log);
            end
            rows(end+1,:)={mainKinds{kk},name{1},caseV,mean(mo),mean(ex),std(ex),acc,stp}; %#ok<AGROW>
        end
    end
end
main=cell2table(rows,'VariableNames',{'WindKind','Policy','CurveCase','MOE_energy',...
    'EnergyExcessPercent','ExcessStd','MaxAccelUsed','Steps'});
writetable(main,fullfile(folder,'kinds_comparison.csv'),'Encoding','UTF-8');
% ---- 物理口径核验: 空速=|地速+风| 与 地速最优闭式(检查脚本独立复算) ----
c=w9.config('seed',11,'duration',30,'tailSteps',5,wind{:});
scn=w9.scenario('static',c);
plant=w9.make_plant(scn,c);
for k=1:30, plant.q(6.3,'hold'); plant.amendEstimate(6.3); end
lg=plant.table();
psi=deg2rad(lg.headingDeg);
uExp=hypot(lg.speed.*cos(psi)+lg.windX, lg.speed.*sin(psi)+lg.windY);
physOK=max(abs(lg.airspeed-uExp))<1e-9;
% ---- 门槛 ----
kn=@(kk) strcmp(main.WindKind,mainKinds{kk}) & strcmp(main.Policy,'known');
ol=@(kk) strcmp(main.WindKind,mainKinds{kk}) & strcmp(main.Policy,'openloop');
knownOK=all(arrayfun(@(kk) mean(main.EnergyExcessPercent(kn(kk)))<1.5,1:3));
infoOK=all(arrayfun(@(kk) mean(main.EnergyExcessPercent(ol(kk)))-mean(main.EnergyExcessPercent(kn(kk)))>2.0,1:3));
checks=[...
    struct('item','单元测试全绿(风场模型库/空速语义/case锚点/执行链回归)','pass',sum([unit.Passed])==numel(unit)),...
    struct('item','七种风场×九策略冒烟: 全部预算走满、测量有限、|dv/dt|<=2','pass',smokeOK && all(smoke.MaxAccelUsed<=2+1e-9) && all(smoke.Steps==60)),...
    struct('item','空速语义核验: 日志空速=|地速矢量+风矢量|(max差<1e-9)','pass',physOK),...
    struct('item','sin/composite/sector 下 known oracle 超额<1.5%(信息上界)','pass',knownOK),...
    struct('item','三种风场下 known 较 openloop 信息价值>2pp','pass',infoOK)];
summary=struct('unitPassed',sum([unit.Passed]),'unitTotal',numel(unit),...
    'gatesPassed',sum([checks.pass]),'gatesTotal',numel(checks));
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
cl=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['# 任务9检查：七种可选风场模型库 × 空速-地速语义\n\n生成时间：%s\n\n'],datestr(now,31));
fprintf(fid,'- 单元测试：%d/%d。\n- 检查门槛：%d/%d。\n\n',summary.unitPassed,summary.unitTotal,...
    summary.gatesPassed,summary.gatesTotal);
fprintf(fid,['## 风场模型库(wind_field.m)\n\nconst恒定 / sin双正弦(任务4-8原口径) / square软边方波 / '...
    'triangle三角 / turb OU湍流 / composite复合(慢变+湍流, 最贴近实际) / sector扇区(随航向)。\n'...
    '湍流序列以独立种子流(seed+917)预生成, 确定性可复现。\n\n']);
fprintf(fid,['## 速度语义(用户口径)\n\n空速=地速+风速(矢量和); 功率由空速决定 → 空速-功率标定曲线'...
    '不随风移动, 地速-功率曲线随风平移; 仪表盘显示地速; 日志新增 airspeed/windX/windY 评价列。\n\n']);
fprintf(fid,'## 主口径横比(3风场×3策略×3case, 3种子均值超额%%)\n\n');
fprintf(fid,'| 风场 | 策略 | case95%% | case90%% | case85%% |\n|---|---|---:|---:|---:|\n');
for kk=1:numel(mainKinds)
    for ii=1:numel(mainPols)
        sel=strcmp(main.WindKind,mainKinds{kk}) & strcmp(main.Policy,mainPols{ii});
        vals=main.EnergyExcessPercent(sel);
        fprintf(fid,'| %s | %s | %.2f | %.2f | %.2f |\n',...
            mainKinds{kk},mainPols{ii},vals(1),vals(2),vals(3));
    end
end
fprintf(fid,'\n| 门槛 | 结果 |\n|---|---|\n');
for k=1:numel(checks)
    v='未过'; if checks(k).pass, v='通过'; end
    fprintf(fid,'| %s | %s |\n',checks(k).item,v);
end
fprintf(fid,'\n冒烟矩阵见 wind_kinds_smoke.csv; 横比明细见 kinds_comparison.csv。\n');
fprintf(fid,['\n结论边界: 全部结果为虚拟/代理对象口径(AGENTS.md红线3), 不支持真实X8节能表述; '...
    'known为已知风oracle参照(非因果), 不参与黑箱横比。\n']);
fprintf('检查门槛：%d/%d\n',summary.gatesPassed,summary.gatesTotal);
if summary.gatesPassed<summary.gatesTotal, warning('w9:Checks','Some gates missed.'); end
end
