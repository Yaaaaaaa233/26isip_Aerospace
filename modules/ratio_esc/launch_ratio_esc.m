function fig = launch_ratio_esc(varargin)
%LAUNCH_RATIO_ESC Chinese staged simulator. Playback never alters simulation.
root=fileparts(mfilename('fullpath')); addpath(root);
visible='on'; if nargin, visible=varargin{1}; end
fig=uifigure('Name','转速比ESC开发与过程演示','Position',[70 50 1360 880],...
    'Color',[0.96 0.97 0.98],'Visible',visible);
outer=uigridlayout(fig,[3 2]); outer.RowHeight={52,'1x',28};
outer.ColumnWidth={275,'1x'}; outer.Padding=[14 10 14 10]; outer.RowSpacing=10;
header=uilabel(outer,'Text','转速比ESC | 恒推力假设下的仿真代理模型，非实测',...
    'FontName','Microsoft YaHei','FontSize',18,'FontWeight','bold');
header.Layout.Row=1; header.Layout.Column=[1 2];
panel=uipanel(outer,'Title','实验配置','FontName','Microsoft YaHei');
panel.Layout.Row=2; panel.Layout.Column=1;
g=uigridlayout(panel,[16 2]); g.ColumnWidth={95,'1x'};
g.RowHeight={24,32,24,32,30,30,30,30,30,30,30,28,34,34,'1x',40};
g.Padding=[10 8 10 8]; g.RowSpacing=6;
g.Scrollable='on';
lab(g,'阶段',1,[1 2]);
stage=uidropdown(g,'Items',{'A 静态曲线','B 固定参考反馈','C 微扰观察','D 在线ESC','E RL接口验证'},...
    'ItemsData',{'static','feedback','dither','esc','rl'},'Value','esc'); place(stage,2,[1 2]);
lab(g,'对象工况',3,[1 2]);
scenario=uidropdown(g,'Items',{'最优点不变','300 s时最优点变化'},'ItemsData',{'stationary','shift'});
place(scenario,4,[1 2]);
initial=number(g,'初始转速比',5,1.2,[0.75 1.25]);
fixed=number(g,'固定参考值',6,0.95,[0.75 1.25]);
noise=number(g,'噪声标准差',7,0,[0 0.1]);
delay=number(g,'测量延迟 / s',8,0,[0 5]);
amp=number(g,'微扰幅值',9,0.02,[0.001 0.2]);
freq=number(g,'微扰频率 / Hz',10,0.1,[0.01 2]);
gain=number(g,'学习增益',11,0.003,[0.00001 0.1]);
truth=uicheckbox(g,'Text','显示评价器曲线与最优点','Value',true); place(truth,12,[1 2]);
play=uibutton(g,'Text','播放'); place(play,13,1);
pause=uibutton(g,'Text','暂停'); place(pause,13,2);
reset=uibutton(g,'Text','重置'); place(reset,14,1);
export=uibutton(g,'Text','导出'); place(export,14,2);
readout=uilabel(g,'Text','','FontName','Microsoft YaHei','WordWrap','on'); place(readout,16,[1 2]);
plotGrid=uigridlayout(outer,[2 2]); plotGrid.Layout.Row=2; plotGrid.Layout.Column=2;
plotGrid.RowHeight={'1x','1x'}; plotGrid.ColumnWidth={'1x','1x'};
plotGrid.Padding=[0 0 0 0]; plotGrid.RowSpacing=18; plotGrid.ColumnSpacing=12;
ax=gobjects(1,4);
for k=1:4
    ax(k)=uiaxes(plotGrid); disableDefaultInteractivity(ax(k)); ax(k).Toolbar.Visible='off';
end
status=uilabel(outer,'Text','就绪','FontName','Microsoft YaHei','FontColor',[0.30 0.37 0.43]);
status.Layout.Row=3; status.Layout.Column=[1 2];
log=table(); config=[]; cursor=1; dirty=true;
clock=timer('ExecutionMode','fixedSpacing','Period',0.15,'BusyMode','drop','TimerFcn',@tick);
controls=struct('stage',stage,'scenario',scenario,'initial',initial,'fixed',fixed,...
    'noise',noise,'delay',delay,'amplitude',amp,'frequency',freq,'gain',gain,...
    'truth',truth,'play',play,'pause',pause,'reset',reset,'export',export,'status',status);
fig.UserData=struct('controls',controls,'timer',clock,'prepare',@prepare,'play',@playRun,...
    'pause',@stopPlayback,'reset',@resetRun,'export',@exportCurrent,'getLog',@readLog);
fields={stage,scenario,initial,fixed,noise,delay,amp,freq,gain};
for k=1:numel(fields), fields{k}.ValueChangedFcn=@changed; end
truth.ValueChangedFcn=@(~,~)redraw(); play.ButtonPushedFcn=@playRun;
pause.ButtonPushedFcn=@stopPlayback; reset.ButtonPushedFcn=@resetRun; export.ButtonPushedFcn=@exportCurrent;
fig.CloseRequestFcn=@closeApp;
prepare();

    function c=readConfig()
        c=ratioesc.config('stage',stage.Value,'scenario',scenario.Value,'initialRatio',initial.Value,...
            'fixedReference',fixed.Value,'noiseSigma',noise.Value,'delay',delay.Value,...
            'amplitude',amp.Value,'frequency',freq.Value,'gain',gain.Value);
    end
    function value=readLog()
        value=log;
    end
    function prepare(varargin)
        if strcmp(clock.Running,'on'), stop(clock); end
        try
            status.Text='正在进行因果闭环仿真...'; drawnow;
            config=readConfig(); log=ratioesc.run(config); cursor=1; dirty=false; redraw();
            status.Text='就绪 | 回放显示已完成的因果仿真；RL阶段为随机策略接口检查，未训练';
        catch err
            status.Text=['配置或仿真错误: ' err.message]; dirty=true;
            rethrow(err);
        end
    end
    function playRun(varargin)
        if dirty || isempty(log), prepare(); end
        if cursor>=height(log), cursor=1; end
        if strcmp(clock.Running,'off'), startTimer(); end
        status.Text='播放中 | 参数在下次运行生效';
    end
    function startTimer()
        start(clock);
    end
    function stopPlayback(varargin)
        if strcmp(clock.Running,'on'), stop(clock); end
        status.Text='已暂停';
    end
    function resetRun(varargin)
        prepare();
    end
    function changed(varargin)
        stopPlayback(); dirty=true; status.Text='配置已更改 | 下次播放重新运行';
    end
    function tick(varargin)
        if ~isvalid(fig), return; end
        cursor=min(height(log),cursor+max(1,round(height(log)/70))); redraw();
        if cursor>=height(log)
            stop(clock); m=ratioesc.metrics(log,config);
            status.Text=sprintf('完成 | 最后100 s超额功率 %.3f%% | 越界次数 %d',...
                m.finalExcessPercent,m.boundViolations);
        end
    end
    function redraw()
        if isempty(log), return; end
        ratioesc.draw_frame(ax,log,config,cursor,truth.Value);
        readout.Text=sprintf('t = %.1f s\n实际比 %.4f | 测量J %.4f',...
            log.time(cursor),log.ratio(cursor),log.measuredPower(cursor));
        drawnow limitrate;
    end
    function exportCurrent(varargin)
        stopPlayback();
        if dirty || isempty(log), prepare(); end
        name=['ui_' datestr(now,'yyyymmdd_HHMMSS')];
        folder=fullfile(root,'results',name);
        status.Text='正在导出图表、动画和日志...'; drawnow;
        ratioesc.export_run(log,config,folder,true);
        status.Text=['已导出: ' name]; status.Tooltip=folder;
    end
    function closeApp(varargin)
        if isvalid(clock), stop(clock); delete(clock); end
        delete(fig);
    end
end

function h=number(g,text,row,value,limits)
lab(g,text,row,1);
h=uieditfield(g,'numeric','Value',value,'Limits',limits,'RoundFractionalValues','off');
place(h,row,2);
end
function lab(g,text,row,col)
h=uilabel(g,'Text',text,'FontName','Microsoft YaHei'); place(h,row,col);
end
function place(h,row,col)
h.Layout.Row=row; h.Layout.Column=col;
end
