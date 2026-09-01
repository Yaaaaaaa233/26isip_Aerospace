function fig = launch_speed_esc(visible)
%LAUNCH_SPEED_ESC Chinese panel. Plot playback is independent of simulation.
if nargin<1, visible='on'; end
root=fileparts(mfilename('fullpath')); addpath(root);
fig=uifigure('Name','平飞速度ESC整合版','Position',[60 40 1420 940],...
    'Color',[.96 .97 .98],'Visible',visible,'AutoResizeChildren','off');
outer=uigridlayout(fig,[3 2]); outer.RowHeight={44,'1x',28}; outer.ColumnWidth={315,'1x'};
outer.Padding=[12 10 12 10]; outer.RowSpacing=10;
header=uilabel(outer,'Text','平飞速度在线寻优 | 固定上下桨配比，仿真代理模型，非实测',...
    'FontName','Microsoft YaHei','FontSize',17,'FontWeight','bold'); put(header,1,[1 2]);
left=uigridlayout(outer,[3 1]); put(left,2,1); left.RowHeight={'1x',116,48};
left.Padding=[0 0 0 0]; left.RowSpacing=8;
form=uipanel(left,'BorderType','none'); put(form,1,1);
g=uigridlayout(form,[16 2]); g.ColumnWidth={140,'1x'};
g.RowHeight=[repmat({30},1,12),{26,30,26,30}];
g.Padding=[0 0 8 0]; g.RowSpacing=7; g.Scrollable='on';
version=choice(g,'对象阶段',1,{'V1 静态','V2 速度响应','V3 噪声/延迟/变化'},{1,2,3},3);
curve=choice(g,'功率曲线',2,{'调试二次曲线','三次代理曲线'},{'debug','cubic'},'cubic');
method=choice(g,'梯度估计方法',3,{'窗口回归','经典同频解调'},{'regression','demod'},'regression');
mode=choice(g,'运行模式',4,{'完整ESC','仅微扰','固定参考'},{'esc','dither','fixed'},'esc');
initial=number(g,'初始速度 / m/s',5,10,[0 20]); tau=number(g,'响应时间常数 / s',6,2,[.1 20]);
noise=number(g,'相对噪声标准差',7,.02,[0 .2]); delay=number(g,'功率延迟 / s',8,.5,[0 2]);
amplitude=number(g,'微扰幅值 / m/s',9,.5,[.01 3]); omega=number(g,'角频率 / rad/s',10,.5,[.1 3]);
gain=number(g,'学习增益',11,8,[.001 60]); duration=number(g,'总时长 / s',12,120,[40 600]);
shift=uicheckbox(g,'Text','启用对象最优点变化','Value',true); put(shift,13,[1 2]);
shiftTime=number(g,'变化发生时间 / s',14,60,[1 500]);
truth=uicheckbox(g,'Text','显示评价器曲线与真值','Value',true); put(truth,15,[1 2]);
fixed=number(g,'固定参考 / m/s',16,10,[0 20]);
actions=uigridlayout(left,[3 2]); put(actions,2,1); actions.Padding=[0 0 8 0];
actions.RowHeight={34,34,34}; actions.RowSpacing=7;
play=uibutton(actions,'Text','播放'); put(play,1,1); pause=uibutton(actions,'Text','暂停'); put(pause,1,2);
reset=uibutton(actions,'Text','重置'); put(reset,2,1); export=uibutton(actions,'Text','导出'); put(export,2,2);
finish=uibutton(actions,'Text','查看末帧'); put(finish,3,1); model=uibutton(actions,'Text','打开Simulink'); put(model,3,2);
readout=uilabel(left,'Text','','WordWrap','on','FontName','Microsoft YaHei'); put(readout,3,1);
plots=uigridlayout(outer,[2 2]); put(plots,2,2); plots.Padding=[0 0 0 0]; plots.RowSpacing=14;
ax=gobjects(1,4); for k=1:4, ax(k)=uiaxes(plots); disableDefaultInteractivity(ax(k)); ax(k).Toolbar.Visible='off'; end
status=uilabel(outer,'Text','就绪','FontName','Microsoft YaHei'); put(status,3,[1 2]);
clock=timer('ExecutionMode','fixedSpacing','Period',.15,'BusyMode','drop','TimerFcn',@tick);
L=table(); c=[]; cursor=1; dirty=true;
controls=struct('version',version,'curve',curve,'method',method,'mode',mode,'initial',initial,...
    'tau',tau,'noise',noise,'delay',delay,'amplitude',amplitude,'omega',omega,'gain',gain,...
    'duration',duration,'shift',shift,'shiftTime',shiftTime,'truth',truth,'play',play,'pause',pause,...
    'reset',reset,'export',export,'finish',finish,'model',model,'fixed',fixed);
fig.UserData=struct('controls',controls,'prepare',@prepare,'play',@playback,'pause',@stopPlayback,...
    'finish',@toEnd,'export',@exportCurrent,'getLog',@getLog,'getCursor',@getCursor,'timer',clock);
for control={version,curve,method,mode,initial,fixed,tau,noise,delay,amplitude,omega,gain,duration,shift,shiftTime}
    control{1}.ValueChangedFcn=@changed;
end
curve.ValueChangedFcn=@preset; method.ValueChangedFcn=@preset; version.ValueChangedFcn=@stageChanged;
truth.ValueChangedFcn=@(~,~)redraw(); play.ButtonPushedFcn=@playback; pause.ButtonPushedFcn=@stopPlayback;
reset.ButtonPushedFcn=@prepare; finish.ButtonPushedFcn=@toEnd; export.ButtonPushedFcn=@exportCurrent;
model.ButtonPushedFcn=@openModel; fig.CloseRequestFcn=@closeApp;
fig.SizeChangedFcn=@resizeLayout;
resizeLayout(); stageChanged(); prepare();

    function resizeLayout(varargin)
        % Explicit tracks prevent nested grids' content minimum from hiding controls.
        bodyHeight=max(300,fig.InnerPosition(4)-112);
        outer.RowHeight={44,bodyHeight,28};
        left.RowHeight={max(120,bodyHeight-180),116,48};
    end

    function changed(varargin)
        stopPlayback(); dirty=true; status.Text='参数已更改';
    end
    function preset(varargin)
        defaults=speedesc.config('curve',curve.Value,'method',method.Value);
        gain.Value=defaults.gain; changed();
    end
    function stageChanged(varargin)
        enabled='off'; if version.Value==3, enabled='on'; end
        for h={noise,delay,shift,shiftTime}, h{1}.Enable=enabled; end
        tau.Enable='on'; if version.Value==1, tau.Enable='off'; end
        changed();
    end
    function prepare(varargin)
        stopPlayback();
        c=speedesc.config('version',version.Value,'curve',curve.Value,'method',method.Value,...
            'mode',mode.Value,'initialSpeed',initial.Value,'fixedReference',fixed.Value,'tau',tau.Value,...
            'noiseSigma',noise.Value,'delay',delay.Value,'amplitude',amplitude.Value,'omega',omega.Value,...
            'gain',gain.Value,'duration',duration.Value,'shift',shift.Value,'shiftTime',shiftTime.Value);
        L=speedesc.run(c); cursor=1; dirty=false; redraw(); status.Text='就绪';
    end
    function playback(varargin)
        try
            if dirty, prepare(); end
            if cursor>=height(L), cursor=1; end
            if strcmp(clock.Running,'off'), start(clock); end
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
        cursor=height(L); redraw(); report();
    end
    function report()
        m=speedesc.metrics(L,c);
        status.Text=sprintf('末段功率超额 %.3f%% | 实际速度均值误差 %.3f m/s | 参考越界 %d',...
            m.regretPercent,m.speedError,m.boundViolations);
    end
    function redraw()
        if isempty(L), return; end
        speedesc.draw_frame(ax,L,c,cursor,truth.Value);
        readout.Text=sprintf('t=%.1f s | 实际速度 %.2f m/s\n收到的功率 J=%.4f',...
            L.time(cursor),L.actualSpeed(cursor),L.measuredPower(cursor));
        drawnow limitrate;
    end
    function exportCurrent(varargin)
        stopPlayback(); if dirty, prepare(); end
        folder=fullfile(root,'results',['ui_' datestr(now,'yyyymmdd_HHMMSS')]);
        speedesc.export_run(L,c,folder,true); status.Text='结果已导出'; status.Tooltip=folder;
    end
    function openModel(varargin)
        stopPlayback(); if dirty, prepare(); end
        [file,~]=build_speed_simulink(c); open_system(file);
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
