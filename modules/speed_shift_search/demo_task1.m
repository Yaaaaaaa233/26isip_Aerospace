function demo_task1()
%DEMO_TASK1 任务1演示出图(保存到 results/task1/task1_demo.png)。
% 图1 六算法静态场景收敛对比；图2 tracker对dx跳变的再跟踪过程；
% 图3 搜索能耗口径(开关=开)横评；图4 tracker功率轨迹与真值最优。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results','task1'); if ~exist(folder,'dir'), mkdir(folder); end
c=task1.config();

% --- 数据 ---
names={'grid','ternary','golden','brent','tracker','esc'};
scnStatic=task1.scenario('static',c);
logs=cell(1,numel(names));
for k=1:numel(names), logs{k}=task1.run_algorithm(names{k},scnStatic,c); end
scnJump=task1.scenario('jumpUp',c);
[logT,infoT]=task1.run_algorithm('tracker',scnJump,c);
mT=task1.evaluate(logT,scnJump,c);
cOn=task1.config('energyAccounting',true);
scnJumpOn=task1.scenario('jumpUp',cOn);
energy=nan(1,numel(names));
for k=1:numel(names)
    lg=task1.run_algorithm(names{k},scnJumpOn,cOn);
    energy(k)=task1.evaluate(lg,scnJumpOn,cOn).energyExcessPercent;
end

% --- 作图 ---
f=figure('Position',[40 40 1250 820],'Color','w','Visible','off');
tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');

ax=nexttile; hold(ax,'on'); grid(ax,'on');
style={':','-.','--','-','-','-'};
for k=1:numel(names)
    plot(ax,logs{k}.step,logs{k}.estimate,style{k},'LineWidth',1.2,...
        'DisplayName',names{k});
end
yline(ax,6.3,'r--','v* 真值','LineWidth',1.3,'HandleVisibility','off');
xlim(ax,[0 c.duration]); ylim(ax,[0 14]);
xlabel(ax,'评估步'); ylabel(ax,'速度估计 v_{hat} / m s^{-1}');
title(ax,'图1 静态场景: 各算法收敛速度(越早贴住红线越优)');
legend(ax,'Location','northeast','FontSize',8);

ax=nexttile; hold(ax,'on'); grid(ax,'on');
plotTag(ax,logT,'search','.b','搜索评估');
plotTag(ax,logT,'hold','ob','锁定平飞');
plotTag(ax,logT,'probe','.g','两点复探');
plot(ax,logT.step,logT.optimumTrue,'r--','LineWidth',1.4,'DisplayName','v* 真值(第120步跳变)');
for rt=infoT.researchTimes, xline(ax,rt,':k','HandleVisibility','off'); end
xlim(ax,[0 c.duration]); ylim(ax,[0 12]);
xlabel(ax,'评估步'); ylabel(ax,'速度 / m s^{-1}');
title(ax,sprintf('图2 tracker 对dx跳变的再跟踪(重搜%d次,恢复%.0f步)',...
    infoT.researchCount,mT.recoverySteps));
legend(ax,'Location','south','FontSize',8);

ax=nexttile; hold(ax,'on'); grid(ax,'on');
bar(ax,1:numel(names),energy,'FaceColor',[.30 .55 .80]);
set(ax,'XTick',1:numel(names),'XTickLabel',names);
ylim(ax,[0 max(energy)*1.25+0.1]);
ylabel(ax,'全程能量超额 / %');
for k=1:numel(names)
    text(ax,k-0.35,energy(k)+0.3,sprintf('%.2f%%',energy(k)),'FontSize',8);
end
title(ax,{'图3 搜索能耗横评(dx跳变场景,开关=开)',...
    ['开关=关时能耗列记NaN、不参与验收,只看图1/图2的定位指标']});

ax=nexttile; hold(ax,'on'); grid(ax,'on');
plot(ax,logT.step,logT.powerTrue,'b-','LineWidth',.9,'DisplayName','真实功率(评价侧)');
plot(ax,logT.step,logT.minPowerTrue,'r--','LineWidth',1.3,'DisplayName','离线最优功率');
xlim(ax,[0 c.duration]);
xlabel(ax,'评估步'); ylabel(ax,'P / P_{hover}');
title(ax,sprintf('图4 tracker 功率轨迹(稳态超额%.3f%%)',mT.steadyRegretPercent));
legend(ax,'Location','north','FontSize',8);

saveas(f,fullfile(folder,'task1_demo.png'));
close(f);
fprintf('演示图已保存: %s\n',fullfile(folder,'task1_demo.png'));
end

    function plotTag(ax,logT,tag,style,label)
        hit=strcmp(logT.tag,tag);
        plot(ax,logT.step(hit),logT.speed(hit),style,'MarkerSize',4,...
            'LineStyle','none','DisplayName',label);
    end
