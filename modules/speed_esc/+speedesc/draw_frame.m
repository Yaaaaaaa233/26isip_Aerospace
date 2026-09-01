function draw_frame(ax,L,c,index,showTruth)
index=min(max(round(index),1),height(L)); sl=1:index;
for k=1:4, cla(ax(k)); hold(ax(k),'on'); grid(ax(k),'on'); ax(k).FontName='Microsoft YaHei'; ax(k).FontSize=11; end
if showTruth
    speeds=linspace(c.lower,c.upper,350); star=L.trueOptimum(index);
    plot(ax(1),speeds,speedesc.power_map(speeds,star,c),'Color',[.25 .3 .35],'LineWidth',1.4,'DisplayName','评价器曲线');
    plot(ax(1),star,speedesc.power_map(star,star,c),'p','MarkerSize',10,'MarkerFaceColor',[.15 .55 .32],...
        'Color',[.15 .55 .32],'DisplayName','评价器最优点');
end
plot(ax(1),L.pairedSpeed(sl),L.measuredPower(sl),'.','Color',[.16 .48 .72],'MarkerSize',4,'DisplayName','时间对齐反馈');
plot(ax(1),L.pairedSpeed(index),L.measuredPower(index),'o','MarkerFaceColor',[.8 .3 .12],...
    'MarkerEdgeColor',[.8 .3 .12],'DisplayName','当前收到的测量');
xlim(ax(1),[c.lower c.upper]); xlabel(ax(1),'速度 / m/s'); ylabel(ax(1),'归一化功率 J');
title(ax(1),'功率曲线与反馈样本'); legend(ax(1),'Location','northwest','FontSize',9);
plot(ax(2),L.time(sl),L.center(sl),'Color',[.12 .55 .36],'LineWidth',1.4,'DisplayName','参考中心');
plot(ax(2),L.time(sl),L.appliedReference(sl),'Color',[.85 .4 .1],'DisplayName','本步速度指令');
plot(ax(2),L.time(sl),L.actualSpeed(sl),'Color',[.15 .4 .78],'LineWidth',1.2,'DisplayName','实际速度');
if showTruth, plot(ax(2),L.time(sl),L.trueOptimum(sl),'k--','DisplayName','评价器最优速度'); end
xlim(ax(2),[0 c.duration]); ylim(ax(2),[c.lower-.3 c.upper+.3]);
xlabel(ax(2),'时间 / s'); ylabel(ax(2),'速度 / m/s'); title(ax(2),'参考值与实际响应');
legend(ax(2),'Location','best','FontSize',9);
plot(ax(3),L.time(sl),L.measuredPower(sl),'Color',[.52 .68 .82],'DisplayName','收到的测量功率');
if showTruth
    plot(ax(3),L.time(sl),L.truePower(sl),'Color',[.2 .3 .4],'LineWidth',1.2,'DisplayName','对象当前真值');
    plot(ax(3),L.time(sl),L.optimalPower(sl),'k--','DisplayName','离线最优基准');
end
xlim(ax(3),[0 c.duration]); xlabel(ax(3),'时间 / s'); ylabel(ax(3),'归一化功率 J');
title(ax(3),'测量反馈与评价基准'); legend(ax(3),'Location','best','FontSize',9);
rawName='窗口回归斜率'; if strcmp(c.method,'demod'), rawName='同频解调输出'; end
plot(ax(4),L.time(sl),L.rawGradient(sl),'Color',[.7 .72 .74],'DisplayName',rawName);
plot(ax(4),L.time(sl),L.gradient(sl),'Color',[.62 .18 .24],'LineWidth',1.4,'DisplayName','低通后的梯度估计');
yline(ax(4),0,':','HandleVisibility','off'); xlim(ax(4),[0 c.duration]);
xlabel(ax(4),'时间 / s'); ylabel(ax(4),'归一化功率 / (m/s)');
title(ax(4),'梯度估计'); legend(ax(4),'Location','best','FontSize',9);
end
