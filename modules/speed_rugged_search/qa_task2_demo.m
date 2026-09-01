function qa_task2_demo()
%QA_TASK2_DEMO 任务2动画面板自检：算法切换、参数变更重跑、真值/能耗开关、
% 播放暂停重置、无偏移复核与导出。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'..','results','task2','ui_qa'); if ~exist(folder,'dir'), mkdir(folder); end
fig=launch_task2_demo('on'); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
u=fig.UserData;
u.finish(); drawnow; exportapp(fig,fullfile(folder,'multistart_end.png'));
% 1) 算法切换
for algo={'multistart','filter_argmin','single_golden','grid','esc'}
    u.controls.algorithm.Value=algo{1}; u.controls.algorithm.ValueChangedFcn([],[]);
    u.prepare(); u.finish(); drawnow;
    assert(height(u.getLog())==u.controls.seed.Value*0+400,'日志长度应等于400步');
    exportapp(fig,fullfile(folder,[algo{1} '_end.png']));
end
% 2) multistart 无偏移复核(面板路径)
u.controls.algorithm.Value='multistart'; u.controls.algorithm.ValueChangedFcn([],[]);
u.prepare(); u.finish();
L=u.getLog(); m=task2.evaluate(L,struct('filterMethod','sg','filterW',7,'filteredArgmin',NaN),task2.config());
assert(abs(L.estimate(end)-m.globalOptimum)<=0.4,'面板路径应命中全局谷');
% 3) 参数变更(初速/崎岖幅值)生效：初速2会作为候选被评估, 日志仍完整
u.controls.initial.Value=2; u.controls.initial.ValueChangedFcn([],[]);
u.prepare(); u.finish();
assert(height(u.getLog())==400,'初速2下日志仍应为400步');
assert(any(abs(u.getLog().speed-2)<1e-9),'初速2应作为候选被评估');
exportapp(fig,fullfile(folder,'initial2_end.png'));
u.controls.ripA1.Value=0; u.controls.ripA1.ValueChangedFcn([],[]);
u.prepare(); u.finish();
assert(height(u.getLog())==400,'崎岖置零后日志仍应为400步');
% 4) 真值隐藏与能耗开关不改变日志
initial=u.getLog();
u.controls.truth.Value=false; u.controls.truth.ValueChangedFcn([],[]);
u.controls.energy.Value=false; u.controls.energy.ValueChangedFcn([],[]);
assert(logsEqual(initial,u.getLog()),'开关切换不得改变日志');
u.controls.truth.Value=true; u.controls.truth.ValueChangedFcn([],[]);
u.controls.energy.Value=true; u.controls.energy.ValueChangedFcn([],[]);
assert(logsEqual(initial,u.getLog()),'切回后日志也不得改变');
exportapp(fig,fullfile(folder,'energy_off.png'));
% 5) 播放/暂停/重置
u.play(); pause(.4); drawnow; u.pause(); assert(strcmp(u.timer.Running,'off'));
cur=u.getCursor(); pause(.2); drawnow; assert(u.getCursor()==cur);
u.prepare(); assert(u.getCursor()==1);
% 6) 导出
u.exportPng();
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8'); fcloseClean=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['# 任务2动画面板自检\n\n算法切换、初速/崎岖参数变更重跑、multistart全局命中、'...
    '真值隐藏与能耗开关不改变日志、播放暂停重置、PNG导出通过。\n\n截图：'...
    '各算法末帧、initial2_end、energy_off。\n']);
fprintf('任务2动画面板自检通过。\n');
end

    function eq=logsEqual(a,b)
        eq=isequal(a.Properties.VariableNames,b.Properties.VariableNames) && ...
            height(a)==height(b);
        for vn=a.Properties.VariableNames
            x=a.(vn{1}); y=b.(vn{1});
            if isnumeric(x)
                eq=eq && all((x==y)|(isnan(x)&isnan(y)));
            else
                eq=eq && isequal(x,y);
            end
        end
    end
