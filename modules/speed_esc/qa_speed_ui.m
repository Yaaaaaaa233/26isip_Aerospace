function qa_speed_ui()
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results','ui_qa'); if ~exist(folder,'dir'), mkdir(folder); end
fig=launch_speed_esc('on'); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
u=fig.UserData;
u.finish(); drawnow; exportapp(fig,fullfile(folder,'desktop.png'));
fig.Position=[60 40 1120 780]; drawnow; exportapp(fig,fullfile(folder,'compact.png'));
for name={'play','pause','reset','export','finish','model'}
    position=getpixelposition(u.controls.(name{1}),true);
    assert(position(2)>=45 && position(2)+position(4)<fig.InnerPosition(4),...
        'Action buttons must remain above the footer and inside the figure.');
end
initial=u.getLog(); u.controls.truth.Value=false; u.controls.truth.ValueChangedFcn([],[]);
assert(isequal(initial,u.getLog()));
exportapp(fig,fullfile(folder,'hidden_evaluator.png'));
for version=1:3
    u.controls.version.Value=version; u.controls.version.ValueChangedFcn([],[]);
    u.prepare(); assert(height(u.getLog())==1200);
end
for method={'regression','demod'}
    u.controls.method.Value=method{1}; u.controls.method.ValueChangedFcn([],[]); u.prepare(); u.finish();
    exportapp(fig,fullfile(folder,[method{1} '.png']));
end
for mode={'fixed','dither','esc'}
    u.controls.mode.Value=mode{1}; u.controls.mode.ValueChangedFcn([],[]); u.prepare();
    L=u.getLog();
    if ~strcmp(mode{1},'esc'), assert(max(abs(diff(L.center)))<1e-12); end
end
u.play(); pause(.4); drawnow; u.pause(); assert(strcmp(u.timer.Running,'off'));
cursor=u.getCursor(); pause(.2); drawnow; assert(u.getCursor()==cursor);
u.prepare(); assert(u.getCursor()==1);
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8'); fcloseClean=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 交互面板检查\n\n阶段V1/V2/V3、两种梯度估计、固定/微扰/ESC模式、真值隐藏、播放暂停和重置回调通过。\n\n');
fprintf(fid,'导出桌面与紧凑窗口截图；PNG/GIF/MAT/CSV导出另由run_speed_demo实际执行。\n');
fprintf('UI control checks passed.\n');
end
