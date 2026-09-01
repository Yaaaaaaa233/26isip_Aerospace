function qa_task1_demo()
%QA_TASK1_DEMO 任务1动画面板自检：算法/场景切换、真值隐藏、能耗开关、
% 播放暂停、重置回调与末帧导出。全部为已完成仿真的回放检查。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results','task1','ui_qa'); if ~exist(folder,'dir'), mkdir(folder); end
fig=launch_task1_demo('on'); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
u=fig.UserData;
u.finish(); drawnow; exportapp(fig,fullfile(folder,'tracker_jumpUp_end.png'));
% 1) 切换算法与场景
for algo={'tracker','brent','golden','grid','esc'}
    u.controls.algorithm.Value=algo{1}; u.controls.algorithm.ValueChangedFcn([],[]);
    u.prepare(); u.finish(); drawnow;
    assert(height(u.getLog())==u.controls.duration.Value,'日志长度必须等于总步数');
    exportapp(fig,fullfile(folder,[algo{1} '_end.png']));
end
% 2) tracker 在 dy-only 场景不重搜(面板路径复现验收结论)
u.controls.algorithm.Value='tracker'; u.controls.algorithm.ValueChangedFcn([],[]);
u.controls.scenario.Value='offset'; u.controls.scenario.ValueChangedFcn([],[]);
u.prepare(); u.finish();
assert(u.getInfo().researchCount==0,'offset场景不应触发重搜');
% 3) 真值隐藏不改变仿真日志
initial=u.getLog(); u.controls.truth.Value=false; u.controls.truth.ValueChangedFcn([],[]);
assert(isequal(initial,u.getLog()));
exportapp(fig,fullfile(folder,'hidden_truth.png'));
% 4) 能耗开关只切评价显示，不重跑仿真
u.controls.truth.Value=true; u.controls.truth.ValueChangedFcn([],[]);
u.controls.energy.Value=false; u.controls.energy.ValueChangedFcn([],[]);
assert(isequal(initial,u.getLog()));
exportapp(fig,fullfile(folder,'energy_off.png'));
u.controls.energy.Value=true; u.controls.energy.ValueChangedFcn([],[]);
% 5) 播放/暂停/重置
u.play(); pause(.4); drawnow; u.pause(); assert(strcmp(u.timer.Running,'off'));
cursor=u.getCursor(); pause(.2); drawnow; assert(u.getCursor()==cursor);
u.prepare(); assert(u.getCursor()==1);
% 6) 导出
u.exportPng(); u.finish();
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8'); fcloseClean=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 任务1动画面板自检\n\n');
fprintf(fid,'算法/场景切换、dy-only不重搜、真值隐藏与能耗开关不改变日志、播放暂停重置、PNG导出通过。\n\n');
fprintf(fid,'截图：tracker_jumpUp_end、各算法末帧、hidden_truth、energy_off。\n');
fprintf('任务1动画面板自检通过。\n');
end
