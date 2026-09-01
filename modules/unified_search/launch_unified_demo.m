function fig = launch_unified_demo(visible)
%LAUNCH_UNIFIED_DEMO 统一程序动画面板：任务1平移 × 任务2崎岖 × MOP/MOE。
% 交互约定与 launch_speed_esc 一致：面板只回放已完成的因果仿真。
%
% 四联图(逐帧)：
%   左上 功率曲线(当前时刻, 含平移) + 按相位着色查询点 + v*(t) 星标
%   右上 速度演化：估计 vs 时变真值 v*(t)（平移时红线台阶移动）
%   左下 功率轨迹：真实/测量/理论最低 Pmin(t)
%   右下 评价口径(能耗开关切换)：累计能量超额% ↔ 估计误差(对数)
if nargin<1, visible='on'; end
root=fileparts(mfilename('fullpath')); addpath(root);
fig=uifigure('Name','统一速度寻优：平移×崎岖×MOP/MOE(动态演示)',...
    'Position',[60 40 1420 940],'Color',[.96 .97 .98],'Visible',visible,...
    'AutoResizeChildren','off');
outer=uigridlayout(fig,[3 2]); outer.RowHeight={44,'1x',28}; outer.ColumnWidth={315,'1x'};
outer.Padding=[12 10 12 10]; outer.RowSpacing=10;
header=uilabel(outer,'Text','统一速度寻优程序 | 任务1平移×任务2崎岖·调试二次曲线基准·代理模型',...
    'FontName','Microsoft YaHei','FontSize',17,'FontWeight','bold'); put(header,1,[1 2]);
left=uigridlayout(outer,[4 1]); put(left,2,1); left.RowHeight={'1x',150,30,'1x'};
left.Padding=[0 0 0 0]; left.RowSpacing=8;
form=uipanel(left,'BorderType','none'); put(form,1,1);
g=uigridlayout(form,[15 2]); g.ColumnWidth={140,'1x'};
g.RowHeight=[repmat({30},1,11),{26,30,26,30}];
g.Padding=[0 0 8 0]; g.RowSpacing=7; g.Scrollable='on';
algorithm=choice(g,'搜索算法',1,{'tracker平移跟踪','esc连续ESC'},...
    {'tracker','esc'},'tracker');
scenarioC=choice(g,'平移场景',2,{'static静态','jumpUp上跳','jumpDown下跳',...
    'offset纯上移','ramp慢漂'},{'static','jumpUp','jumpDown','offset','ramp'},'jumpUp');
initial=number(g,'初始速度 / m/s',3,10,[0 20]);
noise=number(g,'相对噪声标准差',4,0.01,[0 0.05]);
ripA1=number(g,'崎岖幅值A1',5,0.022,[0 0.06]);
ripL1=number(g,'崎岖波长λ1 / m',6,6.0,[2 12]);
ripA2=number(g,'崎岖幅值A2',7,0.012,[0 0.06]);
ripL2=number(g,'崎岖波长λ2 / m',8,2.0,[1 6]);
shiftTime=number(g,'平移时刻 / 步',9,120,[30 350]);
shiftDx=number(g,'跳变幅值dx / m/s',10,2.7,[-6 6]);
seed=number(g,'随机种子',11,11,[1 100]);
truth=uicheckbox(g,'Text','显示评价器曲线与真值','Value',true); put(truth,12,[1 2]);
energy=uicheckbox(g,'Text','搜索能耗计入评价(续航口径)','Value',true); put(energy,13,[1 2]);
speedLabel=uilabel(g,'Text','播放速度: 1.00x','FontName','Microsoft YaHei','FontSize',11); put(speedLabel,14,1);
speedSlider=uislider(g,'Limits',[0.5 8],'Value',1,'MajorTicks',[.5 1 2 4 8],...
    'MajorTickLabels',{'0.5x','1x','2x','4x','8x'}); put(speedSlider,14,2);
speedSlider.ValueChangedFcn=@(~,ev) setSpeed(ev.Value);
    function setSpeed(val)
        speedLabel.Text=sprintf('播放速度: %.2fx',val);
        if strcmp(clock.Running,'on'), clock.Period=.15/val; end
    end
actions=uigridlayout(left,[3 4]); put(actions,2,1); actions.Padding=[0 0 8 0];
actions.RowHeight={34,34,34}; actions.RowSpacing=7;
play=uibutton(actions,'Text','播放'); put(play,1,1); pauseBtn=uibutton(actions,'Text','暂停'); put(pauseBtn,1,2);
reset=uibutton(actions,'Text','重置'); put(reset,1,3); finish=uibutton(actions,'Text','末帧'); put(finish,1,4);
exportPng=uibutton(actions,'Text','导出PNG'); put(exportPng,2,1);
exportGif=uibutton(actions,'Text','导出GIF动画'); put(exportGif,2,[2 4]);
readout=uilabel(left,'Text','','WordWrap','on','FontName','Microsoft YaHei'); put(readout,3,1);
logBox=uitextarea(left,'Editable','off','FontName','Microsoft YaHei','FontSize',9); put(logBox,4,1);
plots=uigridlayout(outer,[2 2]); put(plots,2,2); plots.Padding=[0 0 0 0]; plots.RowSpacing=14;
ax=gobjects(1,4); for k=1:4, ax(k)=uiaxes(plots); disableDefaultInteractivity(ax(k)); ax(k).Toolbar.Visible='off'; end
status=uilabel(outer,'Text','就绪','FontName','Microsoft YaHei'); put(status,3,2);
clock=timer('ExecutionMode','fixedSpacing','Period',.15,'BusyMode','drop','TimerFcn',@tick);
L=table(); info=[]; scn=[]; c=[]; cursor=1; dirty=true; h=struct(); phaseMap=[];
cumEnergy=[]; estError=[]; mopFinal=[];
phaseMap={'local','局部';'sigma','噪声估计';'far','远点证据';'scan','扫描';...
    'refine','精调';'polish','顶点';'hold','锁定';'probe','复探';...
    'search','搜索';'esc','ESC'};
controls=struct('algorithm',algorithm,'scenario',scenarioC,'initial',initial,...
    'noise',noise,'ripA1',ripA1,'ripL1',ripL1,'ripA2',ripA2,'ripL2',ripL2,...
    'shiftTime',shiftTime,'shiftDx',shiftDx,'seed',seed,'truth',truth,'energy',energy,...
    'play',play,'pause',pauseBtn,'reset',reset,'finish',finish,...
    'exportPng',exportPng,'exportGif',exportGif,'speed',speedSlider);
fig.UserData=struct('controls',controls,'prepare',@prepare,'play',@playback,...
    'pause',@stopPlayback,'finish',@toEnd,'getLog',@getLog,'getCursor',@getCursor,...
    'timer',clock,'exportPng',@exportCurrent,'exportGif',@exportGifCurrent,...
    'logMsg',@logMsg,'loadReport',@loadReport,'clearLog',@clearLog);
for cn={algorithm,scenarioC,initial,noise,ripA1,ripL1,ripA2,ripL2,shiftTime,shiftDx,seed}
    cn{1}.ValueChangedFcn=@changed;
end
truth.ValueChangedFcn=@(~,~)redraw(); energy.ValueChangedFcn=@(~,~)redraw();
play.ButtonPushedFcn=@playback; pauseBtn.ButtonPushedFcn=@stopPlayback;
reset.ButtonPushedFcn=@prepare; finish.ButtonPushedFcn=@toEnd;
exportPng.ButtonPushedFcn=@exportCurrent; exportGif.ButtonPushedFcn=@exportGifCurrent;
loadReportBtn=uibutton(actions,'Text','载入验收报告'); put(loadReportBtn,3,1);
loadReportBtn.ButtonPushedFcn=@loadReport;
clearLogBtn=uibutton(actions,'Text','清空日志'); put(clearLogBtn,3,[2 4]);
clearLogBtn.ButtonPushedFcn=@clearLog;
fig.CloseRequestFcn=@closeApp; fig.SizeChangedFcn=@resizeLayout;
setupPanels(); resizeLayout();
logMsg('统一速度寻优程序就绪 | 算法: tracker平移跟踪 / esc连续ESC');
logMsg('提示: 本面板仅提供tracker与esc两个算法, 其余算法保留于+usearch作对照');
if exist(fullfile(root,'results','report.md'),'file')
    loadReport();
else
    logMsg('尚未生成验收报告: 命令行运行 run_unified_acceptance 后点"载入验收报告"');
end
prepare();

    function resizeLayout(varargin)
        bodyHeight=max(420,fig.InnerPosition(4)-112);
        outer.RowHeight={44,bodyHeight,28};
        % 4行左栏: 参数区(可滚动) / 按钮 / 读数 / 日志栏
        left.RowHeight={max(240,bodyHeight-390),150,30,max(170,bodyHeight-420)};
    end

    function changed(varargin)
        stopPlayback(); dirty=true; status.Text='参数已更改，按"重置"或"播放"生效';
    end

    function buildConfig()
        cc=usearch.config('initialSpeed',initial.Value,'noiseSigma',noise.Value,...
            'rippleA1',ripA1.Value,'rippleL1',ripL1.Value,...
            'rippleA2',ripA2.Value,'rippleL2',ripL2.Value,...
            'shiftTime',shiftTime.Value,'seed',seed.Value);
        % 跳变幅值: 场景映射
        if strcmp(scenarioC.Value,'jumpUp'), cc.jumpUpDx=shiftDx.Value; end
        if strcmp(scenarioC.Value,'jumpDown'), cc.jumpDownDx=shiftDx.Value; end
        c=cc;
    end

    function prepare(varargin)
        stopPlayback();
        try
            buildConfig();
            scn=usearch.scenario(scenarioC.Value,c);
            [L,info]=usearch.run_algorithm(algorithm.Value,scn,c);
            n=height(L);
            cumEnergy=100*cumsum(L.powerTrue-L.minPowerTrue)./cumsum(L.minPowerTrue);
            estError=abs(L.estimate-L.optimumTrue);
            mopFinal=usearch.mop_moe(L,c);
            cursor=1; dirty=false; redraw(); status.Text='就绪';
            logMsg(sprintf(['重置完成: 算法=%s 场景=%s 初速=%.1f 噪声=%.3f '...
                'A1=%.3f λ1=%.1f A2=%.3f λ2=%.1f 跳变@%d步dx=%+.1f 种子=%d'],...
                algorithm.Value,scenarioC.Value,initial.Value,noise.Value,...
                ripA1.Value,ripL1.Value,ripA2.Value,ripL2.Value,...
                shiftTime.Value,shiftDx.Value,seed.Value));
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
        m=usearch.mop_moe(L,c);
        if isnan(m.MOE_energy), moeTxt='—'; else, moeTxt=sprintf('%.4f',m.MOE_energy); end
        status.Text=sprintf(['MOE=%.4f | 末误差 %.3f m/s | 稳态超额 %.3f%% | '...
            '全程能耗超额 %.2f%%'],m.MOE_energy,m.finalErr,m.regretPercent,...
            sum(L.powerTrue-L.minPowerTrue)/sum(L.minPowerTrue)*100);
        logMsg(sprintf(['MOP/MOE汇总: MOE_energy=%.4f | 末误差=%.3f m/s | '...
            '稳态超额=%.3f%% | 全程能耗超额=%.2f%% | 入带步数=%g | 锁定占空=%.2f'],...
            m.MOE_energy,m.finalErr,m.regretPercent,m.energyExcessPercent,...
            m.tSearchEvals,m.holdFraction));
    end

    function setupPanels()
        hold(ax(1),'on'); hold(ax(2),'on'); hold(ax(3),'on'); hold(ax(4),'on');
        % 左上：曲线与查询点
        h.curve=line(ax(1),nan,nan,'Color',[.25 .25 .25],'LineWidth',1.4,'DisplayName','对象曲线(当前时刻)');
        h.vstar=line(ax(1),nan,nan,'Color',[.85 .18 .18],'Marker','p','MarkerFaceColor',...
            [.85 .18 .18],'LineStyle','none','MarkerSize',13,'DisplayName','v*(t) 真值最优');
        h.ptScan=line(ax(1),nan,nan,'Color',[.16 .48 .72],'Marker','.','LineStyle','none',...
            'MarkerSize',10,'DisplayName','scan扫描');
        h.ptLocal=line(ax(1),nan,nan,'Color',[.95 .6 .1],'Marker','.','LineStyle','none',...
            'MarkerSize',12,'DisplayName','local局部');
        h.ptFar=line(ax(1),nan,nan,'Color',[.4 .2 .7],'Marker','.','LineStyle','none',...
            'MarkerSize',12,'DisplayName','far远点证据');
        h.ptRefine=line(ax(1),nan,nan,'Color',[.85 .3 .1],'Marker','.','LineStyle','none',...
            'MarkerSize',12,'DisplayName','refine精调');
        h.ptPolish=line(ax(1),nan,nan,'Color',[.8 .1 .35],'Marker','.','LineStyle','none',...
            'MarkerSize',12,'DisplayName','polish顶点');
        h.ptHold=line(ax(1),nan,nan,'Color',[.55 .55 .55],'Marker','.','LineStyle','none',...
            'MarkerSize',7,'DisplayName','hold锁定');
        h.ptProbe=line(ax(1),nan,nan,'Color',[.0 .65 .3],'Marker','.','LineStyle','none',...
            'MarkerSize',12,'DisplayName','probe复探');
        h.ptEsc=line(ax(1),nan,nan,'Color',[.55 .3 .75],'Marker','.','LineStyle','none',...
            'MarkerSize',7,'DisplayName','esc步进');
        h.est=line(ax(1),nan,nan,'Color',[.0 .55 .25],'Marker','o','LineStyle','none',...
            'MarkerSize',5,'DisplayName','当前估计');
        xlabel(ax(1),'速度 / m/s'); ylabel(ax(1),'归一化功率 J');
        title(ax(1),'功率曲线与查询点(逐帧)');
        legend(ax(1),'Location','north','FontSize',7);
        % 右上：速度演化
        h.speed=line(ax(2),nan,nan,'Color',[.2 .4 .8],'LineWidth',.6,'DisplayName','查询速度');
        h.estimate=line(ax(2),nan,nan,'Color',[.0 .55 .25],'LineWidth',1.5,'DisplayName','估计 v_{hat}');
        h.optimum=line(ax(2),nan,nan,'Color',[.85 .18 .18],'LineStyle','--','LineWidth',1.3,'DisplayName','v*(t) 真值');
        xlabel(ax(2),'评估步'); ylabel(ax(2),'速度 / m/s');
        title(ax(2),'速度演化：估计 vs 真值'); legend(ax(2),'Location','northwest','FontSize',8);
        % 左下：功率轨迹
        h.pTrue=line(ax(3),nan,nan,'Color',[.2 .3 .4],'LineWidth',.9,'DisplayName','真实功率');
        h.pMin=line(ax(3),nan,nan,'Color',[.85 .18 .18],'LineStyle','--','LineWidth',1.1,'DisplayName','Pmin(t) 理论最低');
        h.pMeas=line(ax(3),nan,nan,'Color',[.55 .3 .7],'Marker','.','LineStyle','none',...
            'MarkerSize',6,'DisplayName','带噪测量');
        xlabel(ax(3),'评估步'); ylabel(ax(3),'归一化功率 J');
        title(ax(3),'功率轨迹'); legend(ax(3),'Location','north','FontSize',8);
        % 右下：评价口径
        h.metric=line(ax(4),nan,nan,'Color',[.8 .45 .1],'LineWidth',1.3);
        xlabel(ax(4),'评估步'); title(ax(4),'累计能量超额(开关=开)');
    end

    function redraw()
        if isempty(L), return; end
        n=height(L); k=cursor;
        vis=truth.Value;
        tags=string(L.tag(1:k)); sp=L.speed(1:k); pm=L.powerMeas(1:k);
        tNow=L.time(k);
        % 左上：当前时刻曲线(含平移)
        [dx,dy]=usearch.shift_truth(scn,tNow);
        vv=linspace(c.lower,c.upper,400);
        if vis
            h.curve.XData=vv; h.curve.YData=usearch.base_curve(vv-dx,c)+dy;
            vNow=dx+c.optimum0;
            h.vstar.XData=vNow; h.vstar.YData=usearch.base_curve(c.optimum0,c)+dy;
        else
            h.curve.XData=nan; h.curve.YData=nan;
            h.vstar.XData=nan; h.vstar.YData=nan;
        end
        setSlice(h.ptScan,sp,pm,tags,'scan'); setSlice(h.ptLocal,sp,pm,tags,'local');
        setSlice(h.ptFar,sp,pm,tags,'far'); setSlice(h.ptRefine,sp,pm,tags,'refine');
        setSlice(h.ptPolish,sp,pm,tags,'polish'); setSlice(h.ptHold,sp,pm,tags,'hold');
        setSlice(h.ptProbe,sp,pm,tags,'probe'); setSlice(h.ptEsc,sp,pm,tags,'esc');
        h.est.XData=L.estimate(max(1,k-20):k); h.est.YData=pm(max(1,k-20):k);
        % 右上
        h.speed.XData=(1:k)'; h.speed.YData=sp;
        h.estimate.XData=(1:k)'; h.estimate.YData=L.estimate(1:k);
        if vis, h.optimum.XData=(1:k)'; h.optimum.YData=L.optimumTrue(1:k);
        else, h.optimum.XData=nan; h.optimum.YData=nan; end
        xlim(ax(2),[1 n]); ylim(ax(2),[c.lower-0.5 c.upper+0.5]);
        % 左下
        h.pTrue.XData=(1:k)'; h.pTrue.YData=L.powerTrue(1:k);
        h.pMeas.XData=(1:k)'; h.pMeas.YData=pm;
        if vis, h.pMin.XData=(1:k)'; h.pMin.YData=L.minPowerTrue(1:k);
        else, h.pMin.XData=nan; h.pMin.YData=nan; end
        xlim(ax(3),[1 n]);
        % 右下：能耗开关切换评价显示
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
        readout.Text=sprintf('步 %d/%d | 相位 %s | 估计 %.2f | v*(t) %.2f | 平移 dx%.2f dy%.2f',...
            k,n,ph,L.estimate(k),L.optimumTrue(k),dx,dy);
        drawnow limitrate;
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
        file=fullfile(folder,['unified_playback_' datestr(now,'yyyymmdd_HHMMSS') '.gif']);
        n=height(L); stride=max(1,round(n/48)); status.Text='GIF导出中…'; drawnow;
        savedPosition=fig.Position; fig.Position=[60 40 900 620]; drawnow;
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
        % 日志栏: 最新条目置顶, 最多保留400行
        stamp=datestr(now,'HH:MM:SS');
        logBox.Value=[{sprintf('[%s] %s',stamp,msg)}; logBox.Value(1:min(end,398))];
    end

    function clearLog(varargin)
        logBox.Value={'日志已清空'};
    end

    function loadReport(varargin)
        % 将验收报告(results/report.md)载入日志栏
        rp=fullfile(root,'results','report.md');
        if ~exist(rp,'file')
            logMsg('未找到验收报告: 请先在命令行运行 run_unified_acceptance');
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
