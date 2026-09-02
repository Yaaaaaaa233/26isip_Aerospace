function fig = launch_wind_demo(visible)
%LAUNCH_WIND_DEMO 环境风场研究模块面板：控制台(调度) × 飞机模型 × 环境模型。
% TASKS_1_5_ROUTE §3-5 交付口径的动态演示：
%   环境：统一风场(恒定/正弦/双正交)×圆周盘旋；
%   飞机：速度+功率双表盘(黑箱, 只见测量)；
%   控制台：信息结构调度策略(已知风/在线估计风/不知风/匀速对照/恒飞V*)
%           与解析最优 v*(t)、DP调度对照。
if nargin<1, visible='on'; end
root=fileparts(mfilename('fullpath')); addpath(root);
fig=uifigure('Name','环境风场研究模块：解析调度×在线风估计×三档信息结构(动态演示)',...
    'Position',[40 30 1500 960],'Color',[.96 .97 .98],'Visible',visible,...
    'AutoResizeChildren','off');
outer=uigridlayout(fig,[3 2]); outer.RowHeight={44,'1x',28}; outer.ColumnWidth={330,'1x'};
outer.Padding=[12 10 12 10]; outer.RowSpacing=10;
header=uilabel(outer,'Text','环境风场研究模块 | 空速物理 P=P0(|v·t̂+w|) × 解析调度/DP验证 × 风速信息价值',...
    'FontName','Microsoft YaHei','FontSize',16,'FontWeight','bold'); put(header,1,[1 2]);
left=uigridlayout(outer,[6 1]); put(left,2,1);
left.RowHeight={38,'1x',150,165,30,'1x'};
left.Padding=[0 0 0 0]; left.RowSpacing=8;
form=uipanel(left,'BorderType','none'); put(form,1,1);
g=uigridlayout(form,[12 2]); g.ColumnWidth={150,'1x'};
g.RowHeight=repmat({30},1,12); g.Padding=[0 0 8 0]; g.RowSpacing=7;
windMode=choice(g,'风场模式',1,{'const恒定风','sin正弦风','dual双正交风'},...
    {'const','sin','dual'},'dual');
policyC=choice(g,'信息结构策略',2,{'已知风(上界)','在线估计风','不知风(匀速搜索)',...
    '离线最优匀速','恒飞V*'},{'known','online','blind','uniform','fixed'},'online');
windSpeed=number(g,'恒定风速 / m·s⁻¹',3,3.0,[0 10]);
windA=number(g,'x幅值A / m·s⁻¹',4,2.0,[0 10]);
windW1=number(g,'x角频率ω1',5,0.08,[0 2]);
windB=number(g,'x偏置B / m·s⁻¹',6,3.0,[0 10]);
windC=number(g,'y幅值C / m·s⁻¹',7,1.5,[0 10]);
windW2=number(g,'y角频率ω2',8,0.13,[0 2]);
windD=number(g,'y偏置D / m·s⁻¹',9,1.0,[0 10]);
circleT=number(g,'盘旋周期 / s',10,80,[10 400]);
noise=number(g,'测量噪声σ(相对)',11,0.005,[0 0.03]);
truth=uicheckbox(g,'Text','显示评价器真值(v*/Pmin)','Value',true); put(truth,12,[1 2]);
actions=uigridlayout(left,[3 4]); put(actions,3,1); actions.Padding=[0 0 8 0];
actions.RowHeight={34,34,34}; actions.RowSpacing=7;
play=uibutton(actions,'Text','播放'); put(play,1,1);
pauseBtn=uibutton(actions,'Text','暂停'); put(pauseBtn,1,2);
reset=uibutton(actions,'Text','重置'); put(reset,1,3);
finish=uibutton(actions,'Text','末帧'); put(finish,1,4);
exportPng=uibutton(actions,'Text','导出PNG'); put(exportPng,2,1);
loadReportBtn=uibutton(actions,'Text','载入验收报告'); put(loadReportBtn,2,[2 3]);
clearLogBtn=uibutton(actions,'Text','清空日志'); put(clearLogBtn,2,4);
speedLabel=uilabel(actions,'Text','播放速度: 1.00x','FontName','Microsoft YaHei'); put(speedLabel,3,[1 2]);
speedSlider=uislider(actions,'Limits',[0.5 8],'Value',1,'MajorTicks',[.5 1 2 4 8],...
    'MajorTickLabels',{'0.5x','1x','2x','4x','8x'}); put(speedSlider,3,[3 4]);
speedSlider.ValueChangedFcn=@(~,ev) setSpeed(ev.Value);
% --- MOP/MOE 结果卡片(日志栏上方) ---
resultCard=uipanel(left,'Title','★ MOP/MOE 评价结果(任务窗终点)','FontName','Microsoft YaHei',...
    'FontSize',11,'ForegroundColor',[.62 .08 .08],'HighlightColor',[.62 .08 .08]);
put(resultCard,4,1);
rg=uigridlayout(resultCard,[5 2]); rg.RowHeight={30,24,24,24,24};
rg.ColumnWidth={'1x','1x'}; rg.Padding=[8 2 8 2]; rg.RowSpacing=1;
labOverallT=uilabel(rg,'Text','MOE 续航能效(=Emin/E实际)','FontName','Microsoft YaHei',...
    'FontSize',9,'FontColor',[.25 .25 .25]); put(labOverallT,1,1);
labOverall=uilabel(rg,'Text','—','FontName','Microsoft YaHei','FontSize',15,...
    'FontWeight','bold','HorizontalAlignment','right'); put(labOverall,1,2);
labOverall.FontColor=[.0 .45 .2];
labET=uilabel(rg,'Text','能量超额% (全程)','FontName','Microsoft YaHei','FontSize',9); put(labET,2,1);
labE=uilabel(rg,'Text','—','FontName','Microsoft YaHei','FontSize',11,'FontWeight','bold',...
    'HorizontalAlignment','right'); put(labE,2,2);
labRT=uilabel(rg,'Text','尾段功率超额%','FontName','Microsoft YaHei','FontSize',9); put(labRT,3,1);
labR=uilabel(rg,'Text','—','FontName','Microsoft YaHei','FontSize',11,'FontWeight','bold',...
    'HorizontalAlignment','right'); put(labR,3,2);
labVT=uilabel(rg,'Text','调度偏差 rms/max (m/s)','FontName','Microsoft YaHei','FontSize',9); put(labVT,4,1);
labV=uilabel(rg,'Text','—','FontName','Microsoft YaHei','FontSize',11,'FontWeight','bold',...
    'HorizontalAlignment','right'); put(labV,4,2);
labWT=uilabel(rg,'Text','风估计误差(末段均值, m/s)','FontName','Microsoft YaHei','FontSize',9); put(labWT,5,1);
labW=uilabel(rg,'Text','—','FontName','Microsoft YaHei','FontSize',11,'FontWeight','bold',...
    'HorizontalAlignment','right'); put(labW,5,2);
readout=uilabel(left,'Text','','WordWrap','on','FontName','Microsoft YaHei'); put(readout,5,1);
logBox=uitextarea(left,'Editable','off','FontName','Microsoft YaHei','FontSize',9); put(logBox,6,1);
plots=uigridlayout(outer,[3 2]); put(plots,2,2); plots.Padding=[0 0 0 0];
plots.RowHeight={'1x','1x',250}; plots.ColumnWidth={'1x','1x'}; plots.RowSpacing=14; plots.ColumnSpacing=18;
ax=gobjects(1,4); for k=1:4, ax(k)=uiaxes(plots); disableDefaultInteractivity(ax(k)); ax(k).Toolbar.Visible='off'; end
put(ax(1),1,1); put(ax(2),1,2); put(ax(3),2,1); put(ax(4),2,2);
status=uilabel(outer,'Text','就绪','FontName','Microsoft YaHei'); put(status,3,2);
clock=timer('ExecutionMode','fixedSpacing','Period',.15,'BusyMode','drop','TimerFcn',@tick);
L=table(); info=[]; c=[]; cursor=1; dirty=true; h=struct();
cumExcess=[];
% ---- 飞机模型 & 环境模型 模块窗口 ----
airPanel=uipanel(plots,'Title','飞机模型：速度+功率双表盘(黑箱仪表)','FontName','Microsoft YaHei',...
    'ForegroundColor',[.15 .3 .6],'HighlightColor',[.15 .3 .6]);
airPanel.Layout.Row=3; airPanel.Layout.Column=1;
ag=uigridlayout(airPanel,[4 2]); ag.RowHeight={170,18,18,40}; ag.ColumnWidth={'1x','1x'};
ag.Padding=[6 6 6 4]; ag.RowSpacing=4;
gSpeed=uigauge(ag,'Limits',[0 20]); put(gSpeed,1,1);
labSp=uilabel(ag,'Text','速度表盘 / m·s-1','FontName','Microsoft YaHei','FontSize',9,...
    'HorizontalAlignment','center'); put(labSp,2,1);
gPower=uigauge(ag,'Limits',[0.85 1.1]); put(gPower,1,2);
labPw=uilabel(ag,'Text','功率表盘(测量)','FontName','Microsoft YaHei','FontSize',9,...
    'HorizontalAlignment','center'); put(labPw,2,2);
labMetrics=uilabel(ag,'Text','','FontName','Microsoft YaHei','FontSize',10,...
    'HorizontalAlignment','center'); put(labMetrics,3,[1 2]);
btnAirSize=uibutton(ag,'Text','放大 ⤢'); put(btnAirSize,5,[1 2]);
envPanel=uipanel(plots,'Title','环境模型：圆周航迹×风矢量(绿=x向风,紫=合成)','FontName','Microsoft YaHei',...
    'ForegroundColor',[.1 .45 .25],'HighlightColor',[.1 .45 .25]);
envPanel.Layout.Row=3; envPanel.Layout.Column=2;
eg=uigridlayout(envPanel,[2 1]); eg.RowHeight={'1x',26}; eg.Padding=[4 4 4 2];
axEnv=uiaxes(eg); disableDefaultInteractivity(axEnv); axEnv.Toolbar.Visible='off';
title(axEnv,'航迹 + 风矢量(绿=风系x分量, 紫=合成w)','FontSize',8);
put(axEnv,1,1);
% 注意: uiaxes中先建text(箭头字符)再建line(平台怪癖反向破坏)
hTipX=text(axEnv,0,0,char(10132),'FontName','Segoe UI Symbol','FontSize',12,...
    'Color',[.0 .55 .25],'HorizontalAlignment','center','VerticalAlignment','middle');
hTipR=text(axEnv,0,0,char(10132),'FontName','Segoe UI Symbol','FontSize',14,...
    'Color',[.5 .2 .7],'HorizontalAlignment','center','VerticalAlignment','middle');
hTrail=line(axEnv,nan,nan,'Color',[.2 .4 .8],'LineWidth',.8,'DisplayName','航迹');
hPlane=line(axEnv,nan,nan,'Color',[.85 .18 .18],'Marker','>','MarkerFaceColor',...
    [.85 .18 .18],'MarkerSize',11,'LineStyle','none','DisplayName','飞机位置');
hWindX=line(axEnv,nan,nan,'Color',[.0 .55 .25],'LineWidth',2.2,'DisplayName','风矢量w(t)');
hWindR=line(axEnv,nan,nan,'Color',[.5 .2 .7],'LineWidth',2.6,'DisplayName','合成风(双正交)');
hHome=line(axEnv,nan,nan,'Color',[.4 .4 .4],'Marker','s','MarkerSize',8,...
    'LineStyle','none','DisplayName','盘旋中心');
hEnvTxt1=text(axEnv,0,0,'','FontName','Microsoft YaHei','FontSize',9,'Color',[.2 .2 .55]);
hEnvTxt2=text(axEnv,0,0,'','FontName','Microsoft YaHei','FontSize',9,'Color',[.3 .3 .3]);
hEnvTxt1.HorizontalAlignment='center'; hEnvTxt2.HorizontalAlignment='center';
legend(axEnv,'Location','southoutside','Orientation','horizontal','FontSize',7);
btnEnvSize=uibutton(eg,'Text','放大 ⤢'); put(btnEnvSize,2,1);
% 静态曲线
hold(ax(1),'on'); hold(ax(2),'on'); hold(ax(3),'on'); hold(ax(4),'on');
h.vCmd=line(ax(1),nan,nan,'Color',[.2 .4 .8],'LineWidth',1.4,'DisplayName','v_cmd 执行调度');
h.vstar=line(ax(1),nan,nan,'Color',[.85 .18 .18],'LineStyle','--','LineWidth',1.2,'DisplayName','v*(t) 解析最优');
h.vU=line(ax(1),nan,nan,'Color',[.55 .3 .75],'LineStyle',':','LineWidth',1.4,'DisplayName','最优匀速对照');
xlabel(ax(1),'t / s'); ylabel(ax(1),'地速 / m·s^{-1}');
title(ax(1),'速度调度：策略 vs 解析最优'); legend(ax(1),'Location','northeast','FontSize',7);
h.pTrue=line(ax(2),nan,nan,'Color',[.2 .3 .4],'LineWidth',.9,'DisplayName','P_true');
h.pMin=line(ax(2),nan,nan,'Color',[.85 .18 .18],'LineStyle','--','LineWidth',1.1,'DisplayName','P_min(t) 可达下界');
h.pMeas=line(ax(2),nan,nan,'Color',[.55 .3 .7],'Marker','.','LineStyle','none',...
    'MarkerSize',6,'DisplayName','P_meas 带噪');
xlabel(ax(2),'t / s'); ylabel(ax(2),'功率(代理)');
title(ax(2),'功率轨迹'); legend(ax(2),'Location','northeast','FontSize',7);
h.wX=line(ax(3),nan,nan,'Color',[.0 .55 .25],'LineWidth',1.1,'DisplayName','w_x 真值');
h.wY=line(ax(3),nan,nan,'Color',[.85 .45 .1],'LineWidth',1.1,'DisplayName','w_y 真值');
h.wXe=line(ax(3),nan,nan,'Color',[.0 .55 .25],'LineStyle',':','LineWidth',1.5,'DisplayName','ŵ_x 估计');
h.wYe=line(ax(3),nan,nan,'Color',[.85 .45 .1],'LineStyle',':','LineWidth',1.5,'DisplayName','ŵ_y 估计');
xlabel(ax(3),'t / s'); ylabel(ax(3),'风 / m·s^{-1}');
title(ax(3),'风与在线估计'); legend(ax(3),'Location','northeast','FontSize',7);
h.cum=line(ax(4),nan,nan,'Color',[.8 .45 .1],'LineWidth',1.3);
xlabel(ax(4),'t / s'); title(ax(4),'累计能量超额 / %');
ud=struct('controls',struct('windMode',windMode,'policy',policyC,'windSpeed',windSpeed,...
    'windA',windA,'windW1',windW1,'windB',windB,'windC',windC,'windW2',windW2,...
    'windD',windD,'circleT',circleT,'noise',noise,'truth',truth,...
    'play',play,'pause',pauseBtn,'reset',reset,'finish',finish,...
    'exportPng',exportPng,'speed',speedSlider),...
    'prepare',@prepare,'play',@playback,'pause',@stopPlayback,'finish',@toEnd,...
    'getLog',@getLog,'getCursor',@getCursor,'timer',clock,'exportPng',@exportCurrent,...
    'logMsg',@logMsg,'loadReport',@loadReport,'clearLog',@clearLog,...
    'resultCard',struct('overall',labOverall,'energy',labE,'regret',labR,...
    'verr',labV,'west',labW),'airPanel',airPanel,'envPanel',envPanel);
fig.UserData=ud;
for cn={windMode,policyC,windSpeed,windA,windW1,windB,windC,windW2,windD,circleT,noise}
    cn{1}.ValueChangedFcn=@changed;
end
truth.ValueChangedFcn=@(~,~)redraw();
play.ButtonPushedFcn=@playback; pauseBtn.ButtonPushedFcn=@stopPlayback;
reset.ButtonPushedFcn=@prepare; finish.ButtonPushedFcn=@toEnd;
exportPng.ButtonPushedFcn=@exportCurrent;
loadReportBtn.ButtonPushedFcn=@loadReport; clearLogBtn.ButtonPushedFcn=@clearLog;
btnAirSize.ButtonPushedFcn=@(~,~)toggleSize('air');
btnEnvSize.ButtonPushedFcn=@(~,~)toggleSize('env');
fig.CloseRequestFcn=@closeApp;
resizeLayout(); logMsg('环境风场研究模块就绪 | 空速物理+解析调度+DP验证+三档信息结构');
logMsg('提示: 切换信息结构策略对比 已知风/在线估计/不知风 的能耗差异(风速信息价值)');
if exist(fullfile(root,'results','report.md'),'file'), loadReport(); end
prepare();

    function setSpeed(val)
        speedLabel.Text=sprintf('播放速度: %.2fx',val);
        if strcmp(clock.Running,'on'), clock.Period=.15/val; end
    end
    function toggleSize(which)
        if strcmp(which,'air')
            if airPanel.Layout.Row(1)==1
                airPanel.Layout.Row=3; airPanel.Layout.Column=1; btnAirSize.Text='放大 ⤢';
            else
                airPanel.Layout.Row=[1 3]; airPanel.Layout.Column=[1 2]; btnAirSize.Text='还原 ⤡';
            end
        else
            if envPanel.Layout.Row(1)==1
                envPanel.Layout.Row=3; envPanel.Layout.Column=2; btnEnvSize.Text='放大 ⤢';
            else
                envPanel.Layout.Row=[1 3]; envPanel.Layout.Column=[1 2]; btnEnvSize.Text='还原 ⤡';
            end
        end
        drawnow;
    end
    function resizeLayout(varargin)
        bodyHeight=max(440,fig.InnerPosition(4)-112);
        outer.RowHeight={44,bodyHeight,28};
        avail=max(500,bodyHeight)-423;
        formH=max(230,round(0.45*avail)); logH=max(150,avail-formH);
        left.RowHeight={38,formH,150,165,30,logH};
    end
    function changed(varargin)
        stopPlayback(); dirty=true; status.Text='参数已更改，按"重置"或"播放"生效';
    end
    function buildConfig()
        c=wind.config('windMode',windMode.Value,...
            'windSpeed',windSpeed.Value,...
            'windAmp',windA.Value,'windOmega',windW1.Value,'windBias',windB.Value,...
            'windAmpY',windC.Value,'windOmegaY',windW2.Value,'windBiasY',windD.Value,...
            'circlePeriod',circleT.Value,'noiseSigma',noise.Value,'seed',11);
    end
    function prepare(varargin)
        stopPlayback();
        try
            buildConfig();
            [L,info]=wind.run_policy(policyC.Value,c);
            sa=wind.analytic_sched(c,L.time);
            cumExcess=100*cumsum(L.powerTrue-sa.Pmin)./cumsum(sa.Pmin);
            uB=wind.uniform_baseline(c);
            info.vU=uB.vU;
            cursor=1; dirty=false; redraw(); status.Text='就绪';
            logMsg(sprintf('重置完成: 模式=%s 策略=%s 风包络=%.2f m/s 可行=%d/%d | vU=%.2f',...
                c.windMode,policyC.Value,max(sqrt(sa.w2)),sum(sa.feasible),numel(sa.feasible),uB.vU));
        catch err
            status.Text=['配置错误：' err.message];
            logMsg(['配置错误：' err.message]);
        end
    end
    function playback(varargin)
        try
            if dirty, prepare(); end
            if isempty(L), return; end
            if cursor>=height(L), cursor=1; end
            if strcmp(clock.Running,'off')
                clock.Period=.15/speedSlider.Value; start(clock);
            else
                clock.Period=.15/speedSlider.Value;
            end
            status.Text='播放中';
        catch err, status.Text=['配置错误：' err.message]; end
    end
    function stopPlayback(varargin)
        if strcmp(clock.Running,'on'), stop(clock); end
        status.Text='已暂停';
    end
    function tick(varargin)
        if ~isvalid(fig), return; end
        cursor=min(height(L),cursor+max(1,round(height(L)/70))); redraw();
        if cursor==height(L), stopPlayback(); report(); end
    end
    function toEnd(varargin)
        stopPlayback(); if dirty, prepare(); end
        if isempty(L), return; end
        cursor=height(L); redraw(); report();
    end
    function report()
        m=wind.mop_moe(L,c);
        labOverall.Text=sprintf('%.4f',m.MOE_energy);
        if m.MOE_energy>=0.99, labOverall.FontColor=[.0 .45 .2];
        elseif m.MOE_energy>=0.97, labOverall.FontColor=[.85 .45 .1];
        else, labOverall.FontColor=[.8 .1 .1]; end
        labE.Text=sprintf('%.3f%%',m.energyExcessPercent);
        labR.Text=sprintf('%.3f%%',m.MOP.tailRegretPercent);
        labV.Text=sprintf('%.3f / %.3f',m.MOP.rmsVErr,m.MOP.maxVErr);
        if isnan(m.MOP.windEstErr), labW.Text='—(非在线)'; else
            labW.Text=sprintf('%.3f',m.MOP.windEstErr); end
        logMsg(sprintf(['MOP/MOE汇总: MOE=%.4f | 能量超额=%.3f%% | 尾段超额=%.3f%% | '...
            '调度偏差rms=%.3f max=%.3f | 风估误差=%s'],m.MOE_energy,m.energyExcessPercent,...
            m.MOP.tailRegretPercent,m.MOP.rmsVErr,m.MOP.maxVErr,labW.Text));
    end
    function redraw()
        if isempty(L), return; end
        n=height(L); k=cursor; vis=truth.Value;
        sa=wind.analytic_sched(c,L.time);
        h.vCmd.XData=L.time(1:k); h.vCmd.YData=L.vCmd(1:k);
        if vis
            h.vstar.XData=L.time(1:k); h.vstar.YData=sa.v(1:k);
            h.vU.XData=L.time([1 k]); h.vU.YData=info.vU*[1 1];
        else
            h.vstar.XData=nan; h.vstar.YData=nan; h.vU.XData=nan; h.vU.YData=nan;
        end
        xlim(ax(1),[0 L.time(end)]); ylim(ax(1),[c.vLower-0.5 c.vUpper+0.5]);
        h.pTrue.XData=L.time(1:k); h.pTrue.YData=L.powerTrue(1:k);
        h.pMeas.XData=L.time(1:k); h.pMeas.YData=L.powerMeas(1:k);
        if vis, h.pMin.XData=L.time(1:k); h.pMin.YData=sa.Pmin(1:k);
        else, h.pMin.XData=nan; h.pMin.YData=nan; end
        xlim(ax(2),[0 L.time(end)]);
        h.wX.XData=L.time(1:k); h.wX.YData=L.windX(1:k);
        h.wY.XData=L.time(1:k); h.wY.YData=L.windY(1:k);
        h.wXe.XData=L.time(1:k); h.wXe.YData=L.windEstX(1:k);
        h.wYe.XData=L.time(1:k); h.wYe.YData=L.windEstY(1:k);
        xlim(ax(3),[0 L.time(end)]);
        h.cum.XData=L.time(1:k); h.cum.YData=cumExcess(1:k);
        xlim(ax(4),[0 L.time(end)]);
        % 飞机模型
        gSpeed.Value=L.vCmd(k);
        gPower.Value=min(max(L.powerMeas(k),0.85),1.1);
        psi=sa.psi(k); R=c.circleRadius;
        px=R*cos(psi); py=R*sin(psi);
        labMetrics.Text=sprintf('航向 %3.0f° | 位置 (%+.0f,%+.0f) | P测 %.4f | P真 %.4f',...
            mod(rad2deg(psi),360),px,py,L.powerMeas(k),L.powerTrue(k));
        % 环境模型
        thet=linspace(0,2*pi,181);
        hTrail.XData=R*cos(thet); hTrail.YData=R*sin(thet);
        hPlane.XData=px; hPlane.YData=py; hHome.XData=0; hHome.YData=0;
        % 风系分解: 绿=风系x分量Wx(沿风向角), 紫=世界系合成w
        phi=deg2rad(c.windDirDeg);
        Wxf=L.windX(k)*cos(phi)+L.windY(k)*sin(phi);
        setArrow(hWindX,hTipX,c.windDirDeg,R*(0.16+0.055*abs(Wxf)),abs(Wxf)>1e-9);
        setArrow(hWindR,hTipR,atan2d(L.windY(k),L.windX(k)),...
            R*(0.16+0.055*hypot(L.windX(k),L.windY(k))),true);
        hEnvTxt1.HorizontalAlignment='center'; hEnvTxt2.HorizontalAlignment='center';
        hEnvTxt1.Position=[0,-R*0.2,0];
        hEnvTxt1.String=sprintf('w=(%+.2f, %+.2f) |w|=%.2f m/s | ŵ=(%+.2f, %+.2f)',...
            L.windX(k),L.windY(k),hypot(L.windX(k),L.windY(k)),...
            L.windEstX(k),L.windEstY(k));
        hEnvTxt2.Position=[0,R*1.08,0];
        hEnvTxt2.String=sprintf('半径 %d m | 盘旋周期 %.0f s | t=%.0f s | v*=%.2f',...
            R,c.circlePeriod,L.time(k),sa.v(k));
        axis(axEnv,'equal'); xlim(axEnv,[-R*1.15 R*1.15]); ylim(axEnv,[-R*1.3 R*1.32]);
        xlabel(axEnv,'x / m'); ylabel(axEnv,'y / m');
        readout.Text=sprintf('步 %d/%d | t=%.0fs | v_cmd %.2f | v* %.2f | 可行 %d',...
            k,n,L.time(k),L.vCmd(k),sa.v(k),sa.feasible(k));
        drawnow limitrate;
    end
    function setArrow(hL,hT,angDeg,ln,vis)
        ang=angDeg+(ln<0)*180;
        tx=ln*cosd(ang); ty=ln*sind(ang);
        hL.XData=[0.3*tx, 0.85*tx]; hL.YData=[0.3*ty, 0.85*ty];
        hT.Position=[tx,ty,0]; hT.Rotation=ang;
        hL.Visible=vis; hT.Visible=vis;
    end
    function exportCurrent(varargin)
        stopPlayback();
        folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
        file=fullfile(folder,['ui_' datestr(now,'yyyymmdd_HHMMSS') '.png']);
        exportapp(fig,file); status.Text=['面板截图已导出：' file]; logMsg(status.Text);
    end
    function value=getLog(), value=L; end
    function value=getCursor(), value=cursor; end
    function logMsg(msg)
        stamp=datestr(now,'HH:MM:SS');
        logBox.Value=[{sprintf('[%s] %s',stamp,msg)}; logBox.Value(1:min(end,398))];
    end
    function clearLog(varargin)
        logBox.Value={'日志已清空'};
    end
    function loadReport(varargin)
        rp=fullfile(root,'results','report.md');
        if ~exist(rp,'file')
            logMsg('未找到验收报告: 请先在命令行运行 run_wind_acceptance');
            return;
        end
        lines=readlines(rp);
        logMsg('—— 验收报告(results/report.md)开始 ——');
        nShow=min(numel(lines),120);
        for i=1:nShow
            logBox.Value=[logBox.Value(1:min(end,398)); {char(strtrim(lines(i)))}];
        end
        logMsg('—— 验收报告结束 ——');
    end
    function closeApp(varargin)
        if isvalid(clock), stop(clock); delete(clock); end
        delete(fig);
    end
end

function h=number(g,text,row,value,limits)
label(g,text,row); h=uieditfield(g,'numeric','Value',value,'Limits',limits); put(h,row,2);
end
function h=choice(g,text,row,items,data,value)
label(g,text,row); h=uidropdown(g,'Items',items,'ItemsData',data,'Value',value); put(h,row,2);
end
function label(g,text,row)
h=uilabel(g,'Text',text,'FontName','Microsoft YaHei','FontSize',11,'WordWrap','on'); put(h,row,1);
end
function put(h,row,col)
h.Layout.Row=row; h.Layout.Column=col;
end
