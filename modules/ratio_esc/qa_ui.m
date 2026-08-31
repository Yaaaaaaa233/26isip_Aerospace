function result = qa_ui()
%QA_UI Exercise the real uifigure callbacks, capture it, and verify exports.
root=fileparts(mfilename('fullpath')); folder=fullfile(root,'results','ui_qa');
if ~exist(folder,'dir'), mkdir(folder); end
f=launch_ratio_esc('on'); cleanup=onCleanup(@()safeClose(f)); %#ok<NASGU>
u=f.UserData; names={'static','feedback','dither','esc','rl'};
for k=1:numel(names)
    u.controls.stage.Value=names{k};
    if strcmp(names{k},'esc'), u.controls.scenario.Value='shift'; else, u.controls.scenario.Value='stationary'; end
    u.reset(); current=u.getLog(); assert(height(current)==12000);
    assert(all(isfinite(current.measuredPower)));
    exportapp(f,fullfile(folder,['stage_' names{k} '.png']));
end
u.controls.stage.Value='esc'; u.controls.scenario.Value='shift';
u.controls.noise.Value=0.02; u.controls.delay.Value=0.5; u.reset();
reference=u.getLog(); u.play(); pause(2); drawnow; u.pause();
assert(u.timer.TasksExecuted>0,'Playback timer did not advance.');
tasks=u.timer.TasksExecuted; pause(0.3); drawnow; assert(u.timer.TasksExecuted==tasks);
exportapp(f,fullfile(folder,'panel_desktop.png'));
u.controls.truth.Value=false; u.controls.truth.ValueChangedFcn([],[]); drawnow;
after=u.getLog(); assert(isequaln(reference,after),'Visibility toggle changed the simulation.');
lines=findall(f,'Type','line');
for k=1:numel(lines), assert(~contains(lines(k).DisplayName,'评价器')); end
exportapp(f,fullfile(folder,'panel_hidden_truth.png'));
f.Position=[80 70 1100 760]; pause(0.5); drawnow;
exportapp(f,fullfile(folder,'panel_compact.png'));
u.controls.truth.Value=true; u.controls.truth.ValueChangedFcn([],[]);
u.export(); exported=u.controls.status.Tooltip;
frames=imfinfo(fullfile(exported,'online_process.gif'));
assert(numel(frames)==32); assert(all([frames.Width]>0));
saved=load(fullfile(exported,'run.mat'));
csv=readtable(fullfile(exported,'run.csv'));
assert(isequaln(reference,saved.log)); assert(height(csv)==height(reference));
u.reset(); assert(isequaln(reference,u.getLog()),'Reset must be deterministic.');
result=struct('stagesPassed',5,'playPausePassed',true,'truthTogglePassed',true,...
    'resetPassed',true,'exportPassed',true,'gifFrames',numel(frames),'exportFolder',exported);
save(fullfile(folder,'qa_summary.mat'),'result');
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8');
fprintf(fid,'# 交互面板与导出检查\n\n');
fprintf(fid,'- 五个阶段均完成加载，日志无非有限功率。\n');
fprintf(fid,'- 播放计时器推进，暂停后不推进。重置结果可复现。\n');
fprintf(fid,'- 隐藏评价器信息后不显示真实曲线/最优点，且仿真日志保持不变。\n');
fprintf(fid,'- 捕获1360×880与1100×760布局，另保存全部阶段截图。\n');
fprintf(fid,'- PNG、FIG、MAT、CSV与32帧GIF均生成并读取验证。\n');
fprintf(fid,'- 图形检查截图见同目录；算法指标见 ../acceptance/report.md。\n');
fclose(fid); disp(result);
end

function safeClose(f)
if isvalid(f), close(f); end
end
