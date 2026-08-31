function draw_frame(ax,log,c,k,showTruth)
%DRAW_FRAME Evaluator-only visualization; nothing flows back to the policy.
k=min(max(1,k),height(log)); prefix=1:k;
ix=unique(round(linspace(1,k,min(k,1200))));
t=log.time(ix); colors=[0.12 0.40 0.70;0.83 0.30 0.18;0.12 0.55 0.38;0.48 0.35 0.61];
for j=1:4
    if j==4 && numel(ax(j).YAxis)>1
        yyaxis(ax(j),'left'); cla(ax(j));
        yyaxis(ax(j),'right'); cla(ax(j)); yyaxis(ax(j),'left');
    else
        cla(ax(j));
    end
    hold(ax(j),'on'); grid(ax(j),'on');
    set(ax(j),'FontName','Microsoft YaHei','FontSize',10,'Color','white','Box','on');
end
x=linspace(c.lower,c.upper,301);
if showTruth
    plot(ax(1),x,ratioesc.power_map(x,log.optimum(k),c),'Color',colors(1,:),'LineWidth',1.5,...
        'DisplayName','完整曲线（评价器）');
    plot(ax(1),log.optimum(k),1,'d','Color',colors(3,:),'MarkerFaceColor',colors(3,:),...
        'DisplayName','真实最优点（评价器）');
end
scatter(ax(1),log.ratio(ix),log.measuredPower(ix),7,[0.63 0.72 0.80],'filled',...
    'DisplayName','历史测量');
plot(ax(1),log.ratio(k),log.measuredPower(k),'o','MarkerSize',7,...
    'Color',colors(2,:),'MarkerFaceColor',colors(2,:),'DisplayName','当前测量');
xlim(ax(1),[c.lower c.upper]); xlabel(ax(1),'实际转速比 eta = 上桨 / 下桨');
ylabel(ax(1),'归一化功率 J'); title(ax(1),'工作点与功率');
legend(ax(1),'Location','best','FontSize',8);
plot(ax(2),t,log.center(ix),'Color',colors(1,:),'LineWidth',1.2,'DisplayName','参考中心 / RL动作');
plot(ax(2),t,log.reference(ix),'Color',colors(4,:),'LineWidth',0.9,'DisplayName','执行参考');
plot(ax(2),t,log.ratio(ix),'Color',colors(2,:),'LineWidth',1.2,'DisplayName','实际转速比');
if showTruth
    plot(ax(2),t,log.optimum(ix),'--','Color',colors(3,:),'DisplayName','真实最优点（评价器）');
end
xlim(ax(2),[0 c.duration]); ylim(ax(2),[c.lower-0.02 c.upper+0.02]);
xlabel(ax(2),'仿真时间 / s'); ylabel(ax(2),'转速比'); title(ax(2),'参考与执行响应');
legend(ax(2),'Location','best','FontSize',8);
plot(ax(3),t,log.measuredPower(ix),'Color',[0.67 0.74 0.81],'DisplayName','测量功率');
if showTruth
    plot(ax(3),t,log.truePower(ix),'Color',colors(2,:),'LineWidth',1.2,'DisplayName','真实功率（评价器）');
    plot(ax(3),t,log.offlinePower(ix),'--','Color',colors(3,:),'DisplayName','离线最优基准');
end
window=max(1,round(10/c.Ts)); smoothed=movmean(log.measuredPower(prefix),[window-1 0]);
plot(ax(3),t,smoothed(ix),'Color',colors(1,:),'LineWidth',1.2,'DisplayName','测量10 s均值');
xlim(ax(3),[0 c.duration]); xlabel(ax(3),'仿真时间 / s'); ylabel(ax(3),'归一化功率 J');
title(ax(3),'功率反馈'); legend(ax(3),'Location','best','FontSize',8);
yyaxis(ax(4),'left');
plot(ax(4),t,log.dither(ix),'Color',colors(1,:),'DisplayName','微扰');
plot(ax(4),t,log.highpass(ix),'Color',colors(3,:),'DisplayName','高通功率');
ylabel(ax(4),'微扰 / 高通信号');
yyaxis(ax(4),'right');
plot(ax(4),t,log.demodulated(ix),'Color',[0.79 0.72 0.82],'DisplayName','解调信号');
plot(ax(4),t,log.gradient(ix),'Color',colors(2,:),'LineWidth',1.2,'DisplayName','低通梯度估计');
ylabel(ax(4),'解调 / 梯度估计'); xlabel(ax(4),'仿真时间 / s');
xlim(ax(4),[0 c.duration]); title(ax(4),'微扰如何变成调整方向');
legend(ax(4),'Location','best','FontSize',8);
end
