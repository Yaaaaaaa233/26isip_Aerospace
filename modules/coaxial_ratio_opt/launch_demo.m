function fig = launch_demo(visible)
%LAUNCH_DEMO 工作包w11面板：固定速度下上下桨转速比的在线功率寻优。
% 控制量 r=η_Ω=Ω_u/Ω_l∈[0.75,1.25](项目任务书表1), 开环基线 r=1(默认等转速分配)。
% 对象: Opazo 2022 MT链功率-桨比真值(谷底锚定飞试 r*=0.89, 深度=case族) + γ干扰场
% (类比风, 七种模板); 四主角 sweepcal/rl/purerl/hybrid 纯因果 + oracle 参照。
% 四联图布局(方法论映射表口径):
%   左上: 功率-桨比曲线(真值/拟合/采样点, 全图同一自变量域=r);
%   右上: 桨比演化 vs r* 真值(图例两列置右上);
%   左下: 功率轨迹;  右下: 累计能耗超额。
% 附飞机模型(桨比/功率双表盘)与环境模型(航迹+γ曲线预览)模块。
if nargin<1, visible='on'; end
root=fileparts(mfilename('fullpath')); addpath(root);
% —— 自愈暂存: 绕开MATLAB目录缓存滞后导致的 w11.* 解析失败 ——
if exist('w11.fit_curve_interf','file')~=2
    stg=fullfile(tempdir,['w11stage_' datestr(now,'yyyymmddHHMMSS') '_' num2str(randi(8999)+1000)]);
    copyfile(fullfile(root,'+w11'),fullfile(stg,'+w11'));
    addpath(stg); clear functions; rehash;
end
fig=uifigure('Name','工作包w11 共轴桨比在线寻优：r=Ω_u/Ω_l ∈[0.75,1.25] × 默认r=1 × γ干扰场(类比风) × 功率-桨比谷底r*≈0.89(飞试)',...
    'Position',[40 30 1500 960],'Color',[.96 .97 .98],'Visible',visible,...
    'AutoResizeChildren','off');
outer=uigridlayout(fig,[3 2]); outer.RowHeight={44,'1x',28}; outer.ColumnWidth={330,'1x'};
outer.Padding=[12 10 12 10]; outer.RowSpacing=10;
header=uilabel(outer,'Text','工作包w11 | 固定速度下上下桨转速比在线寻优 | r=Ω_u/Ω_l∈[0.75,1.25] | 曲线/γ干扰未知(调桨比→功率黑盒) | MOE=纯能耗(Emin/Eactual)',...
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
algorithm=choice(g,'控制策略',1,{'sweepcal全比域标定+精化','hybrid标定+探针混合',...
    'rl仿真器预训练+微调','purerl纯奖励RL(免标定)','openloop开环基线(r=1)',...
    'interfinfer已知曲线oracle参照','est已知曲线EKF(参照)','known已知γ场oracle上限'},...
    {'sweepcal','hybrid','rl','purerl','openloop','interfinfer','est','known'},'sweepcal');
scenarioC=choice(g,'干扰场景',2,{'static圆周运动','jumpUp干扰上跳','jumpDown干扰下跳',...
    'offset纯功率上移','ramp干扰慢漂'},{'static','jumpUp','jumpDown','offset','ramp'},'static');
flightModeC=choice(g,'飞行模式',3,{'hover悬停','fixed前飞固定V=6','vary变速V=6±2'},...
    {'hover','fixed','vary'},'fixed');
latSec=number(g,'通信时延 / s',4,0.3,[0 0.5]);
slewMax=number(g,'桨比限幅 / r·s⁻¹',5,0.15,[0.02 1.0]);
noise=number(g,'相对噪声标准差',6,0.01,[0 0.05]);
ripA1=number(g,'崎岖幅值A1',7,0.005,[0 0.02]);
ripL1=number(g,'崎岖波长λ1',8,0.18,[0.08 0.40]);
ripA2=number(g,'崎岖幅值A2',9,0.003,[0 0.015]);
ripL2=number(g,'崎岖波长λ2',10,0.06,[0.03 0.15]);
shiftTime=number(g,'跳变时刻 / 步',11,120,[30 350]);
shiftDg=number(g,'γ跳变幅值',12,0.06,[-0.10 0.10]);
seed=number(g,'随机种子',13,11,[1 100]);
gammaAmp=number(g,'γ幅值A (turb=湍动σ)',14,0.0,[0 0.20]);
gammaOmega=number(g,'γ角频率ω1 / rad·s⁻¹',15,0.08,[0 2]);
gammaBias=number(g,'γ偏置B',16,0.0,[-0.10 0.20]);
gammaKind=choice(g,'干扰场(选中即预览)',17,{'const 恒定干扰','sin 慢变正弦',...
    'square 方波(软边)','triangle 三角波','turb 湍动(OU)','composite 复合(推荐)','sector 扇区(随航向)'},...
    {'const','sin','square','triangle','turb','composite','sector'},'const');
sqEdge=number(g,'方波沿陡度k',18,4,[0.5 20]);
turbS=number(g,'湍动σ',19,0.015,[0 0.08]);
curveC=choice(g,'谷底深度case(谷底/等转速)',20,{'case1 97%','case2 95%','case3 92%'},...
    {0.97,0.95,0.92},0.95);
truth=uicheckbox(g,'Text','显示评价器曲线与真值','Value',true); put(truth,21,[1 2]);
speedLabel=uilabel(g,'Text','播放速度: 1.00x','FontName','Microsoft YaHei','FontSize',11); put(speedLabel,22,1);
speedSlider=uislider(g,'Limits',[0.5 8],'Value',1,'MajorTicks',[.5 1 2 4 8],...
    'MajorTickLabels',{'0.5x','1x','2x','4x','8x'}); put(speedSlider,22,2);
speedSlider.ValueChangedFcn=@(~,ev) setSpeed(ev.Value);
    function setSpeed(val)
        speedLabel.Text=sprintf('播放速度: %.2fx',val);
        if strcmp(clock.Running,'on'), clock.Period=.15/val; end
    end
actions=uigridlayout(left,[2 4]); put(actions,3,1); actions.Padding=[0 0 8 0];
actions.RowHeight={34,34}; actions.RowSpacing=7;
play=uibutton(actions,'Text','播放'); put(play,1,1); pauseBtn=uibutton(actions,'Text','暂停'); put(pauseBtn,1,2);
reset=uibutton(actions,'Text','重置'); put(reset,1,3); finish=uibutton(actions,'Text','末帧'); put(finish,1,4);
exportPng=uibutton(actions,'Text','导出PNG'); put(exportPng,2,1);
exportGif=uibutton(actions,'Text','导出GIF动画'); put(exportGif,2,[2 3]);
loadReportBtn=uibutton(actions,'Text','载入验收报告'); put(loadReportBtn,2,4);
% --- MOP/MOE 评价结果卡片 ---
resultCard=uipanel(left,'Title','★ MOP/MOE 评价结果(任务窗终点)','FontName','Microsoft YaHei',...
    'FontSize',11,'ForegroundColor',[.62 .08 .08],'HighlightColor',[.62 .08 .08]);
put(resultCard,4,1);
rg=uigridlayout(resultCard,[6 2]); rg.RowHeight={30,24,24,24,24,24};
rg.ColumnWidth={'1x','1x'}; rg.Padding=[8 2 8 2]; rg.RowSpacing=1;
mkTag=@(txt) uilabel(rg,'Text',txt,'FontName','Microsoft YaHei','FontSize',9,'FontColor',[.25 .25 .25]);
mkVal=@(sz) uilabel(rg,'Text','—','FontName','Microsoft YaHei','FontSize',sz,...
    'FontWeight','bold','HorizontalAlignment','right');
labOverallT=mkTag('MOE 综合效能 overall(=续航能耗Emin/Eactual)'); put(labOverallT,1,1);
labOverall=mkVal(15); put(labOverall,1,2); labOverall.FontColor=[.0 .45 .2];
labEnergyT=mkTag('续航能效 MOE_energy / 能耗超额'); put(labEnergyT,2,1);
labEnergy=mkVal(11); put(labEnergy,2,2);
labLiftT=mkTag('vs 开环基线(r=1): ΔMOE / 能耗相对变化'); put(labLiftT,3,1);
labLift=mkVal(11); put(labLift,3,2);
labInstT=mkTag('瞬时能效 instant / 桨比跟踪滞后'); put(labInstT,4,1);
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
phaseMap={'calib','标定';'refine','精调';'infer','推断';'probe','探针';...
    'settle','指令就位';'hold','锁定';'pure','纯RL';'rl','RL微调';'est','EKF';'oracle','oracle'};
controls=struct('algorithm',algorithm,'scenario',scenarioC,'flightModeC',flightModeC,...
    'latSec',latSec,'slewMax',slewMax,'noise',noise,...
    'ripA1',ripA1,'ripL1',ripL1,'ripA2',ripA2,'ripL2',ripL2,...
    'shiftTime',shiftTime,'shiftDg',shiftDg,'seed',seed,...
    'gammaAmp',gammaAmp,'gammaOmega',gammaOmega,'gammaBias',gammaBias,...
    'gammaKind',gammaKind,'sqEdge',sqEdge,'turbS',turbS,'curveC',curveC,'truth',truth,...
    'play',play,'pause',pauseBtn,'reset',reset,'finish',finish,...
    'exportPng',exportPng,'exportGif',exportGif,'speed',speedSlider);
fig.UserData=struct('controls',controls,'prepare',@prepare,'play',@playback,...
    'pause',@stopPlayback,'finish',@toEnd,'getLog',@getLog,'getCursor',@getCursor,...
    'timer',clock,'exportPng',@exportCurrent,'exportGif',@exportGifCurrent,...
    'logMsg',@logMsg,'loadReport',@loadReport,'clearLog',@clearLog,...
    'setView',@setView);
% ============ 飞机模型 & 环境模型 模块窗口 ============
airPanel=uipanel(plots,'Title','飞机模型：桨比+功率双表盘(黑箱仪表)','FontName','Microsoft YaHei',...
    'ForegroundColor',[.15 .3 .6],'HighlightColor',[.15 .3 .6]);
airPanel.Layout.Row=3; airPanel.Layout.Column=1;
ag=uigridlayout(airPanel,[5 2]); ag.RowHeight={150,16,16,16,34}; ag.ColumnWidth={'1x','1x'};
ag.Padding=[6 6 6 4]; ag.RowSpacing=4;
gRatio=uigauge(ag,'Limits',[0.7 1.3]); put(gRatio,1,1);
labRt=uilabel(ag,'Text','桨比表(实际 Ω_u/Ω_l)  黑箱读数','FontName','Microsoft YaHei','FontSize',9,'HorizontalAlignment','center'); put(labRt,2,1);
gPower=uigauge(ag,'Limits',[0.8 1.4]); put(gPower,1,2);
labPw=uilabel(ag,'Text','功率表 / 归一化(P(1)=1)','FontName','Microsoft YaHei','FontSize',9,'HorizontalAlignment','center'); put(labPw,2,2);
labHdg=uilabel(ag,'Text','航向: —','FontName','Microsoft YaHei','FontSize',10,'HorizontalAlignment','center'); put(labHdg,3,1);
labPos=uilabel(ag,'Text','位置: —','FontName','Microsoft YaHei','FontSize',10,'HorizontalAlignment','center'); put(labPos,3,2);
labMetrics=uilabel(ag,'Text','','FontName','Microsoft YaHei','FontSize',10,...
    'HorizontalAlignment','center'); put(labMetrics,4,[1 2]);
btnAirSize=uibutton(ag,'Text','放大 ⤢'); put(btnAirSize,5,[1 2]);
btnAirSize.ButtonPushedFcn=@(~,~)toggleSize('air');
envPanel=uipanel(plots,'Title','环境模型：盘旋航迹 × 干扰因子γ场(七种)',...
    'ForegroundColor',[.1 .45 .25],'HighlightColor',[.1 .45 .25]);
envPanel.Layout.Row=3; envPanel.Layout.Column=2;
eg=uigridlayout(envPanel,[2 2]); eg.RowHeight={'1x',28}; eg.ColumnWidth={'1x','1x'};
eg.Padding=[4 4 4 2]; eg.RowSpacing=2; eg.ColumnSpacing=8;
axEnv=uiaxes(eg); put(axEnv,1,1); disableDefaultInteractivity(axEnv); axEnv.Toolbar.Visible='off';
title(axEnv,'航迹(半径R=100m, 与指令解耦)','FontSize',8);
axGamma=uiaxes(eg); put(axGamma,1,2); disableDefaultInteractivity(axGamma); axGamma.Toolbar.Visible='off';
title(axGamma,'干扰因子γ曲线(选中模板即预览)','FontSize',9);
ylabel(axGamma,'γ','FontSize',8); xlabel(axGamma,'t / s','FontSize',8);
btnEnvSize=uibutton(eg,'Text','放大 ⤢'); put(btnEnvSize,2,[1 2]);
btnEnvSize.ButtonPushedFcn=@(~,~)toggleSize('env');
ud=fig.UserData; ud.airPanel=airPanel; ud.envPanel=envPanel;
ud.resultCard=struct('overall',labOverall,'energy',labEnergy,'lift',labLift,...
    'instant',labInst,'settle',labSet,'search',labSea); fig.UserData=ud;
% 环境模型静态要素(uiaxes平台怪癖: patch须先于line创建)
hTrail=line(axEnv,nan,nan,'Color',[.2 .4 .8],'LineWidth',.8,'DisplayName','航迹');
hPlane=line(axEnv,nan,nan,'Color',[.85 .18 .18],'Marker','>','MarkerFaceColor',...
    [.85 .18 .18],'MarkerSize',11,'LineStyle','none','DisplayName','飞机位置');
hHome=line(axEnv,nan,nan,'Color',[.4 .4 .4],'Marker','s','MarkerSize',8,...
    'LineStyle','none','DisplayName','盘旋中心');
hEnvTxt1=text(axEnv,0,0,'','FontName','Microsoft YaHei','FontSize',9,'Color',[.2 .2 .55]);
hEnvTxt1.HorizontalAlignment='center';
hCurveG=line(axGamma,nan,nan,'Color',[.0 .55 .25],'LineWidth',1.2,'DisplayName','γ(t)');
hNowG=line(axGamma,nan,nan,'Color',[.5 .2 .7],'Marker','o','MarkerFaceColor',...
    [.5 .2 .7],'MarkerSize',4,'LineStyle','none','DisplayName','当前γ');
hOne=line(axGamma,nan,nan,'Color',[.6 .6 .6],'LineStyle','--','LineWidth',.5,'DisplayName','γ=1(基准)');
legend(axGamma,'Location','southoutside','Orientation','horizontal','FontSize',7);
ctrlList={algorithm,scenarioC,flightModeC,latSec,slewMax,noise,ripA1,ripL1,ripA2,ripL2,...
    shiftTime,shiftDg,seed,gammaAmp,gammaOmega,gammaBias,gammaKind,sqEdge,turbS,curveC};
for cn=ctrlList
    cn{1}.ValueChangedFcn=@changed;
end
curveC.ValueChangedFcn=@caseChanged;
gammaKind.ValueChangedFcn=@gammaKindChanged;   % 切换模板即自动载入推荐参数
gammaAmp.ValueChangedFcn=@gammaChanged; gammaOmega.ValueChangedFcn=@gammaChanged;
gammaBias.ValueChangedFcn=@gammaChanged; sqEdge.ValueChangedFcn=@gammaChanged;
turbS.ValueChangedFcn=@gammaChanged;
truth.ValueChangedFcn=@(~,~)redraw();
play.ButtonPushedFcn=@playback; pauseBtn.ButtonPushedFcn=@stopPlayback;
reset.ButtonPushedFcn=@prepare; finish.ButtonPushedFcn=@toEnd;
exportPng.ButtonPushedFcn=@exportCurrent; exportGif.ButtonPushedFcn=@exportGifCurrent;
loadReportBtn.ButtonPushedFcn=@loadReport;
btnConsole.ButtonPushedFcn=@(~,~)setView('console');
btnAir.ButtonPushedFcn=@(~,~)setView('air');
btnEnv.ButtonPushedFcn=@(~,~)setView('env');
fig.CloseRequestFcn=@closeApp; fig.SizeChangedFcn=@resizeLayout;
setupPanels(); resizeLayout(); highlightButtons();
logMsg('工作包w11 共轴桨比在线寻优就绪 | 控制量r=Ω_u/Ω_l∈[0.75,1.25], 默认r=1(等转速分配) | 真值: Opazo MT链功率-桨比曲线, 谷底r*≈0.89(飞试锚点) | γ干扰场类比风(七种模板)');
logMsg('左上图读法: 全图同一自变量域r——蓝真值曲线/绿拟合f̂/彩色采样点都在r域; 红五角星=r*(t)真值, 紫五角星=算法谷底估计r̂*');
logMsg('对象黑箱: 只给"调桨比→带噪总功率"+时延(0.3s)+桨比限幅(0.15 r/s)+就位规则; known/interfinfer/est为oracle参照(非因果)');
logMsg('开环基线r=1的固有超额≈1/case−1≈5.3%(case=0.95), 即Opazo飞试"差速分配节能≈5%"的口径来源; 结果为proxy等级, 不支持实机节能表述');
if exist(fullfile(root,'results','report.md'),'file')
    loadReport();
else
    logMsg('尚未生成验收报告: 命令行运行 run_checks 后点"载入验收报告"');
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
        gRatio.Value=L.ratio(k);
        gPower.Value=L.powerTrue(k);
        tailExcess=100*sum(L.powerTrue(1:k)-L.minPowerTrue(1:k))/max(sum(L.minPowerTrue(1:k)),eps);
        labMetrics.Text=sprintf(['桨比(实际) %.3f | 指令 %.3f | γ真值 %.3f | 航向 %3.0f° | ',...
            '功率真值 %.3f | 测量 %.3f | 累计能耗超额 %.2f%%'],...
            L.ratio(k),L.ratioCmd(k),L.gammaTrue(k),mod(rad2deg(psi),360),...
            L.powerTrue(k),L.powerMeas(k),tailExcess);
        labPos.Text=sprintf('位置: (%+.0f, %+.0f) m',px,py);
        labHdg.Text=sprintf('航向: %3.0f°',mod(rad2deg(psi),360));
        thet=linspace(0,2*pi,181);
        hTrail.XData=R*cos(thet); hTrail.YData=R*sin(thet);
        hPlane.XData=px; hPlane.YData=py;
        hHome.XData=0; hHome.YData=0;
        hEnvTxt1.Position=[0,-R*0.25,0];
        hEnvTxt1.String=sprintf('γ真值 %.3f (基准1.0) | 飞行速度 %.1f m/s | 桨比限幅 %.2f r/s',...
            L.gammaTrue(k),L.flightV(k),c.slewMax);
        axis(axEnv,'equal');
        xlim(axEnv,[-R*1.15 R*1.15]); ylim(axEnv,[-R*1.3 R*1.32]);
        xlabel(axEnv,'x / m'); ylabel(axEnv,'y / m');
        if strcmp(c.gammaKind,'sector')   % 扇区干扰: 横轴=航向
            psd=linspace(0,360,361);
            [gC,~]=w11.interfer_field(scn,0,deg2rad(psd));
            hCurveG.XData=psd; hCurveG.YData=gC;
            hNowG.XData=mod(rad2deg(psi),360); hNowG.YData=L.gammaTrue(k);
            hOne.XData=[0 360]; hOne.YData=[1 1];
            xlim(axGamma,[0 360]);
            ylim(axGamma,[min(gC)-0.03,max(gC)+0.03]);
        else
            tt=linspace(0,c.duration*c.tEval,600);
            [gC,~]=w11.interfer_field(scn,tt,0);
            hCurveG.XData=tt; hCurveG.YData=gC;
            hNowG.XData=tNow; hNowG.YData=L.gammaTrue(k);
            hOne.XData=[0 tt(end)]; hOne.YData=[1 1];
            xlim(axGamma,[0 tt(end)]);
            ylim(axGamma,[min(gC)-0.03,max(gC)+0.03]);
        end
    end

    function resizeLayout(varargin)
        bodyHeight=max(440,fig.InnerPosition(4)-112);
        outer.RowHeight={44,bodyHeight,28};
        avail=max(500,bodyHeight)-448;
            formH=max(230,round(0.45*avail)); logH=max(150,avail-formH);
            leftLayout.RowHeight={38,formH,150,175,30,logH};
    end

    function changed(varargin)
        stopPlayback(); dirty=true; status.Text='参数已更改，按"重置"或"播放"生效';
    end

    function buildConfig()
        c=w11.config('noiseSigma',noise.Value,'ratioCase',curveC.Value,...
            'latencySec',latSec.Value,'slewMax',slewMax.Value,...
            'rippleA1',ripA1.Value,'rippleL1',ripL1.Value,...
            'rippleA2',ripA2.Value,'rippleL2',ripL2.Value,...
            'shiftTime',shiftTime.Value,'seed',seed.Value,...
            'flightMode',flightModeC.Value,...
            'gammaAmp',gammaAmp.Value,'gammaOmega',gammaOmega.Value,'gammaBias',gammaBias.Value,...
            'gammaKind',gammaKind.Value,'squareEdge',sqEdge.Value,'turbStd',turbS.Value);
        if strcmp(scenarioC.Value,'jumpUp'), c.jumpUpDg=shiftDg.Value; end
        if strcmp(scenarioC.Value,'jumpDown'), c.jumpDownDg=shiftDg.Value; end
    end

    function prepare(varargin)
        stopPlayback();
        try
            buildConfig();
            drawCasePreview();
            scn=w11.scenario(scenarioC.Value,c);
            [L,info]=w11.run_algorithm(algorithm.Value,scn,c);
            n=height(L);
            cumEnergy=100*cumsum(L.powerTrue-L.minPowerTrue)./cumsum(L.minPowerTrue);
            estError=abs(L.estimate-L.optimumTrue);
            mopFinal=w11.mop_moe(L,c);
            % 开环基线对照: 同对象/同预算/同种子
            if strcmp(algorithm.Value,'openloop')
                Lb=L; mBase=mopFinal;
            else
                [Lb,~]=w11.run_algorithm('openloop',scn,c);
                mBase=w11.mop_moe(Lb,c);
            end
            cursor=1; dirty=false; redraw(); status.Text='就绪';
            if any(strcmp(gammaKind.Value,{'turb','composite'}))
                tn=sprintf('| 湍动σ=%.3f ',turbS.Value);
            else
                tn='';
            end
            logMsg(sprintf(['重置完成: 策略=%s 场景=%s 飞行模式=%s γ场=%s 时延=%.1fs 限幅=%.2fr/s '...
                '种子=%d | γ参数: A=%.3f B=%.3f %s'],algorithm.Value,scenarioC.Value,...
                flightModeC.Value,gammaKind.Value,latSec.Value,slewMax.Value,...
                seed.Value,gammaAmp.Value,gammaBias.Value,tn));
            if isstruct(info) && isfield(info,'rStar')
                logMsg(sprintf('策略%s: 谷底估计 r̂*=%.3f (评价侧真值 r*=%.3f) | 标定%d步 拟合RMS %.4f',...
                    algorithm.Value,info.rStar,c.rStar0+w11.drift_of(1.08,c)*(strcmp(gammaKind.Value,'const')&&abs(gammaBias.Value-0.08)<1e-9),...
                    info.calibSteps,info.fitRms));
            end
            if strcmp(algorithm.Value,'purerl') && isstruct(info) && isfield(info,'muB')
                logMsg(sprintf('纯奖励RL(免标定): 对偶探索σ=%.3f→%.3f | μ轮廓幅值=%.3f | 终态σ=%.3f',...
                    info.sigma0,info.sigma,max(info.muB)-min(info.muB),info.sigma));
            end
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
        m=w11.mop_moe(L,c);
        status.Text=sprintf(['MOE=%.4f | 末误差 %.3f | 稳态超额 %.3f%% | '...
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
        labEnergy.Text=sprintf('%.4f (超额 %.2f%%)',m.MOE_energy,m.energyExcessPercent);
        mb=mBase;
        if strcmp(algorithm.Value,'openloop')
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
        labInst.Text=sprintf('%.4f / %.3f',m.MOE_instant,m.MOP.meanTrackLag);
        labSet.Text=sprintf('%g 步 / %.1f%%',m.MOP.settleSteps,100*m.MOE_availability);
        labSea.Text=sprintf('%d 步 / σ=%.3f',m.MOP.searchSteps,m.MOP.steadyFluct);
        logMsg(sprintf(['MOP/MOE汇总: overall=%.4f | MOE_energy=%.4f | 开环基线MOE=%.4f | '...
            'ΔMOE=%+.4f | 可用率=%.1f%% | 末误差=%.3f | 跟踪滞后=%.3f | '...
            '搜索步数=%d(就位占%.0f%%) | 峰值桨比变化率=%.3f r/s'],...
            m.MOE.overall,m.MOE_energy,mBase.MOE_energy,...
            m.MOE_energy-mBase.MOE_energy,100*m.MOE_availability,...
            m.finalErr,m.MOP.meanTrackLag,m.MOP.searchSteps,...
            100*m.MOP.settleQueryRatio,m.MOP.slewMaxUsed));
    end

    function setupPanels()
        hold(ax(1),'on'); hold(ax(2),'on'); hold(ax(3),'on'); hold(ax(4),'on');
        % 前三条为case族的真值曲线预览(选中的加粗)
        h.case1=line(ax(1),nan,nan,'Color',[.75 .75 .75],'LineWidth',.8,'DisplayName','case1 谷底97%');
        h.case2=line(ax(1),nan,nan,'Color',[.75 .75 .75],'LineWidth',.8,'DisplayName','case2 谷底95%');
        h.case3=line(ax(1),nan,nan,'Color',[.75 .75 .75],'LineWidth',.8,'DisplayName','case3 谷底92%');
        h.curve=line(ax(1),nan,nan,'Color',[.3 .5 .8],'LineStyle','-.','LineWidth',1.2,...
            'DisplayName','真值曲线(当前γ, 评价器)');
        h.rstar=line(ax(1),nan,nan,'Color',[.85 .18 .18],'Marker','p','MarkerFaceColor',...
            [.85 .18 .18],'LineStyle','none','MarkerSize',13,'DisplayName','r*(t) 真值最优');
        h.ptHold=line(ax(1),nan,nan,'Color',[.55 .55 .55],'Marker','.','LineStyle','none',...
            'MarkerSize',7,'DisplayName','hold锁定');
        h.ptSettle=line(ax(1),nan,nan,'Color',[.7 .7 .3],'Marker','x','LineStyle','none',...
            'MarkerSize',5,'DisplayName','settle就位');
        h.ptProbe=line(ax(1),nan,nan,'Color',[.0 .65 .3],'Marker','.','LineStyle','none',...
            'MarkerSize',12,'DisplayName','probe探针');
        h.ptRefine=line(ax(1),nan,nan,'Color',[.85 .3 .1],'Marker','.','LineStyle','none',...
            'MarkerSize',12,'DisplayName','refine精调');
        h.ptCalib=line(ax(1),nan,nan,'Color',[.45 .2 .65],'Marker','^','LineStyle','none',...
            'MarkerSize',4,'DisplayName','calib全比域标定采样');
        h.ptPure=line(ax(1),nan,nan,'Color',[.95 .5 .05],'Marker','.','LineStyle','none',...
            'MarkerSize',9,'DisplayName','pure纯RL探索');
        h.ptInfer=line(ax(1),nan,nan,'Color',[.55 .3 .75],'Marker','.','LineStyle','none',...
            'MarkerSize',9,'DisplayName','infer/EKF');
        h.fitCurve=line(ax(1),nan,nan,'Color',[.0 .55 .25],'LineWidth',2.0,...
            'DisplayName','拟合曲线f̂(算法自己学的)');
        h.rStarHat=line(ax(1),nan,nan,'Color',[.62 .16 .86],'Marker','p','LineStyle','none',...
            'MarkerFaceColor',[.62 .16 .86],'MarkerSize',12,'DisplayName','r̂* 拟合谷底');
        xlabel(ax(1),'桨比 r = Ω_u/Ω_l'); ylabel(ax(1),'功率 / 归一化(P(1)=1)');
        drawCasePreview(); gammaPreview();
        title(ax(1),'功率-桨比曲线(全图同一自变量域r): 蓝真值/绿拟合/采样点 | 红星r*真值, 紫星r̂*');
        legend(ax(1),'Location','northwest','NumColumns',2,'FontSize',7);
        h.ratio=line(ax(2),nan,nan,'Color',[.2 .4 .8],'LineWidth',.8,'DisplayName','实际桨比');
        h.cmd=line(ax(2),nan,nan,'Color',[.55 .3 .75],'LineWidth',.6,'LineStyle',':','DisplayName','指令桨比');
        h.estimate=line(ax(2),nan,nan,'Color',[.0 .55 .25],'LineWidth',1.5,'DisplayName','估计(调度目标)');
        h.optimum=line(ax(2),nan,nan,'Color',[.85 .18 .18],'LineStyle','--','LineWidth',1.3,'DisplayName','r*(t) 真值');
        h.rhatT=line(ax(2),nan,nan,'Color',[.62 .16 .86],'LineStyle','-.','LineWidth',1.8,'DisplayName','r̂*(t) 谷底在线估计(紫)');
        xlabel(ax(2),'评估步'); ylabel(ax(2),'桨比 r = Ω_u/Ω_l');
        title(ax(2),'桨比演化 vs r* 真值'); legend(ax(2),'Location','northeast','NumColumns',2,'FontSize',7);
        h.pTrue=line(ax(3),nan,nan,'Color',[.2 .3 .4],'LineWidth',.9,'DisplayName','真实功率');
        h.pMin=line(ax(3),nan,nan,'Color',[.85 .18 .18],'LineStyle','--','LineWidth',1.1,'DisplayName','Pmin(t) 理论最低');
        h.pMeas=line(ax(3),nan,nan,'Color',[.55 .3 .7],'Marker','.','LineStyle','none',...
            'MarkerSize',6,'DisplayName','带噪测量');
        xlabel(ax(3),'评估步'); ylabel(ax(3),'功率 / 归一化');
        title(ax(3),'功率轨迹'); legend(ax(3),'Location','north','FontSize',8);
        h.metric=line(ax(4),nan,nan,'Color',[.8 .45 .1],'LineWidth',1.3);
        xlabel(ax(4),'评估步'); title(ax(4),'累计能耗超额(续航口径)');
    end

    function caseChanged(varargin)
        dirty=true;
        drawCasePreview();
        status.Text=sprintf('case已切换: 谷底=%.0f%%×等转速功率, 曲线预览已更新; 按"重置/播放"生效',curveC.Value*100);
        logMsg(status.Text);
    end

    function gammaKindChanged(varargin)
        applyGammaPreset(gammaKind.Value);
        gammaChanged();
        logMsg('已载入该干扰模板的推荐参数(幅值/频率/偏置/湍动σ), 可在左侧继续修改, 即改即预览');
    end

    function applyGammaPreset(k)
        switch k
            case 'const'    % 无干扰对照口径
                gammaAmp.Value=0.0; gammaOmega.Value=0.08; gammaBias.Value=0.0;
                sqEdge.Value=4.0; turbS.Value=0.015;
            case 'sin'
                gammaAmp.Value=0.04; gammaOmega.Value=0.08; gammaBias.Value=0.02;
                sqEdge.Value=4.0; turbS.Value=0.015;
            case 'square'
                gammaAmp.Value=0.04; gammaOmega.Value=0.08; gammaBias.Value=0.02;
                sqEdge.Value=4.0; turbS.Value=0.015;
            case 'triangle'
                gammaAmp.Value=0.04; gammaOmega.Value=0.08; gammaBias.Value=0.02;
                sqEdge.Value=4.0; turbS.Value=0.015;
            case 'turb'     % OU湍动: A=湍动强度(均值=B)
                gammaAmp.Value=0.05; gammaBias.Value=0.0;
            case 'composite' % 复合(推荐, 3×3表"漂移干扰"口径): 慢变+湍动
                gammaAmp.Value=0.04; gammaOmega.Value=0.08; gammaBias.Value=0.0;
                turbS.Value=0.015;
            case 'sector'   % 扇区(随航向)
                gammaAmp.Value=0.05; gammaBias.Value=0.0;
        end
    end

    function gammaChanged(varargin)
        stopPlayback();
        dirty=true;
        gammaPreview();
        status.Text='干扰场已切换: γ曲线已即时预览(无需运行); 按"重置/播放"生效';
        logMsg(sprintf('干扰模板: %s | A=%.3f ω1=%.2f B=%.3f | k=%.1f σ=%.3f',...
            gammaKind.Value,gammaAmp.Value,gammaOmega.Value,gammaBias.Value,...
            sqEdge.Value,turbS.Value));
    end

    function gammaPreview()
        % 运行前即时预览: 按当前UI参数装配γ场并画曲线(时间类横轴=t, 扇区横轴=ψ)
        buildConfig();
        pvScn=w11.scenario(scenarioC.Value,c);
        hNowG.XData=NaN;
        if strcmp(c.gammaKind,'sector')
            psd=linspace(0,360,721);
            [gP,~]=w11.interfer_field(pvScn,0,deg2rad(psd));
            hCurveG.XData=psd; hCurveG.YData=gP;
            hOne.XData=[0 360]; hOne.YData=[1 1];
            xlim(axGamma,[0 360]);
            title(axGamma,'扇区干扰预览: γ随航向ψ(盘旋一圈即采样一遍)','FontSize',9);
            xlabel(axGamma,'航向 ψ / °','FontSize',8);
        else
            tt=linspace(0,c.duration*c.tEval,900);
            [gP,~]=w11.interfer_field(pvScn,tt,0);
            hCurveG.XData=tt; hCurveG.YData=gP;
            hOne.XData=[0 tt(end)]; hOne.YData=[1 1];
            xlim(axGamma,[0 tt(end)]);
            title(axGamma,'干扰因子γ曲线(运行前预览)','FontSize',9);
            xlabel(axGamma,'t / s','FontSize',8);
        end
        ylim(axGamma,[min(gP)-0.03,max(gP)+0.03]);
    end

    function drawCasePreview()
        if isempty(c), buildConfig(); end
        vv=linspace(c.lower,c.upper,400);
        cv=[0.97 0.95 0.92];
        hds=[h.case1,h.case2,h.case3];
        for q=1:3
            cc=w11.config(c,'ratioCase',cv(q));
            hds(q).XData=vv; hds(q).YData=w11.truth_curve(vv,cc);
            if abs(curveC.Value-cv(q))<1e-9
                hds(q).Color=[.85 .33 .1]; hds(q).LineWidth=2.4;
            else
                hds(q).Color=[.75 .75 .75]; hds(q).LineWidth=0.8;
            end
        end
        ylim(ax(1),[0.88 1.32]);
        legend(ax(1),'Location','northwest','NumColumns',2,'FontSize',7);
    end

    function redraw()
        if isempty(L), return; end
        n=height(L); k=cursor;
        vis=truth.Value;
        tags=string(L.tag(1:k)); rr=L.ratio(1:k); pm=L.powerMeas(1:k);
        tNow=L.time(k);
        % 左上: 全图同一自变量域r——真值曲线(当前γ) + 采样点
        psiK=deg2rad(L.headingDeg(k));
        [~,gEffK]=w11.interfer_field(scn,tNow,psiK);
        [dGamK,dyK]=w11.shift_truth(scn,tNow);
        [dxK,dlevK]=w11.drift_of(gEffK+dGamK,c);
        fVK=w11.fwd_level(L.flightV(k),c);
        vv=linspace(c.lower,c.upper,400);
        if vis
            h.curve.XData=vv;
            h.curve.YData=dlevK*fVK*w11.truth_curve(vv-dxK,c) + fVK*dyK;
            h.rstar.XData=L.optimumTrue(k); h.rstar.YData=L.minPowerTrue(k);
        else
            h.curve.XData=nan; h.curve.YData=nan;
            h.rstar.XData=nan; h.rstar.YData=nan;
        end
        setSlice(h.ptCalib,rr,pm,tags,'calib');
        setSlice(h.ptRefine,rr,pm,tags,'refine');
        setSlice(h.ptHold,rr,pm,tags,'hold');
        setSlice(h.ptSettle,rr,pm,tags,'settle');
        setSlice(h.ptProbe,rr,pm,tags,'probe');
        setSlice(h.ptPure,rr,pm,tags,'pure');
        setSlice(h.ptInfer,rr,pm,tags,{'infer','est','rl','oracle'});
        if any(strcmp(algorithm.Value,{'hybrid','sweepcal','rl'})) && isstruct(info) && isfield(info,'coefs') ...
                && all(isfinite(info.coefs))
            uu=linspace(info.rLo,info.rHi,200); xg=(uu-1.0)/0.25; cf=info.coefs;
            thK=info.thFinal;
            uu2=uu-(thK(1)+thK(2)*cos(psiK)+thK(3)*sin(psiK));
            h.fitCurve.XData=uu;
            h.fitCurve.YData=(cf(1)+cf(2)*xg+cf(3)*xg.^2+cf(4)*xg.^3+cf(5)*xg.^4)*dlevK*fVK;
            xg0=(info.rStar-1.0)/0.25;   % r̂*标记: 拟合谷底落在r域哪里, 一眼可见
            h.rStarHat.XData=info.rStar;
            h.rStarHat.YData=(cf(1)+cf(2)*xg0+cf(3)*xg0^2+cf(4)*xg0^3+cf(5)*xg0^4)*dlevK*fVK;
        else
            h.fitCurve.XData=nan; h.fitCurve.YData=nan;
            h.rStarHat.XData=nan; h.rStarHat.YData=nan;
        end
        % 右上: 桨比演化 vs r* 真值
        h.ratio.XData=(1:k)'; h.ratio.YData=rr;
        h.cmd.XData=(1:k)'; h.cmd.YData=L.ratioCmd(1:k);
        h.estimate.XData=(1:k)'; h.estimate.YData=L.estimate(1:k);
        if vis, h.optimum.XData=(1:k)'; h.optimum.YData=L.optimumTrue(1:k);
        else, h.optimum.XData=nan; h.optimum.YData=nan; end
        if any(strcmp(algorithm.Value,{'hybrid','sweepcal','rl'})) && isstruct(info) && isfield(info,'rHat')
            h.rhatT.XData=(1:k)'; h.rhatT.YData=info.rHat(1:k);
        else
            h.rhatT.XData=nan; h.rhatT.YData=nan;
        end
        xlim(ax(2),[1 n]); ylim(ax(2),[c.lower-0.02,c.upper+0.02]);
        % 左下
        h.pTrue.XData=(1:k)'; h.pTrue.YData=L.powerTrue(1:k);
        h.pMeas.XData=(1:k)'; h.pMeas.YData=pm;
        if vis, h.pMin.XData=(1:k)'; h.pMin.YData=L.minPowerTrue(1:k);
        else, h.pMin.XData=nan; h.pMin.YData=nan; end
        xlim(ax(3),[1 n]);
        % 右下
        xlim(ax(4),[1 n]);
        h.metric.YData=cumEnergy(1:k);
        h.metric.XData=(1:k)';
        ph='—';
        for q=1:size(phaseMap,1)
            if any(strcmp(char(tags(k)),phaseMap{q,1})), ph=phaseMap{q,2}; end
        end
        readout.Text=sprintf(['步 %d/%d | 相位 %s | 指令 %.3f | 实际 %.3f | r*(t) %.3f'...
            ' | γ真值 %.3f | 航向 %3.0f°'],...
            k,n,ph,L.ratioCmd(k),L.ratio(k),L.optimumTrue(k),L.gammaTrue(k),...
            mod(rad2deg(psiK),360));
        updateModules(k);
        drawnow limitrate;
    end

    function setSlice(hdl,sp,pm,tags,name)
        if iscell(name), hit=false(size(tags));
            for q=1:numel(name), hit=hit|strcmp(tags,name{q}); end
        else
            hit=strcmp(tags,name);
        end
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
            logMsg('未找到验收报告: 请先在命令行运行 run_checks');
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
