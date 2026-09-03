function fig = launch_task7_demo(visible)
%LAUNCH_TASK8_DEMO 任务8功率曲线case标定面板：控制台(主) + 飞机模型 + 环境模型。
% 架构与任务6一致(环境/飞机/控制台三模块), 对象侧升级四处实际约束：
% 转弯半径50-150m(物理化: 航向角速度=v/R) / 通信时延0.1-0.5s / 加速度限幅
% 2 m/s² / 开环固定基线对照。策略下拉含 openloop基线与known oracle参照。
% 结果卡片新增"vs开环基线"行, 直接量化算法MOE提升(需求4)。
if nargin<1, visible='on'; end
root=fileparts(mfilename('fullpath')); addpath(root);
fig=uifigure('Name','任务8功率曲线case标定：谷底=悬停的95%/90%/85%(参考DJI Mavic Pro) × 真实约束(动态演示)',...
    'Position',[40 30 1500 960],'Color',[.96 .97 .98],'Visible',visible,...
    'AutoResizeChildren','off');
outer=uigridlayout(fig,[3 2]); outer.RowHeight={44,'1x',28}; outer.ColumnWidth={330,'1x'};
outer.Padding=[12 10 12 10]; outer.RowSpacing=10;
header=uilabel(outer,'Text','任务8程序 | 功率曲线case标定(case1 95%/case2 90%/case3 85%谷底·悬停) × 真实约束 × 双层MOP/MOE',...
    'FontName','Microsoft YaHei','FontSize',15,'FontWeight','bold'); put(header,1,[1 2]);
leftLayout=uigridlayout(outer,[6 1]); put(leftLayout,2,1);
leftLayout.RowHeight={38,'1x',150,175,30,'1x'};
leftLayout.Padding=[0 0 0 0]; leftLayout.RowSpacing=8;
left=leftLayout;
% --- 模块切换按钮(左上三个) ---
mods=uigridlayout(left,[1 3]); put(mods,1,1); mods.Padding=[0 0 8 0];
btnConsole=uibutton(mods,'Text','控制台(主)','FontWeight','bold'); put(btnConsole,1,1);
btnAir=uibutton(mods,'Text','飞机模型'); put(btnAir,1,2);
btnEnv=uibutton(mods,'Text','环境模型'); put(btnEnv,1,3);
form=uipanel(left,'BorderType','none'); put(form,2,1);
g=uigridlayout(form,[24 2]); g.ColumnWidth={150,'1x'};
g.RowHeight=[repmat({30},1,21),{26,30,30}];
g.Padding=[0 0 8 0]; g.RowSpacing=7; g.Scrollable='on';
algorithm=choice(g,'控制策略',1,{'openloop开环固定基线','tracker平移跟踪','esc连续ESC',...
    'spsa随机扰动寻优','bayes贝叶斯代理寻优','qnewton牛顿拟合寻优',...
    'gtrack小行程梯度跟踪(新)','est风EKF估计跟踪(新)','known已知风oracle参照'},...
    {'openloop','tracker','esc','spsa','bayes','qnewton','gtrack','est','known'},'qnewton');
scenarioC=choice(g,'平移场景',2,{'static圆周运动','jumpUp上跳','jumpDown下跳',...
    'offset纯上移','ramp慢漂'},{'static','jumpUp','jumpDown','offset','ramp'},'static');
turnR=number(g,'转弯半径 / m',3,100,[50 150]);
latSec=number(g,'通信时延 / s',4,0.3,[0.1 0.5]);
aMaxF=number(g,'加速度限幅 / m·s⁻²',5,2.0,[0.5 5]);
initial=number(g,'初始速度 / m/s',6,6,[0 20]);
noise=number(g,'相对噪声标准差',7,0.01,[0 0.05]);
ripA1=number(g,'崎岖幅值A1',8,0.022,[0 0.06]);
ripL1=number(g,'崎岖波长λ1 / m',9,6.0,[2 12]);
ripA2=number(g,'崎岖幅值A2',10,0.012,[0 0.06]);
ripL2=number(g,'崎岖波长λ2 / m',11,2.0,[1 6]);
shiftTime=number(g,'平移时刻 / 步',12,120,[30 350]);
shiftDx=number(g,'跳变幅值dx / m/s',13,2.7,[-6 6]);
seed=number(g,'随机种子',14,11,[1 100]);
windAmp=number(g,'风幅值A / m·s⁻¹',15,2.0,[0 10]);
windOmega=number(g,'风角频率ω1 / rad·s⁻¹',16,0.08,[0 2]);
windBias=number(g,'风偏置B / m·s⁻¹',17,3.0,[0 10]);
windC=number(g,'风幅值C / m·s⁻¹',18,1.5,[0 10]);
windOmega2=number(g,'风角频率ω2 / rad·s⁻¹',19,0.13,[0 2]);
windD=number(g,'风偏置D / m·s⁻¹',20,1.0,[0 10]);
curveC=choice(g,'功率曲线case(谷底/悬停)',21,{'case1 95%','case2 90%','case3 85%'},...
    {0.95,0.90,0.85},0.90);
truth=uicheckbox(g,'Text','显示评价器曲线与真值','Value',true); put(truth,22,[1 2]);
energy=uicheckbox(g,'Text','搜索能耗计入评价(续航口径)','Value',true); put(energy,23,[1 2]);
speedLabel=uilabel(g,'Text','播放速度: 1.00x','FontName','Microsoft YaHei','FontSize',11); put(speedLabel,24,1);
speedSlider=uislider(g,'Limits',[0.5 8],'Value',1,'MajorTicks',[.5 1 2 4 8],...
    'MajorTickLabels',{'0.5x','1x','2x','4x','8x'}); put(speedSlider,24,2);
speedSlider.ValueChangedFcn=@(~,ev) setSpeed(ev.Value);
    function setSpeed(val)
        speedLabel.Text=sprintf('播放速度: %.2fx',val);
        if strcmp(clock.Running,'on'), clock.Period=.15/val; end
    end
actions=uigridlayout(left,[3 4]); put(actions,3,1); actions.Padding=[0 0 8 0];
actions.RowHeight={34,34,34}; actions.RowSpacing=7;
play=uibutton(actions,'Text','播放'); put(play,1,1); pauseBtn=uibutton(actions,'Text','暂停'); put(pauseBtn,1,2);
reset=uibutton(actions,'Text','重置'); put(reset,1,3); finish=uibutton(actions,'Text','末帧'); put(finish,1,4);
exportPng=uibutton(actions,'Text','导出PNG'); put(exportPng,2,1);
exportGif=uibutton(actions,'Text','导出GIF动画'); put(exportGif,2,[2 4]);
% --- MOP/MOE 评价结果卡片(日志栏上方, 显著展示) ---
resultCard=uipanel(left,'Title','★ MOP/MOE 评价结果(任务窗终点)','FontName','Microsoft YaHei',...
    'FontSize',11,'ForegroundColor',[.62 .08 .08],'HighlightColor',[.62 .08 .08]);
put(resultCard,4,1);
rg=uigridlayout(resultCard,[6 2]); rg.RowHeight={30,24,24,24,24,24};
rg.ColumnWidth={'1x','1x'}; rg.Padding=[8 2 8 2]; rg.RowSpacing=1;
mkTag=@(txt) uilabel(rg,'Text',txt,'FontName','Microsoft YaHei','FontSize',9,'FontColor',[.25 .25 .25]);
mkVal=@(sz) uilabel(rg,'Text','—','FontName','Microsoft YaHei','FontSize',sz,...
    'FontWeight','bold','HorizontalAlignment','right');
labOverallT=mkTag('MOE 综合效能 overall(0.5能+0.3瞬+0.2可用)'); put(labOverallT,1,1);
labOverall=mkVal(15); put(labOverall,1,2); labOverall.FontColor=[.0 .45 .2];
labEnergyT=mkTag('续航能效 MOE_energy / 能耗超额'); put(labEnergyT,2,1);
labEnergy=mkVal(11); put(labEnergy,2,2);
labLiftT=mkTag('vs 开环基线: ΔMOE / 能耗相对变化'); put(labLiftT,3,1);
labLift=mkVal(11); put(labLift,3,2);
labInstT=mkTag('瞬时能效 instant / 指令跟踪滞后'); put(labInstT,4,1);
labInst=mkVal(11); put(labInst,4,2);
labSetT=mkTag('入带步数 / 任务可用率'); put(labSetT,5,1);
labSet=mkVal(11); put(labSet,5,2);
labSeaT=mkTag('搜索步数(含就位) / 稳态波动σ'); put(labSeaT,6,1);
labSea=mkVal(11); put(labSea,6,2);
readout=uilabel(left,'Text','','WordWrap','on','FontName','Microsoft YaHei'); put(readout,5,1);
logBox=uitextarea(left,'Editable','off','FontName','Microsoft YaHei','FontSize',9); put(logBox,6,1);
plots=uigridlayout(outer,[3 2]); put(plots,2,2); plots.Padding=[0 0 0 0];
plots.RowHeight={'1x','1x',250}; plots.ColumnWidth={'1x','1x'}; plots.RowSpacing=14; plots.ColumnSpacing=18;
ax=gobjects(1,4); for k=1:4, ax(k)=uiaxes(plots); disableDefaultInteractivity(ax(k)); ax(k).Toolbar.Visible='off'; end
put(ax(1),1,1); put(ax(2),1,2); put(ax(3),2,1); put(ax(4),2,2);
status=uilabel(outer,'Text','就绪','FontName','Microsoft YaHei'); put(status,3,2);
clock=timer('ExecutionMode','fixedSpacing','Period',.15,'BusyMode','drop','TimerFcn',@tick);
L=table(); info=[]; scn=[]; c=[]; Lb=table(); mBase=[]; cursor=1; dirty=true;
h=struct(); phaseMap=[]; cumEnergy=[]; estError=[]; curView='console';
phaseMap={'local','局部';'sigma','噪声估计';'far','远点证据';'scan','扫描';...
    'refine','精调';'polish','顶点';'hold','锁定';'probe','复探';...
    'search','搜索';'esc','ESC步进';'settle','指令就位';'track','梯度跟踪';...
    'est','估计跟踪';'oracle','oracle'};
controls=struct('algorithm',algorithm,'scenario',scenarioC,'turnR',turnR,...
    'latSec',latSec,'aMaxF',aMaxF,'initial',initial,'noise',noise,...
    'ripA1',ripA1,'ripL1',ripL1,'ripA2',ripA2,'ripL2',ripL2,...
    'shiftTime',shiftTime,'shiftDx',shiftDx,'seed',seed,...
    'windAmp',windAmp,'windOmega',windOmega,'windBias',windBias,...
    'windC',windC,'windOmega2',windOmega2,'windD',windD,'curveC',curveC,'truth',truth,'energy',energy,...
    'play',play,'pause',pauseBtn,'reset',reset,'finish',finish,...
    'exportPng',exportPng,'exportGif',exportGif,'speed',speedSlider);
fig.UserData=struct('controls',controls,'prepare',@prepare,'play',@playback,...
    'pause',@stopPlayback,'finish',@toEnd,'getLog',@getLog,'getCursor',@getCursor,...
    'timer',clock,'exportPng',@exportCurrent,'exportGif',@exportGifCurrent,...
    'logMsg',@logMsg,'loadReport',@loadReport,'clearLog',@clearLog,...
    'setView',@setView);
% ============ 飞机模型 & 环境模型 模块窗口 ============
airPanel=uipanel(plots,'Title','飞机模型：速度+功率双表盘(黑箱仪表)','FontName','Microsoft YaHei',...
    'ForegroundColor',[.15 .3 .6],'HighlightColor',[.15 .3 .6]);
airPanel.Layout.Row=3; airPanel.Layout.Column=1;
ag=uigridlayout(airPanel,[5 2]); ag.RowHeight={150,16,16,16,34}; ag.ColumnWidth={'1x','1x'};
ag.Padding=[6 6 6 4]; ag.RowSpacing=4;
gSpeed=uigauge(ag,'Limits',[0 20]); put(gSpeed,1,1);
labSp=uilabel(ag,'Text','实际速度表 / m·s⁻¹','FontName','Microsoft YaHei','FontSize',9,'HorizontalAlignment','center'); put(labSp,2,1);
gPower=uigauge(ag,'Limits',[80 140]); put(gPower,1,2);
labPw=uilabel(ag,'Text','功率表 / W','FontName','Microsoft YaHei','FontSize',9,'HorizontalAlignment','center'); put(labPw,2,2);
labHdg=uilabel(ag,'Text','航向: —','FontName','Microsoft YaHei','FontSize',10,'HorizontalAlignment','center'); put(labHdg,3,1);
labPos=uilabel(ag,'Text','位置: —','FontName','Microsoft YaHei','FontSize',10,'HorizontalAlignment','center'); put(labPos,3,2);
labMetrics=uilabel(ag,'Text','','FontName','Microsoft YaHei','FontSize',10,...
    'HorizontalAlignment','center'); put(labMetrics,4,[1 2]);
btnAirSize=uibutton(ag,'Text','放大 ⤢'); put(btnAirSize,5,[1 2]);
btnAirSize.ButtonPushedFcn=@(~,~)toggleSize('air');
envPanel=uipanel(plots,'Title','环境模型：真实半径盘旋×双正交风','FontName','Microsoft YaHei',...
    'ForegroundColor',[.1 .45 .25],'HighlightColor',[.1 .45 .25]);
envPanel.Layout.Row=3; envPanel.Layout.Column=2;
eg=uigridlayout(envPanel,[2 2]); eg.RowHeight={'1x',28}; eg.ColumnWidth={'1x','1x'};
eg.Padding=[4 4 4 2]; eg.RowSpacing=2; eg.ColumnSpacing=8;
axEnv=uiaxes(eg); put(axEnv,1,1); disableDefaultInteractivity(axEnv); axEnv.Toolbar.Visible='off';
title(axEnv,'航迹 + 双正交风矢量(绿=x向, 橙=y向, 紫=合成)','FontSize',8);
axWind=uiaxes(eg); put(axWind,1,2); disableDefaultInteractivity(axWind); axWind.Toolbar.Visible='off';
title(axWind,'两正交方向风速变化曲线','FontSize',9);
ylabel(axWind,'W / m·s^{-1}','FontSize',8); xlabel(axWind,'t / s','FontSize',8);
btnEnvSize=uibutton(eg,'Text','放大 ⤢'); put(btnEnvSize,2,[1 2]);
btnEnvSize.ButtonPushedFcn=@(~,~)toggleSize('env');
ud=fig.UserData; ud.airPanel=airPanel; ud.envPanel=envPanel;
ud.resultCard=struct('overall',labOverall,'energy',labEnergy,'lift',labLift,...
    'instant',labInst,'settle',labSet,'search',labSea); fig.UserData=ud;
% 环境模型静态要素(uiaxes平台怪癖: patch须先于line创建)
hTrail=line(axEnv,nan,nan,'Color',[.2 .4 .8],'LineWidth',.8,'DisplayName','航迹');
hPlane=line(axEnv,nan,nan,'Color',[.85 .18 .18],'Marker','>','MarkerFaceColor',...
    [.85 .18 .18],'MarkerSize',11,'LineStyle','none','DisplayName','飞机位置');
hWindX=line(axEnv,nan,nan,'Color',[.0 .55 .25],'LineWidth',2.2,'DisplayName','x向风');
hWindY=line(axEnv,nan,nan,'Color',[.85 .45 .1],'LineWidth',2.2,'DisplayName','y向风');
hWindR=line(axEnv,nan,nan,'Color',[.5 .2 .7],'LineWidth',2.6,'DisplayName','合成风');
hHome=line(axEnv,nan,nan,'Color',[.4 .4 .4],'Marker','s','MarkerSize',8,...
    'LineStyle','none','DisplayName','盘旋中心');
hEnvTxt1=text(axEnv,0,0,'','FontName','Microsoft YaHei','FontSize',9,'Color',[.2 .2 .55]);
hEnvTxt2=text(axEnv,0,0,'','FontName','Microsoft YaHei','FontSize',9,'Color',[.3 .3 .3]);
hEnvTxt1.HorizontalAlignment='center';
hEnvTxt2.HorizontalAlignment='center';
hTipX=text(axEnv,0,0,char(10132),'FontName','Segoe UI Symbol','FontSize',12,...
    'Color',[.0 .55 .25],'HorizontalAlignment','center','VerticalAlignment','middle');
hTipY=text(axEnv,0,0,char(10132),'FontName','Segoe UI Symbol','FontSize',12,...
    'Color',[.85 .45 .1],'HorizontalAlignment','center','VerticalAlignment','middle');
hTipR=text(axEnv,0,0,char(10132),'FontName','Segoe UI Symbol','FontSize',14,...
    'Color',[.5 .2 .7],'HorizontalAlignment','center','VerticalAlignment','middle');
legend(axEnv,'Location','southoutside','Orientation','horizontal','FontSize',6.5);
hCurveX=line(axWind,nan,nan,'Color',[.0 .55 .25],'LineWidth',1.2,'DisplayName','x向风 W_x');
hCurveY=line(axWind,nan,nan,'Color',[.85 .45 .1],'LineWidth',1.2,'DisplayName','y向风 W_y');
hNowX=line(axWind,nan,nan,'Color',[.0 .55 .25],'Marker','o','MarkerFaceColor',...
    [.0 .55 .25],'MarkerSize',4,'LineStyle','none','DisplayName','当前W_x');
hNowY=line(axWind,nan,nan,'Color',[.85 .45 .1],'Marker','o','MarkerFaceColor',...
    [.85 .45 .1],'MarkerSize',4,'LineStyle','none','DisplayName','当前W_y');
hWindZero=line(axWind,nan,nan,'Color',[.6 .6 .6],'LineStyle','--','LineWidth',.5,'DisplayName','W=0');
legend(axWind,'Location','southoutside','Orientation','horizontal','FontSize',7);
ctrlList={algorithm,scenarioC,turnR,latSec,aMaxF,initial,noise,ripA1,ripL1,ripA2,ripL2,...
    shiftTime,shiftDx,seed,windAmp,windOmega,windBias,windC,windOmega2,windD,curveC};
for cn=ctrlList
    cn{1}.ValueChangedFcn=@changed;
end
curveC.ValueChangedFcn=@caseChanged;
truth.ValueChangedFcn=@(~,~)redraw(); energy.ValueChangedFcn=@(~,~)redraw();
play.ButtonPushedFcn=@playback; pauseBtn.ButtonPushedFcn=@stopPlayback;
reset.ButtonPushedFcn=@prepare; finish.ButtonPushedFcn=@toEnd;
exportPng.ButtonPushedFcn=@exportCurrent; exportGif.ButtonPushedFcn=@exportGifCurrent;
loadReportBtn=uibutton(actions,'Text','载入验收报告'); put(loadReportBtn,3,1);
loadReportBtn.ButtonPushedFcn=@loadReport;
clearLogBtn=uibutton(actions,'Text','清空日志'); put(clearLogBtn,3,[2 4]);
clearLogBtn.ButtonPushedFcn=@clearLog;
btnConsole.ButtonPushedFcn=@(~,~)setView('console');
btnAir.ButtonPushedFcn=@(~,~)setView('air');
btnEnv.ButtonPushedFcn=@(~,~)setView('env');
fig.CloseRequestFcn=@closeApp; fig.SizeChangedFcn=@resizeLayout;
setupPanels(); resizeLayout(); highlightButtons();
logMsg('任务8功率曲线case标定程序就绪 | case1 95%/case2 90%/case3 85%(谷底/悬停) | 参考DJI Mavic Pro | 半径50-150m/时延0.1-0.5s/限幅2m/s²');
logMsg('提示: 结果卡片含"vs开环基线"提升行; known为已知风oracle参照(非因果); 半径即时延即改即生效');
if exist(fullfile(root,'results','report.md'),'file')
    loadReport();
else
    logMsg('尚未生成验收报告: 命令行运行 run_task8_checks 后点"载入验收报告"');
end
prepare();

    function toggleSize(which)
        if strcmp(which,'air')
            if airPanel.Layout.Row(1)==1
                airPanel.Layout.Row=3; airPanel.Layout.Column=1;
                btnAirSize.Text='放大 ⤢';
            else
                airPanel.Layout.Row=[1 3]; airPanel.Layout.Column=[1 2];
                btnAirSize.Text='还原 ⤡';
            end
        else
            if envPanel.Layout.Row(1)==1
                envPanel.Layout.Row=3; envPanel.Layout.Column=2;
                btnEnvSize.Text='放大 ⤢';
            else
                envPanel.Layout.Row=[1 3]; envPanel.Layout.Column=[1 2];
                btnEnvSize.Text='还原 ⤡';
            end
        end
        drawnow;
    end

    function setView(v)
        curView=v;
        plots.Visible='on';
        airPanel.Visible='on'; envPanel.Visible='on';
        switch v
            case 'console'
                airPanel.Layout.Row=3; airPanel.Layout.Column=1;
                envPanel.Layout.Row=3; envPanel.Layout.Column=2;
                btnAirSize.Text='放大 ⤢'; btnEnvSize.Text='放大 ⤢';
            case 'air'
                envPanel.Visible='off';
                airPanel.Layout.Row=[1 3]; airPanel.Layout.Column=[1 2];
                btnAirSize.Text='还原 ⤡'; btnEnvSize.Text='放大 ⤢';
            case 'env'
                airPanel.Visible='off';
                envPanel.Layout.Row=[1 3]; envPanel.Layout.Column=[1 2];
                btnAirSize.Text='放大 ⤢'; btnEnvSize.Text='还原 ⤡';
        end
        highlightButtons();
        drawnow;
    end

    function highlightButtons()
        if strcmp(curView,'console'), btnConsole.FontWeight='bold'; else, btnConsole.FontWeight='normal'; end
        if strcmp(curView,'air'), btnAir.FontWeight='bold'; else, btnAir.FontWeight='normal'; end
        if strcmp(curView,'env'), btnEnv.FontWeight='bold'; else, btnEnv.FontWeight='normal'; end
        btnConsole.BackgroundColor=[.85 .92 1]*strcmp(curView,'console')+[1 1 1]*(strcmp(curView,'console')==0);
        btnAir.BackgroundColor=[.85 .92 1]*strcmp(curView,'air')+[1 1 1]*(strcmp(curView,'air')==0);
        btnEnv.BackgroundColor=[.85 .92 1]*strcmp(curView,'env')+[1 1 1]*(strcmp(curView,'env')==0);
    end

    function updateModules(k)
        % 依据当前帧k更新飞机模型与环境模型(位置用日志里的积分航向)
        if isempty(L) || isempty(c), return; end
        tNow=L.time(k);
        R=c.turnRadius;
        psi=deg2rad(L.headingDeg(k));
        px=R*cos(psi); py=R*sin(psi);
        gSpeed.Value=L.speed(k);
        gPower.Value=L.powerTrue(k)*c.pHover;
        tailExcess=100*sum(L.powerTrue(1:k)-L.minPowerTrue(1:k))/max(sum(L.minPowerTrue(1:k)),eps);
        labMetrics.Text=sprintf(['航向 %3.0f° | 周期 %.0f s | 功率真值 %.3f | '...
            '测量 %.3f | 累计能耗超额 %.2f%%'],...
            mod(rad2deg(psi),360),2*pi*R/max(L.speed(k),0.1),...
            L.powerTrue(k),L.powerMeas(k),tailExcess);
        labPos.Text=sprintf('位置: (%+.0f, %+.0f) m',px,py);
        labHdg.Text=sprintf('航向: %3.0f°',mod(rad2deg(psi),360));
        thet=linspace(0,2*pi,181);
        hTrail.XData=R*cos(thet); hTrail.YData=R*sin(thet);
        hPlane.XData=px; hPlane.YData=py;
        hHome.XData=0; hHome.YData=0;
        phi=deg2rad(c.windDirDeg);
        [Wx,Wy,Vx,Vy]=w8.wind_components(scn,tNow);
        Vm=hypot(Vx,Vy); Vang=atan2d(Vy,Vx);
        setArrow(hWindX,hTipX,c.windDirDeg,   R*(0.16+0.055*abs(Wx)),abs(Wx)>1e-9);
        setArrow(hWindY,hTipY,c.windDirDeg+90,R*(0.16+0.055*abs(Wy)),abs(Wy)>1e-9);
        setArrow(hWindR,hTipR,Vang,           R*(0.16+0.055*Vm),      abs(Vm)>1e-9);
        hEnvTxt1.HorizontalAlignment='center';
        hEnvTxt2.HorizontalAlignment='center';
        hEnvTxt1.Position=[0,-R*0.2,0];
        hEnvTxt1.String=sprintf('x风 %+.2f | y风 %+.2f | 合成 %+.2f m/s @ %3.0f°',Wx,Wy,Vm,Vang);
        hEnvTxt2.Position=[0, R*1.08, 0];
        hEnvTxt2.String=sprintf('半径 %d m | 时延 %.1f s | 限幅 %.0f m/s² | t=%.0f s',...
            R,c.latencySec,c.aMax,tNow);
        axis(axEnv,'equal');
        xlim(axEnv,[-R*1.15 R*1.15]); ylim(axEnv,[-R*1.3 R*1.32]);
        xlabel(axEnv,'x / m'); ylabel(axEnv,'y / m');
        tt=linspace(0,c.duration*c.tEval,600);
        WWx=c.windAmp*sin(c.windOmega*tt)+c.windBias;
        WWy=c.windAmpY*sin(c.windOmegaY*tt)+c.windBiasY;
        hCurveX.XData=tt; hCurveX.YData=WWx;
        hCurveY.XData=tt; hCurveY.YData=WWy;
        hNowX.XData=tNow; hNowX.YData=Wx;
        hNowY.XData=tNow; hNowY.YData=Wy;
        hWindZero.XData=[0 tt(end)]; hWindZero.YData=[0 0];
        xlim(axWind,[0 tt(end)]);
        ylim(axWind,[min([WWx,WWy])-0.6,max([WWx,WWy])+0.6]);
    end

    function resizeLayout(varargin)
        bodyHeight=max(440,fig.InnerPosition(4)-112);
        outer.RowHeight={44,bodyHeight,28};
        avail=max(500,bodyHeight)-448;  % 38+150+175+30固定 + 5×8间距
            formH=max(230,round(0.45*avail)); logH=max(150,avail-formH);
            leftLayout.RowHeight={38,formH,150,175,30,logH};
    end

    function changed(varargin)
        stopPlayback(); dirty=true; status.Text='参数已更改，按"重置"或"播放"生效';
    end

    function buildConfig()
        c=w8.config('initialSpeed',initial.Value,'noiseSigma',noise.Value,'curveCase',curveC.Value,...
            'turnRadius',turnR.Value,'latencySec',latSec.Value,'aMax',aMaxF.Value,...
            'rippleA1',ripA1.Value,'rippleL1',ripL1.Value,...
            'rippleA2',ripA2.Value,'rippleL2',ripL2.Value,...
            'shiftTime',shiftTime.Value,'seed',seed.Value,...
            'windAmp',windAmp.Value,'windOmega',windOmega.Value,'windBias',windBias.Value,...
            'windAmpY',windC.Value,'windOmegaY',windOmega2.Value,'windBiasY',windD.Value);
        if strcmp(scenarioC.Value,'jumpUp'), c.jumpUpDx=shiftDx.Value; end
        if strcmp(scenarioC.Value,'jumpDown'), c.jumpDownDx=shiftDx.Value; end
    end

    function prepare(varargin)
        stopPlayback();
        try
            buildConfig();
            drawCasePreview();
            scn=w8.scenario(scenarioC.Value,c);
            [L,info]=w8.run_algorithm(algorithm.Value,scn,c);
            n=height(L);
            cumEnergy=100*cumsum(L.powerTrue-L.minPowerTrue)./cumsum(L.minPowerTrue);
            estError=abs(L.estimate-L.optimumTrue);
            mopFinal=w8.mop_moe(L,c);
            % 开环基线对照(需求4): 同对象/同预算/同种子
            if strcmp(algorithm.Value,'openloop')
                Lb=L; mBase=mopFinal;
            else
                [Lb,~]=w8.run_algorithm('openloop',scn,c);
                mBase=w8.mop_moe(Lb,c);
            end
            cursor=1; dirty=false; redraw(); status.Text='就绪';
            logMsg(sprintf(['重置完成: 策略=%s 场景=%s 半径=%dm 时延=%.1fs 限幅=%.0fm/s² '...
                '初速=%.0f 种子=%d | 风: x=A%.1f·sin(ω1t)+%.1f y=C%.1f·sin(ω2t)+%.1f '...
                '| 整圈周期≈%.0fs'],algorithm.Value,scenarioC.Value,turnR.Value,...
                latSec.Value,aMaxF.Value,initial.Value,seed.Value,...
                windAmp.Value,windBias.Value,windC.Value,windD.Value,...
                2*pi*turnR.Value/max(mean(L.speed),0.5)));
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
        m=w8.mop_moe(L,c);
        status.Text=sprintf(['MOE=%.4f | 末误差 %.3f m/s | 稳态超额 %.3f%% | '...
            '全程能耗超额 %.2f%%'],m.MOE_energy,m.finalErr,m.regretPercent,...
            sum(L.powerTrue-L.minPowerTrue)/sum(L.minPowerTrue)*100);
        if isnan(m.MOE.overall)
            labOverall.Text='—'; labOverall.FontColor=[.5 .5 .5];
        else
            labOverall.Text=sprintf('%.4f',m.MOE.overall);
            if m.MOE.overall>=0.99, labOverall.FontColor=[.0 .45 .2];
            elseif m.MOE.overall>=0.97, labOverall.FontColor=[.85 .45 .1];
            else, labOverall.FontColor=[.8 .1 .1]; end
        end
        if isnan(m.MOE_energy)
            labEnergy.Text='能耗开关=关';
        else
            labEnergy.Text=sprintf('%.4f (超额 %.2f%%)',m.MOE_energy,m.energyExcessPercent);
        end
        % vs开环基线(需求4核心读数)
        mb=mBase;
        if strcmp(algorithm.Value,'openloop') || isnan(mb.MOE_energy) || isnan(m.MOE_energy)
            labLift.Text='基线=自身 / —';
            labLift.FontColor=[.4 .4 .4];
        else
            lift=m.MOE_energy-mb.MOE_energy;
            epct=100*(mb.EactualNorm-m.EactualNorm)/mb.EactualNorm;
            labLift.Text=sprintf('%+.4f / %+.2f%%',lift,epct);
            if lift>1e-6, labLift.FontColor=[.0 .45 .2];
            elseif lift<-1e-6, labLift.FontColor=[.8 .1 .1];
            else, labLift.FontColor=[.5 .5 .5]; end
        end
        if isnan(m.MOE_instant)
            labInst.Text='能耗开关=关';
        else
            labInst.Text=sprintf('%.4f / %.2f m/s',m.MOE_instant,m.MOP.meanTrackLag);
        end
        labSet.Text=sprintf('%g 步 / %.1f%%',m.MOP.settleSteps,100*m.MOE_availability);
        labSea.Text=sprintf('%d 步 / σ=%.3f',m.MOP.searchSteps,m.MOP.steadyFluct);
        logMsg(sprintf(['MOP/MOE汇总: overall=%.4f | MOE_energy=%.4f | 开环基线MOE=%.4f | '...
            'ΔMOE=%+.4f | 可用率=%.1f%% | 末误差=%.3f | 跟踪滞后=%.2f m/s | '...
            '搜索步数=%d(就位占%.0f%%) | 峰值加速度=%.1f m/s²'],...
            m.MOE.overall,m.MOE_energy,mBase.MOE_energy,...
            m.MOE_energy-mBase.MOE_energy,100*m.MOE_availability,...
            m.finalErr,m.MOP.meanTrackLag,m.MOP.searchSteps,...
            100*m.MOP.settleQueryRatio,m.maxAccelUsed));
    end

    function setupPanels()
        hold(ax(1),'on'); hold(ax(2),'on'); hold(ax(3),'on'); hold(ax(4),'on');
        % 前三条为case标定曲线预览(选中的加粗), 无需运行即可比较区别
        h.case1=line(ax(1),nan,nan,'Color',[.75 .75 .75],'LineWidth',.8,'DisplayName','case1 谷底95%');
        h.case2=line(ax(1),nan,nan,'Color',[.75 .75 .75],'LineWidth',.8,'DisplayName','case2 谷底90%');
        h.case3=line(ax(1),nan,nan,'Color',[.75 .75 .75],'LineWidth',.8,'DisplayName','case3 谷底85%');
        h.curve=line(ax(1),nan,nan,'Color',[.25 .25 .25],'LineWidth',1.4,'DisplayName','对象曲线(当前时刻,含风)');
        h.vstar=line(ax(1),nan,nan,'Color',[.85 .18 .18],'Marker','p','MarkerFaceColor',...
            [.85 .18 .18],'LineStyle','none','MarkerSize',13,'DisplayName','v*(t) 真值最优');
        h.ptHold=line(ax(1),nan,nan,'Color',[.55 .55 .55],'Marker','.','LineStyle','none',...
            'MarkerSize',7,'DisplayName','hold锁定');
        h.ptSettle=line(ax(1),nan,nan,'Color',[.7 .7 .3],'Marker','x','LineStyle','none',...
            'MarkerSize',5,'DisplayName','settle就位');
        h.ptProbe=line(ax(1),nan,nan,'Color',[.0 .65 .3],'Marker','.','LineStyle','none',...
            'MarkerSize',12,'DisplayName','probe复探');
        h.ptRefine=line(ax(1),nan,nan,'Color',[.85 .3 .1],'Marker','.','LineStyle','none',...
            'MarkerSize',12,'DisplayName','refine精调');
        h.ptScan=line(ax(1),nan,nan,'Color',[.16 .48 .72],'Marker','.','LineStyle','none',...
            'MarkerSize',10,'DisplayName','scan扫描');
        h.ptSearch=line(ax(1),nan,nan,'Color',[.0 .5 .6],'Marker','x','LineStyle','none',...
            'MarkerSize',6,'DisplayName','宽探针');
        h.ptTrack=line(ax(1),nan,nan,'Color',[.95 .5 .05],'Marker','.','LineStyle','none',...
            'MarkerSize',9,'DisplayName','track梯度');
        h.ptEst=line(ax(1),nan,nan,'Color',[.55 .3 .75],'Marker','.','LineStyle','none',...
            'MarkerSize',9,'DisplayName','est估计');
        h.est=line(ax(1),nan,nan,'Color',[.0 .55 .25],'Marker','o','LineStyle','none',...
            'MarkerSize',5,'DisplayName','当前指令');
        xlabel(ax(1),'速度 / m/s'); ylabel(ax(1),'功率 / W');
        drawCasePreview();
        title(ax(1),'功率曲线与查询点(逐帧)'); legend(ax(1),'Location','northwest','NumColumns',2,'FontSize',7);
        h.speed=line(ax(2),nan,nan,'Color',[.2 .4 .8],'LineWidth',.6,'DisplayName','实际速度');
        h.cmd=line(ax(2),nan,nan,'Color',[.55 .3 .75],'LineWidth',.5,'DisplayName','指令速度');
        h.estimate=line(ax(2),nan,nan,'Color',[.0 .55 .25],'LineWidth',1.5,'DisplayName','估计 v_{hat}');
        h.optimum=line(ax(2),nan,nan,'Color',[.85 .18 .18],'LineStyle','--','LineWidth',1.3,'DisplayName','v*(t) 真值');
        xlabel(ax(2),'评估步'); ylabel(ax(2),'速度 / m/s');
        title(ax(2),'速度演化：指令/实际 vs 真值'); legend(ax(2),'Location','northwest','FontSize',7);
        h.pTrue=line(ax(3),nan,nan,'Color',[.2 .3 .4],'LineWidth',.9,'DisplayName','真实功率');
        h.pMin=line(ax(3),nan,nan,'Color',[.85 .18 .18],'LineStyle','--','LineWidth',1.1,'DisplayName','Pmin(t) 理论最低');
        h.pMeas=line(ax(3),nan,nan,'Color',[.55 .3 .7],'Marker','.','LineStyle','none',...
            'MarkerSize',6,'DisplayName','带噪测量');
        xlabel(ax(3),'评估步'); ylabel(ax(3),'功率 / W');
        title(ax(3),'功率轨迹'); legend(ax(3),'Location','north','FontSize',8);
        h.metric=line(ax(4),nan,nan,'Color',[.8 .45 .1],'LineWidth',1.3);
        xlabel(ax(4),'评估步'); title(ax(4),'累计能量超额(开关=开)');
    end

    function caseChanged(varargin)
        dirty=true;
        drawCasePreview();
        status.Text=sprintf('case已切换: 谷底=%.0f%%×悬停103.7W, 曲线预览已更新; 按"重置/播放"生效',curveC.Value*100);
        logMsg(status.Text);
    end

    function drawCasePreview()
        if isempty(c), buildConfig(); end
        vv=linspace(0,c.upper,400);
        cv=[0.95 0.90 0.85];
        hds=[h.case1,h.case2,h.case3];
        for q=1:3
            cc=w8.config(c,'curveCase',cv(q));
            hds(q).XData=vv; hds(q).YData=w8.base_curve(vv,cc)*c.pHover;
            if abs(curveC.Value-cv(q))<1e-9
                hds(q).Color=[.85 .33 .1]; hds(q).LineWidth=2.4;
            else
                hds(q).Color=[.75 .75 .75]; hds(q).LineWidth=0.8;
            end
        end
        ylim(ax(1),[78 145]);
        legend(ax(1),'Location','northwest','NumColumns',2,'FontSize',7);
    end

    function redraw()
        if isempty(L), return; end
        n=height(L); k=cursor;
        vis=truth.Value;
        tags=string(L.tag(1:k)); sp=L.speed(1:k); pm=L.powerMeas(1:k)*c.pHover;
        tNow=L.time(k);
        % 左上: 当前时刻曲线 = J0(|v·t̂+w|-dx)+dy(显示侧)
        psiK=deg2rad(L.headingDeg(k));
        [WxK,WyK,VxK,VyK]=w8.wind_components(scn,tNow);
        vv=linspace(c.lower,c.upper,400);
        if vis
            uu=hypot(vv*cos(psiK)+VxK,vv*sin(psiK)+VyK);
            h.curve.XData=vv; h.curve.YData=(w8.base_curve(uu-L.shiftDx(k),c)+L.shiftDy(k))*c.pHover;
            h.vstar.XData=L.optimumTrue(k); h.vstar.YData=L.minPowerTrue(k)*c.pHover;
        else
            h.curve.XData=nan; h.curve.YData=nan;
            h.vstar.XData=nan; h.vstar.YData=nan;
        end
        setSlice(h.ptScan,sp,pm,tags,'scan');
        setSlice(h.ptRefine,sp,pm,tags,'refine');
        setSlice(h.ptHold,sp,pm,tags,'hold');
        setSlice(h.ptSettle,sp,pm,tags,'settle');
        setSlice(h.ptProbe,sp,pm,tags,'probe');
        setSlice(h.ptSearch,sp,pm,tags,'search');
        setSlice(h.ptTrack,sp,pm,tags,'track');
        setSlice(h.ptEst,sp,pm,tags,'est');
        h.est.XData=L.estimate(max(1,k-20):k); h.est.YData=pm(max(1,k-20):k);
        % 右上
        h.speed.XData=(1:k)'; h.speed.YData=sp;
        h.cmd.XData=(1:k)'; h.cmd.YData=L.speedCmd(1:k);
        h.estimate.XData=(1:k)'; h.estimate.YData=L.estimate(1:k);
        if vis, h.optimum.XData=(1:k)'; h.optimum.YData=L.optimumTrue(1:k);
        else, h.optimum.XData=nan; h.optimum.YData=nan; end
        xlim(ax(2),[1 n]); ylim(ax(2),[c.lower-0.5 c.upper+0.5]);
        % 左下
        h.pTrue.XData=(1:k)'; h.pTrue.YData=L.powerTrue(1:k)*c.pHover;
        h.pMeas.XData=(1:k)'; h.pMeas.YData=pm;
        if vis, h.pMin.XData=(1:k)'; h.pMin.YData=L.minPowerTrue(1:k)*c.pHover;
        else, h.pMin.XData=nan; h.pMin.YData=nan; end
        xlim(ax(3),[1 n]);
        % 右下
        xlim(ax(4),[1 n]);
        if energy.Value
            ax(4).YScale='linear'; ax(4).YLabel.String='累计能量超额 / %';
            title(ax(4),'累计能量超额(开关=开, 续航口径)');
            h.metric.YData=cumEnergy(1:k);
        else
            ax(4).YScale='log'; ax(4).YLabel.String='|v_{hat}-v*(t)| / m/s';
            title(ax(4),'估计误差(开关=关, 只看定位)');
            h.metric.YData=max(estError(1:k),1e-4);
        end
        h.metric.XData=(1:k)';
        ph='—';
        for q=1:size(phaseMap,1)
            if strcmp(char(tags(k)),phaseMap{q,1}), ph=phaseMap{q,2}; end
        end
        dxK=L.shiftDx(k); dyK=L.shiftDy(k);
        readout.Text=sprintf(['步 %d/%d | 相位 %s | 指令 %.2f | 实际 %.2f | v*(t) %.2f'...
            ' | 平移 dx%.2f dy%.2f | 航向 %3.0f°'],...
            k,n,ph,L.speedCmd(k),L.speed(k),L.optimumTrue(k),dxK,dyK,...
            mod(rad2deg(psiK),360));
        updateModules(k);
        drawnow limitrate;
    end

    function setArrow(hL,hT,angDeg,ln,vis)
        ang=angDeg+(ln<0)*180;
        tx=ln*cosd(ang); ty=ln*sind(ang);
        hL.XData=[0.3*tx, 0.85*tx]; hL.YData=[0.3*ty, 0.85*ty];
        hT.Position=[tx,ty,0]; hT.Rotation=ang;
        hL.Visible=vis; hT.Visible=vis;
    end

    function setSlice(hdl,sp,pm,tags,name)
        hit=strcmp(tags,name);
        hdl.XData=sp(hit); hdl.YData=pm(hit);
    end

    function exportCurrent(varargin)
        stopPlayback();
        folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
        file=fullfile(folder,['ui_' datestr(now,'yyyymmdd_HHMMSS') '.png']);
        exportapp(fig,file); status.Text=['面板截图已导出：' file]; logMsg(status.Text);
    end

    function exportGifCurrent(varargin)
        stopPlayback(); if dirty, prepare(); end
        if isempty(L), return; end
        folder=fullfile(root,'results'); if ~exist(folder,'dir'), mkdir(folder); end
        file=fullfile(folder,['modules_playback_' datestr(now,'yyyymmdd_HHMMSS') '.gif']);
        n=height(L); stride=max(1,round(n/48)); status.Text='GIF导出中…'; drawnow;
        savedPosition=fig.Position; fig.Position=[40 30 1000 680]; drawnow;
        first=true; cleanupGif=onCleanup(@()set(fig,'Position',savedPosition)); %#ok<NASGU>
        for k=1:stride:n
            cursor=min(k,n); redraw(); drawnow;
            tmp=fullfile(tempdir,sprintf('uf_%d.png',randi(1e9)));
            exportapp(fig,tmp);
            [A,map]=rgb2ind(imread(tmp),128);
            if first, imwrite(A,map,file,'gif','LoopCount',Inf,'DelayTime',.15); first=false;
            else, imwrite(A,map,file,'gif','WriteMode','append','DelayTime',.15); end
            delete(tmp);
        end
        cursor=n; redraw();
        status.Text=['GIF动画已导出：' file]; logMsg(status.Text);
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
            logMsg('未找到验收报告: 请先在命令行运行 run_task8_checks');
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
