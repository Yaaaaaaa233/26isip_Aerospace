function fig = launch_task2_demo(visible)
%LAUNCH_TASK2_DEMO 任务2动画面板：崎岖多峰曲线上的滤波全局寻优(逐帧回放)。
% 交互约定与 launch_speed_esc / launch_task1_demo 一致：面板只回放已完成的
% 因果仿真；更改参数后按"重置"或"播放"重跑。
%
% 四联图(逐帧生长)：
%   左上 功率曲线与查询点：崎岖真值曲线(评价器)、按相位着色的查询点
%        (scan蓝/refine橙/polish红/esc紫)、全局最优红星、已搜索滤波轮廓
%   右上 速度演化：估计(绿) vs 全局最优v*(红虚)；初始速度可调
%   左下 功率轨迹：真实功率/测量值/离线最优
%   右下 评价口径：能耗开关=开 -> 累计能量超额%；关 -> 估计误差(对数轴)
if nargin<1, visible='on'; end
root=fileparts(mfilename('fullpath')); addpath(root);
fig=uifigure('Name','任务2：崎岖多峰曲线的滤波全局寻优(动态演示)',...
    'Position',[80 60 1420 940],'Color',[.96 .97 .98],'Visible',visible,...
    'AutoResizeChildren','off');
outer=uigridlayout(fig,[3 2]); outer.RowHeight={44,'1x',28}; outer.ColumnWidth={315,'1x'};
outer.Padding=[12 10 12 10]; outer.RowSpacing=10;
header=uilabel(outer,'Text','任务2 崎岖多峰曲线全局寻优 | 调试二次曲线+正弦崎岖项·无平移·代理模型',...
    'FontName','Microsoft YaHei','FontSize',17,'FontWeight','bold'); put(header,1,[1 2]);
left=uigridlayout(outer,[3 1]); put(left,2,1); left.RowHeight={'1x',116,48};
left.Padding=[0 0 0 0]; left.RowSpacing=8;
form=uipanel(left,'BorderType','none'); put(form,1,1);
g=uigridlayout(form,[13 2]); g.ColumnWidth={140,'1x'};
g.RowHeight=[repmat({30},1,9),{26,30,26,30}];
g.Padding=[0 0 8 0]; g.RowSpacing=7;
algorithm=choice(g,'搜索算法',1,{'multistart(推荐)','filter_argmin 只滤波',...
    'single_golden 单起点','grid 网格','esc 连续ESC'},...
    {'multistart','filter_argmin','single_golden','grid','esc'},'multistart');
initial=number(g,'初始速度 / m/s',2,10,[0 20]);
noise=number(g,'相对噪声标准差',3,0.01,[0 0.05]);
ripA1=number(g,'崎岖幅值A1',4,0.022,[0 0.06]);
ripL1=number(g,'崎岖波长λ1 / m',5,6.0,[2 12]);
ripA2=number(g,'崎岖幅值A2',6,0.012,[0 0.06]);
ripL2=number(g,'崎岖波长λ2 / m',7,2.0,[1 6]);
Knum=number(g,'候选谷数 K',8,5,[1 10]);
seed=number(g,'随机种子',9,11,[1 100]);
truth=uicheckbox(g,'Text','显示评价器曲线与真值','Value',true); put(truth,10,[1 2]);
energy=uicheckbox(g,'Text','搜索能耗计入评价(续航口径)','Value',true); put(energy,11,[1 2]);
speedLabel=uilabel(g,'Text','播放速度: 1.00x','FontName','Microsoft YaHei','FontSize',11); put(speedLabel,12,1);
speedSlider=uislider(g,'Limits',[0.5 8],'Value',1,'MajorTicks',[.5 1 2 4 8],...
    'MajorTickLabels',{'0.5x','1x','2x','4x','8x'}); put(speedSlider,12,2);
speedSlider.ValueChangedFcn=@(~,ev) setSpeed(ev.Value);
    function setSpeed(val)
        speedLabel.Text=sprintf('播放速度: %.2fx',val);
        if strcmp(clock.Running,'on'), clock.Period=.15/val; end
    end
actions=uigridlayout(left,[2 4]); put(actions,2,1); actions.Padding=[0 0 8 0];
actions.RowHeight={34,34}; actions.RowSpacing=7;
play=uibutton(actions,'Text','播放'); put(play,1,1); pauseBtn=uibutton(actions,'Text','暂停'); put(pauseBtn,1,2);
reset=uibutton(actions,'Text','重置'); put(reset,1,3); finish=uibutton(actions,'Text','末帧'); put(finish,1,4);
exportPng=uibutton(actions,'Text','导出PNG'); put(exportPng,2,1);
exportGif=uibutton(actions,'Text','导出GIF动画'); put(exportGif,2,[2 4]);
readout=uilabel(left,'Text','','WordWrap','on','FontName','Microsoft YaHei'); put(readout,3,1);
plots=uigridlayout(outer,[2 2]); put(plots,2,2); plots.Padding=[0 0 0 0]; plots.RowSpacing=14;
ax=gobjects(1,4); for k=1:4, ax(k)=uiaxes(plots); disableDefaultInteractivity(ax(k)); ax(k).Toolbar.Visible='off'; end
status=uilabel(outer,'Text','就绪','FontName','Microsoft YaHei'); put(status,3,2);
clock=timer('ExecutionMode','fixedSpacing','Period',.15,'BusyMode','drop','TimerFcn',@tick);
L=table(); info=[]; c=[]; cursor=1; dirty=true; h=struct();
cumEnergy=[]; estError=[]; vG=NaN; curveVV=[]; curveYY=[];
controls=struct('algorithm',algorithm,'initial',initial,'noise',noise,...
    'ripA1',ripA1,'ripL1',ripL1,'ripA2',ripA2,'ripL2',ripL2,'K',Knum,'seed',seed,...
    'truth',truth,'energy',energy,'play',play,'pause',pauseBtn,'reset',reset,...
    'finish',finish,'exportPng',exportPng,'exportGif',exportGif,'speed',speedSlider);
fig.UserData=struct('controls',controls,'prepare',@prepare,'play',@playback,...
    'pause',@stopPlayback,'finish',@toEnd,'getLog',@getLog,'getCursor',@getCursor,...
    'timer',clock,'exportPng',@exportCurrent,'exportGif',@exportGifCurrent);
for cn={algorithm,initial,noise,ripA1,ripL1,ripA2,ripL2,Knum,seed}
    cn{1}.ValueChangedFcn=@changed;
end
truth.ValueChangedFcn=@(~,~)redraw(); energy.ValueChangedFcn=@(~,~)redraw();
play.ButtonPushedFcn=@playback; pauseBtn.ButtonPushedFcn=@stopPlayback;
reset.ButtonPushedFcn=@prepare; finish.ButtonPushedFcn=@toEnd;
exportPng.ButtonPushedFcn=@exportCurrent; exportGif.ButtonPushedFcn=@exportGifCurrent;
fig.CloseRequestFcn=@closeApp; fig.SizeChangedFcn=@resizeLayout;
setupPanels(); resizeLayout(); prepare();

    function resizeLayout(varargin)
        bodyHeight=max(300,fig.InnerPosition(4)-112);
        outer.RowHeight={44,bodyHeight,28};
        left.RowHeight={max(120,bodyHeight-180),116,48};
    end

    function changed(varargin)
        stopPlayback(); dirty=true; status.Text='参数已更改，按"重置"或"播放"生效';
    end

    function c=buildConfig()
        c=task2.config('initialSpeed',initial.Value,'noiseSigma',noise.Value,...
            'rippleA1',ripA1.Value,'rippleL1',ripL1.Value,...
            'rippleA2',ripA2.Value,'rippleL2',ripL2.Value,...
            'K',Knum.Value,'seed',seed.Value);
    end

    function prepare(varargin)
        stopPlayback();
        try
            c=buildConfig();
            [L,info]=task2.run_algorithm(algorithm.Value,c);
            [~,vG]=task2.power_map([],c);
            n=height(L);
            cumEnergy=100*cumsum(L.powerTrue-L.minPowerTrue)./cumsum(L.minPowerTrue);
            estError=abs(L.estimate-vG);
            % 崎岖项>=0.001时整条曲线绘制并求滤波轮廓(逐帧显示已扫描部分)
            vv=linspace(c.lower,c.upper,601);
            curveVV=vv; curveYY=task2.power_map(vv,c);
            cursor=1; dirty=false; redraw(); status.Text='就绪';
        catch err
            status.Text=['配置错误：' err.message];
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
        m=task2.evaluate(L,info,c);
        if isnan(m.energyExcessPercent), eTxt='—'; else, eTxt=sprintf('%.2f%%',m.energyExcessPercent); end
        status.Text=sprintf(['误差 %.3f m/s | 稳态超额 %.3f%% | 全程能耗 %s | '...
            '扫描%d+精调%d步'],m.finalErr,m.steadyRegretPercent,eTxt,...
            m.scanSteps,m.refineSteps);
    end

    function setupPanels()
        hold(ax(1),'on'); hold(ax(2),'on'); hold(ax(3),'on'); hold(ax(4),'on');
        phaseMap=containers.Map({'scan','refine','polish','hold','esc'},...
            {'扫描','谷精调','终精调','锁定','ESC'});
        % 左上：曲线与查询点
        h.curve=line(ax(1),nan,nan,'Color',[.25 .25 .25],'LineWidth',1.4,'DisplayName','对象曲线(评价器)');
        h.scanFilt=line(ax(1),nan,nan,'Color',[.2 .55 .75],'LineWidth',1.8,'DisplayName','扫描+滤波轮廓');
        h.vg=line(ax(1),nan,nan,'Color',[.85 .18 .18],'Marker','p','MarkerFaceColor',...
            [.85 .18 .18],'LineStyle','none','MarkerSize',13,'DisplayName','全局最优 v*');
        h.ptScan=line(ax(1),nan,nan,'Color',[.16 .48 .72],'Marker','.','LineStyle','none',...
            'MarkerSize',10,'DisplayName','scan 扫描');
        h.ptRefine=line(ax(1),nan,nan,'Color',[.9 .55 .1],'Marker','.','LineStyle','none',...
            'MarkerSize',12,'DisplayName','refine 谷精调');
        h.ptPolish=line(ax(1),nan,nan,'Color',[.8 .18 .18],'Marker','.','LineStyle','none',...
            'MarkerSize',12,'DisplayName','polish 终精调');
        h.ptHold=line(ax(1),nan,nan,'Color',[.55 .55 .55],'Marker','.','LineStyle','none',...
            'MarkerSize',7,'DisplayName','hold 锁定');
        h.ptEsc=line(ax(1),nan,nan,'Color',[.65 .3 .75],'Marker','.','LineStyle','none',...
            'MarkerSize',7,'DisplayName','esc 步进');
        h.est=line(ax(1),nan,nan,'Color',[.0 .55 .25],'Marker','o','LineStyle','none',...
            'MarkerSize',5,'DisplayName','当前估计');
        xlabel(ax(1),'速度 / m/s'); ylabel(ax(1),'归一化功率 J');
        title(ax(1),'崎岖功率曲线与查询点(逐帧)');
        legend(ax(1),'Location','north','FontSize',7);
        % 右上：速度演化
        h.speed=line(ax(2),nan,nan,'Color',[.2 .4 .8],'LineWidth',.6,'DisplayName','查询速度');
        h.estimate2=line(ax(2),nan,nan,'Color',[.0 .55 .25],'LineWidth',1.5,'DisplayName','估计 v_{hat}');
        h.vg2=line(ax(2),nan,nan,'Color',[.85 .18 .18],'LineStyle','--','LineWidth',1.3,'DisplayName','全局最优 v*');
        xlabel(ax(2),'评估步'); ylabel(ax(2),'速度 / m/s');
        title(ax(2),'速度演化：估计 vs 全局最优'); legend(ax(2),'Location','northwest','FontSize',8);
        % 左下：功率轨迹
        h.pTrue=line(ax(3),nan,nan,'Color',[.2 .3 .4],'LineWidth',.9,'DisplayName','真实功率');
        h.pMin=line(ax(3),nan,nan,'Color',[.85 .18 .18],'LineStyle','--','LineWidth',1.1,'DisplayName','全局最优功率');
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
        tags=L.tag(1:k); sp=L.speed(1:k); pm=L.powerMeas(1:k);
        % 左上
        if vis && ~isempty(curveVV)
            h.curve.XData=curveVV; h.curve.YData=curveYY;
            h.vg.XData=vG; h.vg.YData=min(curveYY);
        else
            h.curve.XData=nan; h.curve.YData=nan; h.vg.XData=nan; h.vg.YData=nan;
        end
        % 已扫描段的滤波轮廓(需>=5个scan点)
        hits=find(strcmp(tags,'scan'),1,'last');
        if ~isempty(hits) && hits>=5
            scanV=sp(strcmp(tags,'scan')); scanP=pm(strcmp(tags,'scan'));
            if ~isempty(scanV) && scanV(end)>scanV(1)
                vq=linspace(scanV(1),scanV(end),numel(scanV));
                pf=task2.apply_filter(scanP,c.filterMethod,c.filterW);
                h.scanFilt.XData=scanV; h.scanFilt.YData=pf;
            end
        else
            h.scanFilt.XData=nan; h.scanFilt.YData=nan;
        end
        setSlice(h.ptScan,sp,pm,tags,'scan');
        setSlice(h.ptRefine,sp,pm,tags,'refine');
        setSlice(h.ptPolish,sp,pm,tags,'polish');
        setSlice(h.ptHold,sp,pm,tags,'hold');
        setSlice(h.ptEsc,sp,pm,tags,'esc');
        h.est.XData=L.estimate(max(1,k-20):k); h.est.YData=pm(max(1,k-20):k);
        % 右上
        h.speed.XData=(1:k)'; h.speed.YData=sp;
        h.estimate2.XData=(1:k)'; h.estimate2.YData=L.estimate(1:k);
        if vis, h.vg2.XData=(1:k)'; h.vg2.YData=vG*ones(1,k);
        else, h.vg2.XData=nan; h.vg2.YData=nan; end
        xlim(ax(2),[1 n]); ylim(ax(2),[c.lower-0.5 c.upper+0.5]);
        % 左下
        h.pTrue.XData=(1:k)'; h.pTrue.YData=L.powerTrue(1:k);
        h.pMeas.XData=(1:k)'; h.pMeas.YData=pm;
        if vis, h.pMin.XData=(1:k)'; h.pMin.YData=L.minPowerTrue(1:k);
        else, h.pMin.XData=nan; h.pMin.YData=nan; end
        xlim(ax(3),[1 n]);
        % 右下
        xlim(ax(4),[1 n]);
        if energy.Value
            ax(4).YScale='linear'; ax(4).YLabel.String='累计能量超额 / %';
            title(ax(4),'累计能量超额(开关=开, 续航口径)');
            h.metric.YData=cumEnergy(1:k);
        else
            ax(4).YScale='log'; ax(4).YLabel.String='|v_{hat}-v*| / m/s';
            title(ax(4),'估计误差(开关=关, 只看定位)');
            h.metric.YData=max(estError(1:k),1e-4);
        end
        h.metric.XData=(1:k)';
        phaseMap={'scan','扫描';'refine','谷精调';'polish','终精调';'hold','锁定';'esc','ESC'};
        ph='—';
        for q=1:size(phaseMap,1)
            if strcmp(char(tags(k)),phaseMap{q,1}), ph=phaseMap{q,2}; end
        end
        readout.Text=sprintf('步 %d/%d | 相位 %s | 估计 %.2f m/s | 全局最优 %.2f m/s',...
            k,n,ph,L.estimate(k),vG);
        drawnow limitrate;
    end

    function setSlice(hdl,sp,pm,tags,name)
        hit=strcmp(tags,name);
        hdl.XData=sp(hit); hdl.YData=pm(hit);
    end

    function exportCurrent(varargin)
        stopPlayback();
        folder=fullfile(root,'..','results','task2'); if ~exist(folder,'dir'), mkdir(folder); end
        file=fullfile(folder,['ui2_' datestr(now,'yyyymmdd_HHMMSS') '.png']);
        exportapp(fig,file); status.Text=['面板截图已导出：' file];
    end

    function exportGifCurrent(varargin)
        stopPlayback(); if dirty, prepare(); end
        if isempty(L), return; end
        folder=fullfile(root,'..','results','task2'); if ~exist(folder,'dir'), mkdir(folder); end
        file=fullfile(folder,['task2_playback_' datestr(now,'yyyymmdd_HHMMSS') '.gif']);
        n=height(L); stride=max(1,round(n/48)); status.Text='GIF导出中…'; drawnow;
        savedPosition=fig.Position; fig.Position=[80 60 900 620]; drawnow;
        first=true; cleanupGif=onCleanup(@()set(fig,'Position',savedPosition)); %#ok<NASGU>
        for k=1:stride:n
            cursor=min(k,n); redraw(); drawnow;
            tmp=fullfile(tempdir,sprintf('task2frame_%d.png',randi(1e9)));
            exportapp(fig,tmp);
            [A,map]=rgb2ind(imread(tmp),128);
            if first, imwrite(A,map,file,'gif','LoopCount',Inf,'DelayTime',.15); first=false;
            else, imwrite(A,map,file,'gif','WriteMode','append','DelayTime',.15); end
            delete(tmp);
        end
        cursor=n; redraw();
        status.Text=['GIF动画已导出：' file];
    end

    function value=getLog(), value=L; end
    function value=getCursor(), value=cursor; end

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
