function fig = launch_task1_demo(visible)
%LAUNCH_TASK1_DEMO 任务1动画面板：平移曲线黑箱搜索的逐帧回放。
% 与 launch_speed_esc 同一交互约定：面板只回放"已完成"的因果仿真日志，
% 播放/暂停/拖动不改变控制器计算；更改参数后按"重置"重跑。
%
% 四联图(逐帧生长)：
%   左上 功率曲线与查询点
%   右上 速度演化
%   左下 功率轨迹
%   右下 评价口径(能耗开关)
%
% 新功能：
%   - 黑箱假设：不预设最优点，只给定初始速度
%   - 多次跳变：在 UI 中可添加/删除多个跳变事件
%   - 日志记录区：记录每次跳变、初始搜索、重搜及恢复步数
if nargin<1, visible='on'; end
root=fileparts(mfilename('fullpath')); addpath(root);
fig=uifigure('Name','任务1：平移曲线黑箱搜索(动态演示)','Position',[60 40 1500 980],...
    'Color',[.96 .97 .98],'Visible',visible,'AutoResizeChildren','off');
outer=uigridlayout(fig,[2 2]); outer.RowHeight={46,'1x'}; outer.ColumnWidth={420,'1x'};
outer.Padding=[10 8 10 8]; outer.RowSpacing=8;
header=uilabel(outer,'Text','任务1 平移曲线黑箱速度搜索 | 黑箱最优点·多次跳变·代理曲线·非实测',...
    'FontName','Microsoft YaHei','FontSize',16,'FontWeight','bold'); put(header,1,[1 2]);

% ========== 左侧参数面板 ==========
left=uipanel(outer,'BorderType','none'); put(left,2,1);
lg=uigridlayout(left,[3 1]); lg.RowHeight={'1x','1.2x',36}; lg.Padding=[4 4 4 4];
lg.RowSpacing=6;

% 上部：参数与跳变设置
topBox=uipanel(lg,'BorderType','none'); put(topBox,1,1);
tg=uigridlayout(topBox,[14 2]); tg.ColumnWidth={140,'1x'};
tg.RowHeight=cellfun(@(x){x},num2cell(repmat(30,1,14)));
tg.Padding=[2 2 2 2]; tg.RowSpacing=5; tg.Scrollable='on';

algorithm=choice(tg,'搜索算法',1,{'tracker(推荐)','esc连续跟踪'},{'tracker','esc'},'tracker');
curve=choice(tg,'对象曲线',2,{'三次代理曲线(cubic)','调试二次曲线(debug)'},{'cubic','debug'},'cubic');
duration=number(tg,'总评估步数',3,400,[200 2000]);
initial=number(tg,'初始速度 / m/s',4,10,[0 20]);
energy=uicheckbox(tg,'Text','搜索能耗计入评价(续航口径)','Value',true); put(energy,5,[1 2]);
truth=uicheckbox(tg,'Text','显示评价器曲线与真值','Value',true); put(truth,6,[1 2]);
scnChoice=choice(tg,'平移场景',7,{'static 无平移','jumpUp 上跳2.7','jumpDown 下跳2.3',...
    'offset 纯上移5%','ramp 慢漂1.7','midsearch 搜索中跳变','manual 多次手动跳变'},...
    {'static','jumpUp','jumpDown','offset','ramp','midsearch','manual'},'manual');

% 跳变表标题
shiftTitle=uilabel(tg,'Text','手动跳变列表(manual时生效)',...
    'FontName','Microsoft YaHei','FontWeight','bold','FontSize',11); put(shiftTitle,8,1);

% 跳变内容区(第9-10行)：表头+动态跳变行
shiftContent=uipanel(tg,'BorderType','none'); put(shiftContent,9,[1 2]);
scLayout=uigridlayout(shiftContent,[2 5]); scLayout.ColumnWidth={50,70,70,80,30};
scLayout.RowHeight={24,'1x'}; scLayout.Padding=[2 2 2 2]; scLayout.RowSpacing=2;
% 表头
h1=uilabel(scLayout,'Text','启用','FontWeight','bold','FontSize',10); put(h1,1,1);
h2=uilabel(scLayout,'Text','Δv (m/s)','FontWeight','bold','FontSize',10); put(h2,1,2);
h3=uilabel(scLayout,'Text','η (%)','FontWeight','bold','FontSize',10); put(h3,1,3);
h4=uilabel(scLayout,'Text','时间 (s)','FontWeight','bold','FontSize',10); put(h4,1,4);
h5=uilabel(scLayout,'Text','#','FontWeight','bold','FontSize',10); put(h5,1,5);
% 跳变行容器
shiftRowsPanel=uipanel(scLayout,'BorderType','none'); put(shiftRowsPanel,2,[1 5]);
shiftRowsLayout=uigridlayout(shiftRowsPanel,[1 5]); shiftRowsLayout.ColumnWidth={50,70,70,80,30};
shiftRowsLayout.Padding=[0 0 0 0]; shiftRowsLayout.RowSpacing=0;

% 跳变管理按钮(第10行)
scl=uigridlayout(tg,[1 3]); scl.ColumnWidth={80,80,'1x'};
scl.RowHeight={26}; scl.Padding=[0 0 0 0]; scl.ColumnSpacing=4;
put(scl,10,[1 2]);
addBtn=uibutton(scl,'Text','+ 添加跳变'); put(addBtn,1,1);
delBtn=uibutton(scl,'Text','- 删除最后'); put(delBtn,1,2);
clearBtn=uibutton(scl,'Text','清空全部'); put(clearBtn,1,3);

% 播放速度(第11行)
speedLabel=uilabel(tg,'Text','播放速度: 1.00x','FontName','Microsoft YaHei','FontSize',11); put(speedLabel,11,1);
speedSlider=uislider(tg,'Limits',[0.1 8],'Value',1,'MajorTicks',[.5 1 2 4 8],...
    'MajorTickLabels',{'0.5x','1x','2x','4x','8x'}); put(speedSlider,11,2);
speedSlider.ValueChangedFcn=@(~,ev) setSpeed(ev.Value);

% 操作按钮(第12行)
actionsBox=uipanel(tg,'BorderType','none'); put(actionsBox,12,[1 2]);
agl=uigridlayout(actionsBox,[1 5]); agl.ColumnWidth={60,60,60,60,'1x'};
agl.RowHeight={30}; agl.Padding=[0 0 0 0]; agl.ColumnSpacing=4;
play=uibutton(agl,'Text','播放'); put(play,1,1); pauseBtn=uibutton(agl,'Text','暂停'); put(pauseBtn,1,2);
reset=uibutton(agl,'Text','重置'); put(reset,1,3); finish=uibutton(agl,'Text','末帧'); put(finish,1,4);
exportPng=uibutton(agl,'Text','导出PNG'); put(exportPng,1,5);

% 导出GIF按钮(第13行)
exportGifBtn=uipanel(tg,'BorderType','none'); put(exportGifBtn,13,[1 2]);
egl=uigridlayout(exportGifBtn,[1 1]); egl.RowHeight={28}; egl.Padding=[0 0 0 0];
exportGif=uibutton(egl,'Text','导出GIF动画'); put(exportGif,1,1);

% 状态 readout(第14行)
readout=uilabel(tg,'Text','','WordWrap','on','FontName','Microsoft YaHei','FontSize',10);
readout.Layout.Row=14; readout.Layout.Column=[1 2];

% 下部：日志记录区
midBox=uipanel(lg,'BorderType','none'); put(midBox,2,1);
logLayout=uigridlayout(midBox,[2 1]); logLayout.RowHeight={22,'1x'};
logLayout.Padding=[2 2 2 2]; logLayout.RowSpacing=4;
logTitle=uilabel(logLayout,'Text','日志记录区 (黑箱搜索关键事件)',...
    'FontName','Microsoft YaHei','FontWeight','bold','FontSize',11); put(logTitle,1,1);
logArea=uitextarea(logLayout,'Editable','off','FontName','Consolas','FontSize',10);
logArea.Layout.Row=2; logArea.Layout.Column=1;

% 状态栏
bottomBox=uipanel(lg,'BorderType','none'); put(bottomBox,3,1);
bg=uigridlayout(bottomBox,[2 2]); bg.ColumnWidth={80,'1x'}; bg.RowHeight={26,26};
bg.Padding=[2 2 2 2]; bg.RowSpacing=4;
statusLabel=uilabel(bg,'Text','当前状态:','FontName','Microsoft YaHei','FontWeight','bold'); put(statusLabel,1,1);
status=uilabel(bg,'Text','就绪','FontName','Microsoft YaHei'); put(status,1,2);
exportGif2=uilabel(bg,'Text',''); put(exportGif2,2,1);

% ========== 右侧图表区 ==========
right=uigridlayout(outer,[2 2]); put(right,2,2); right.Padding=[0 0 0 0]; right.RowSpacing=10; right.ColumnSpacing=10;
ax=gobjects(1,4); for k=1:4, ax(k)=uiaxes(right); disableDefaultInteractivity(ax(k)); ax(k).Toolbar.Visible='off'; end

% 定时器
clock=timer('ExecutionMode','fixedSpacing','Period',.15,'BusyMode','drop','TimerFcn',@tick);
L=table(); info=[]; scn=[]; c=[]; cursor=1; dirty=true; h=struct(); phaseMap=[];
cumEnergy=[]; estError=[]; bIdx=[];

% 跳变条目管理：每个条目为 struct{en,dEdit,tEdit}
shifts=struct('en',{},'dx',{},'dy',{},'t',{});

fig.UserData=struct('shifts',shifts);

for control={algorithm,curve,duration,initial,scnChoice}
    control{1}.ValueChangedFcn=@changed;
end
truth.ValueChangedFcn=@(~,~)redraw(); energy.ValueChangedFcn=@(~,~)redraw();
play.ButtonPushedFcn=@playback; pauseBtn.ButtonPushedFcn=@stopPlayback;
reset.ButtonPushedFcn=@prepare; finish.ButtonPushedFcn=@toEnd;
exportPng.ButtonPushedFcn=@exportCurrent; exportGif.ButtonPushedFcn=@exportGifCurrent;
addBtn.ButtonPushedFcn=@addShift; delBtn.ButtonPushedFcn=@delShift;
clearBtn.ButtonPushedFcn=@clearShifts;
fig.CloseRequestFcn=@closeApp;
setupPanels(); prepare();

    function addShift(varargin)
        newIdx=numel(shifts)+1;
        shifts(newIdx).en=true; shifts(newIdx).dx=2; shifts(newIdx).dy=0;
        shifts(newIdx).t=120+60*(newIdx-1);  % 默认错开60秒
        rebuildShiftPanel(); dirty=true; status.Text='已添加新跳变，按"重置"生效';
    end

    function delShift(varargin)
        if isempty(shifts), return; end
        shifts(end)=[]; rebuildShiftPanel(); dirty=true; status.Text='已删除最后跳变';
    end

    function clearShifts(varargin)
        shifts=struct('en',{},'dx',{},'dy',{},'t',{});
        rebuildShiftPanel(); dirty=true; status.Text='已清空跳变';
    end

    function rebuildShiftPanel()
        % 重建跳变行：删除并重建 shiftRowsLayout
        delete(shiftRowsLayout);
        n=numel(shifts);
        shiftRowsLayout=uigridlayout(shiftRowsPanel,[max(n,1) 5]);
        shiftRowsLayout.ColumnWidth={50,70,70,80,30};
        shiftRowsLayout.RowHeight=repmat({26},1,max(n,1));
        shiftRowsLayout.Padding=[0 0 0 0]; shiftRowsLayout.RowSpacing=0;
        if n>0
            for k=1:n
                cb=uicheckbox(shiftRowsLayout,'Text','','Value',shifts(k).en);
                cb.Layout.Row=k; cb.Layout.Column=1;
                cb.ValueChangedFcn=@(~,ev) updateShift(k,1,logical(ev.Value));
                de=uieditfield(shiftRowsLayout,'numeric','Value',shifts(k).dx,...
                    'Limits',[-10 10],'ValueDisplayFormat','%.2f','BackgroundColor',[1 1 1]);
                de.Layout.Row=k; de.Layout.Column=2;
                de.ValueChangedFcn=@(~,ev) updateShift(k,2,ev.Value);
                ye=uieditfield(shiftRowsLayout,'numeric','Value',100*shifts(k).dy,...
                    'Limits',[-50 50],'ValueDisplayFormat','%.1f','BackgroundColor',[1 1 1]);
                ye.Layout.Row=k; ye.Layout.Column=3;
                ye.ValueChangedFcn=@(~,ev) updateShift(k,3,ev.Value/100);
                te=uieditfield(shiftRowsLayout,'numeric','Value',shifts(k).t,...
                    'Limits',[0 400],'ValueDisplayFormat','%.0f','BackgroundColor',[1 1 1]);
                te.Layout.Row=k; te.Layout.Column=4;
                te.ValueChangedFcn=@(~,ev) updateShift(k,4,ev.Value);
                lbl=uilabel(shiftRowsLayout,'Text',sprintf('%d',k),'FontSize',9,'HorizontalAlignment','center');
                lbl.Layout.Row=k; lbl.Layout.Column=5;
            end
        else
            emptyMsg=uilabel(shiftRowsLayout,'Text','(无跳变，点"+ 添加跳变"创建)','FontColor',[.5 .5 .5],'FontSize',10);
            emptyMsg.Layout.Row=1; emptyMsg.Layout.Column=[1 5];
        end
    end

    function updateShift(idx,field,val)
        if idx>numel(shifts), return; end
        switch field
            case 1, shifts(idx).en=val;
            case 2, shifts(idx).dx=val;
            case 3, shifts(idx).dy=val;
            case 4, shifts(idx).t=val;
        end
        dirty=true; status.Text='跳变已修改，按"重置"生效';
    end

    function setSpeed(val)
        speedLabel.Text=sprintf('播放速度: %.2fx',val);
        if strcmp(clock.Running,'on'), clock.Period=.15/val; end
    end

    function changed(varargin)
        stopPlayback(); dirty=true; status.Text='参数已更改，按"重置"或"播放"生效';
    end

    function shiftsMat = collectShifts()
        % 从 UI 收集 shifts 到 N×4 矩阵
        M=zeros(numel(shifts),4);
        for k=1:numel(shifts)
            M(k,1)=shifts(k).t; M(k,2)=shifts(k).dx;
            M(k,3)=shifts(k).dy; M(k,4)=double(shifts(k).en);
        end
        shiftsMat = M;
    end

    function prepare(varargin)
        stopPlayback();
        try
            c=task1.config('duration',duration.Value,'curve',curve.Value,...
                'initialSpeed',initial.Value,...
                'energyAccounting',energy.Value);
            if strcmp(scnChoice.Value,'manual')
                shiftsMat=collectShifts();
                scn=task1.scenario('manual',c,'shifts',shiftsMat);
            else
                scn=task1.scenario(scnChoice.Value,c);
            end
            [L,info]=task1.run_algorithm(algorithm.Value,scn,c);
            n=height(L);
            cumEnergy=100*cumsum(L.powerTrue-L.minPowerTrue)./cumsum(L.minPowerTrue);
            estError=abs(L.estimate-L.optimumTrue);
            bIdx=nan(n,1); j=0;
            for k=1:n
                if strcmp(L.tag(k),'search')
                    j=j+1;
                    if j<=size(info.brackets,1), bIdx(k)=j; end
                end
            end
            cursor=1; dirty=false; redraw(); writeLog(); status.Text='就绪';
        catch err
            status.Text=['配置错误：' err.message];
            logArea.Value={['错误: ' err.message]};
        end
    end

    function writeLog()
        % 生成日志记录
        n=height(L);
        lines={};
        lines{end+1}=sprintf('=========================================================');
        lines{end+1}=sprintf('  运行日志  |  算法:%s | 曲线:%s | 初速:%.2f m/s | 总步:%d',...
            algorithm.Value,curve.Value,initial.Value,n);
        lines{end+1}=sprintf('=========================================================');
        lines{end+1}=sprintf('初始搜索起点: %.2f m/s (用户给定，黑箱假设)',initial.Value);

        % 初始搜索：tracker 算法用 lockV(1)，其他算法用 best 或 searchEvals 后的 estimate
        if isfield(info,'searchEvals') && ~isempty(info.searchEvals)
            sEvals=info.searchEvals;
            lines{end+1}=sprintf('初始搜索完成于第 %d 步 (用时 %.0f s)',sEvals,sEvals*c.tEval);
            if isfield(info,'best') && ~isempty(info.best)
                lines{end+1}=sprintf('初始最优速度: %.3f m/s',info.best);
            else
                lines{end+1}=sprintf('初始最优速度: %.3f m/s',L.estimate(sEvals));
            end
        else
            % tracker/esc 算法：从日志读取初始搜索结束点
            searchIdx=find(strcmp(L.tag,'search'));
            if isempty(searchIdx)
                initEval=1; initV=L.estimate(1);
            else
                % 找第一个连续 search 段的结束位置
                nonsIdx=find(~strcmp(L.tag,'search'),1,'first');
                if isempty(nonsIdx)
                    initEval=searchIdx(end);
                else
                    initEval=max(1,nonsIdx-1);
                end
                % 搜索段的最后一步的 estimate 视为初始最优
                initV=L.estimate(initEval);
            end
            if strcmp(algorithm.Value,'esc')
                lines{end+1}=sprintf('连续跟踪: 起点步 1 (即时跟踪)');
                lines{end+1}=sprintf('初始估计速度: %.3f m/s',initV);
            else
                lines{end+1}=sprintf('初始搜索完成于第 %d 步 (用时 %.0f s)',initEval,initEval*c.tEval);
                lines{end+1}=sprintf('初始最优速度: %.3f m/s',initV);
            end
        end
        lines{end+1}='';
        % 跳变事件
        if ~isempty(scn.jumps)
            lines{end+1}=sprintf('-- 跳变事件 (手动配置) --');
            for j=1:size(scn.jumps,1)
                t=scn.jumps(j,1); dx=scn.jumps(j,2); dy=scn.jumps(j,3);
                desc=sprintf('  [%d] t=%.1fs',j,t);
                if dx~=0, desc=sprintf('%s, dx=%+.2fm/s (左右)',desc,dx); end
                if dy~=0, desc=sprintf('%s, dy=%+.3f (上下)',desc,dy); end
                lines{end+1}=desc;
            end
        else
            lines{end+1}=sprintf('-- 跳变事件: 无 (static 场景) --');
        end
        lines{end+1}='';
        % 重搜事件
        if isfield(info,'researchTimes') && ~isempty(info.researchTimes)
            lines{end+1}=sprintf('-- 重搜(平移监测触发) --');
            for r=1:length(info.researchTimes)
                rt=info.researchTimes(r);
                if r<length(info.researchTimes)
                    rt2=info.researchTimes(r+1);
                else
                    rt2=n;
                end
                % 取这次重搜后第一次进入 hold 时的 estimate 作为新最优速度
                segTag=L.tag(rt:rt2);
                segEst=L.estimate(rt:rt2);
                holdInSeg=find(strcmp(segTag,'hold'),1,'first');
                if isempty(holdInSeg)
                    newV=segEst(end);
                else
                    newV=segEst(holdInSeg);
                end
                % 重搜持续步数（search+probe 步）
                searchInSeg=sum(strcmp(segTag,'search'))+sum(strcmp(segTag,'probe'));
                lines{end+1}=sprintf('  重搜#%d: 触发步 %d (t=%.0fs), 找到新最优 %.3f m/s, 搜索用时 %d 步',...
                    r,rt,rt*c.tEval,newV,searchInSeg);
            end
        else
            if isfield(info,'researchCount') && ~isnan(info.researchCount) && info.researchCount>0
                lines{end+1}=sprintf('-- 重搜: 已触发 %d 次 (元数据保留) --',info.researchCount);
            else
                lines{end+1}=sprintf('-- 重搜: 未触发 --');
            end
        end
        % 末段结果
        m=task1.evaluate(L,scn,c);
        lines{end+1}='';
        lines{end+1}=sprintf('-- 末段结果 --');
        lines{end+1}=sprintf('  最终误差: %.3f m/s',m.finalErr);
        lines{end+1}=sprintf('  稳态超额: %.3f%%',m.steadyRegretPercent);
        if ~isnan(m.energyExcessPercent)
            lines{end+1}=sprintf('  全程能耗超额: %.3f%%',m.energyExcessPercent);
        end
        if ~isnan(m.recoverySteps)
            lines{end+1}=sprintf('  最长恢复步数: %d',m.recoverySteps);
        end
        logArea.Value=lines;
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
        m=task1.evaluate(L,scn,c);
        if isnan(m.energyExcessPercent), eTxt='—'; else, eTxt=sprintf('%.3f%%',m.energyExcessPercent); end
        status.Text=sprintf('末段误差 %.3f m/s | 稳态超额 %.3f%% | 能耗 %s | 重搜 %s 次',...
            m.finalErr,m.steadyRegretPercent,eTxt,num2str(info.researchCount));
    end

    function setupPanels()
        hold(ax(1),'on'); hold(ax(2),'on'); hold(ax(3),'on'); hold(ax(4),'on');
        phaseMap=containers.Map({'search','hold','probe','esc'},{'搜索','锁定','复探','ESC'});
        h.band=patch(ax(1),nan(1,4),nan(1,4),[.93 .78 .78],'EdgeColor','none','DisplayName','夹逼区间');
        h.curve=line(ax(1),nan,nan,'Color',[.25 .25 .25],'LineWidth',1.4,'DisplayName','对象曲线(当前)');
        h.curveOriginal=line(ax(1),nan,nan,'Color',[.6 .6 .6],'LineStyle','--','LineWidth',1,'DisplayName','原始曲线');
        h.ptSearch=line(ax(1),nan,nan,'Color',[.2 .4 .8],'Marker','.','LineStyle','none','MarkerSize',12,'DisplayName','search 评估');
        h.ptHold=line(ax(1),nan,nan,'Color',[.55 .55 .55],'Marker','.','LineStyle','none','MarkerSize',8,'DisplayName','hold 锁定');
        h.ptProbe=line(ax(1),nan,nan,'Color',[.0 .65 .3],'Marker','.','LineStyle','none','MarkerSize',12,'DisplayName','probe 复探');
        h.ptEsc=line(ax(1),nan,nan,'Color',[.65 .3 .75],'Marker','.','LineStyle','none','MarkerSize',8,'DisplayName','esc 步进');
        h.vstar=line(ax(1),nan,nan,'Color',[.85 .2 .2],'Marker','v','LineStyle','none','MarkerSize',9,'DisplayName','v* 真值');
        xlim(ax(1),[0 20]); ylim(ax(1),[0.85 4.2]);
        xlabel(ax(1),'v / m/s'); ylabel(ax(1),'J');
        title(ax(1),'功率曲线与查询点(逐帧)'); legend(ax(1),'Location','northeast','FontSize',8);
        h.speed=line(ax(2),nan,nan,'Color',[.2 .4 .8],'LineWidth',.6,'DisplayName','下发速度');
        h.estimate=line(ax(2),nan,nan,'Color',[.0 .55 .25],'LineWidth',1.4,'DisplayName','估计 v_{hat}');
        h.optimum=line(ax(2),nan,nan,'Color',[.85 .2 .2],'LineStyle','--','LineWidth',1.2,'DisplayName','v* 真值');
        xlabel(ax(2),'评估步'); ylabel(ax(2),'v / m/s');
        title(ax(2),'速度演化：估计 vs 真值'); legend(ax(2),'Location','northwest','FontSize',8);
        h.pTrue=line(ax(3),nan,nan,'Color',[.2 .4 .8],'LineWidth',.8,'DisplayName','真实功率');
        h.pMin=line(ax(3),nan,nan,'Color',[.85 .2 .2],'LineStyle','--','LineWidth',1.1,'DisplayName','离线最优');
        h.pMeas=line(ax(3),nan,nan,'Color',[.55 .3 .7],'Marker','.','LineStyle','none','MarkerSize',7,'DisplayName','测量值');
        xlabel(ax(3),'评估步'); ylabel(ax(3),'P / P_{hover}');
        title(ax(3),'功率轨迹'); legend(ax(3),'Location','north','FontSize',8);
        h.metric=line(ax(4),nan,nan,'Color',[.8 .45 .1],'LineWidth',1.3);
        xlabel(ax(4),'评估步'); title(ax(4),'累计能量超额(开关=开)');
    end

    function redraw()
        if isempty(L), return; end
        n=height(L); k=cursor;
        vis=truth.Value;
        [dx,dy]=task1.shift_truth(scn,L.time(k));
        vv=linspace(0,20,600);
        if vis
            h.curve.XData=vv; h.curve.YData=task1.power_map(vv-dx,c)+dy;
            h.curveOriginal.XData=vv; h.curveOriginal.YData=task1.power_map(vv,c);
            h.vstar.XData=c.optimum0+dx; h.vstar.YData=task1.power_map(c.optimum0,c)+dy;
        else
            h.curve.XData=nan; h.curve.YData=nan;
            h.curveOriginal.XData=nan; h.curveOriginal.YData=nan;
            h.vstar.XData=nan; h.vstar.YData=nan;
        end
        tags=L.tag(1:k); sp=L.speed(1:k); pm=L.powerMeas(1:k);
        setSlice(h.ptSearch,sp,pm,tags,'search');
        setSlice(h.ptProbe,sp,pm,tags,'probe');
        setSlice(h.ptHold,sp,pm,tags,'hold');
        setSlice(h.ptEsc,sp,pm,tags,'esc');
        lastBand=find(~isnan(bIdx(1:k)),1,'last');
        if ~isempty(lastBand)
            br=info.brackets(bIdx(lastBand),:);
            h.band.XData=[br(1) br(2) br(2) br(1)];
            h.band.YData=[0.85 0.85 4.2 4.2];
        else
            h.band.XData=nan(1,4); h.band.YData=nan(1,4);
        end
        h.speed.XData=(1:k)'; h.speed.YData=sp;
        h.estimate.XData=(1:k)'; h.estimate.YData=L.estimate(1:k);
        if vis, h.optimum.XData=(1:k)'; h.optimum.YData=L.optimumTrue(1:k);
        else, h.optimum.XData=nan; h.optimum.YData=nan; end
        xlim(ax(2),[1 n]);
        h.pTrue.XData=(1:k)'; h.pTrue.YData=L.powerTrue(1:k);
        h.pMeas.XData=(1:k)'; h.pMeas.YData=pm;
        if vis, h.pMin.XData=(1:k)'; h.pMin.YData=L.minPowerTrue(1:k);
        else, h.pMin.XData=nan; h.pMin.YData=nan; end
        xlim(ax(3),[1 n]);
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
        ph='—'; if isKey(phaseMap,char(L.tag(k))), ph=phaseMap(char(L.tag(k))); end
        readout.Text=sprintf('步 %d/%d | 相位 %s | 估计 %.2f m/s | 真值 %.2f m/s | 平移(dx=%.2f,dy=%.3f)',...
            k,n,ph,L.estimate(k),L.optimumTrue(k),dx,dy);
        drawnow limitrate;
    end

    function setSlice(hdl,sp,pm,tags,name)
        hit=strcmp(tags,name);
        hdl.XData=sp(hit); hdl.YData=pm(hit);
    end

    function exportCurrent(varargin)
        stopPlayback();
        folder=fullfile(root,'results','task1'); if ~exist(folder,'dir'), mkdir(folder); end
        file=fullfile(folder,['ui_' datestr(now,'yyyymmdd_HHMMSS') '.png']);
        exportapp(fig,file); status.Text=['面板截图已导出：' file];
    end

    function exportGifCurrent(varargin)
        stopPlayback(); if dirty, prepare(); end
        if isempty(L), return; end
        folder=fullfile(root,'results','task1'); if ~exist(folder,'dir'), mkdir(folder); end
        file=fullfile(folder,['task1_playback_' datestr(now,'yyyymmdd_HHMMSS') '.gif']);
        n=height(L); stride=max(1,round(n/48)); status.Text='GIF导出中…'; drawnow;
        savedPosition=fig.Position; fig.Position=[60 40 900 620]; drawnow;
        first=true; cleanupGif=onCleanup(@()set(fig,'Position',savedPosition)); %#ok<NASGU>
        for k=1:stride:n
            cursor=min(k,n); redraw(); drawnow;
            tmp=fullfile(tempdir,sprintf('task1frame_%d.png',randi(1e9)));
            exportapp(fig,tmp);
            [A,map]=rgb2ind(imread(tmp),128);
            if first, imwrite(A,map,file,'gif','LoopCount',Inf,'DelayTime',.15); first=false;
            else, imwrite(A,map,file,'gif','WriteMode','append','DelayTime',.15); end
            delete(tmp);
        end
        cursor=n; redraw();
        status.Text=['GIF动画已导出：' file];
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