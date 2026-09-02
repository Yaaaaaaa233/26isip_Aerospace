function QA_TASK3_DEMO()
%QA_UNIFIED_DEMO 任务4三模块面板自检：算法/场景切换、参数变更、开关不改变
% 日志、播放暂停重置、MOP/MOE读出与导出。
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results','ui_qa'); if ~exist(folder,'dir'), mkdir(folder); end
fig=launch_task4_demo('on'); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
u=fig.UserData;
u.finish(); drawnow; exportapp(fig,fullfile(folder,'tracker_jumpUp_end.png'));
% 1) 算法切换(面板仅提供tracker/esc)
for algo={'tracker','esc'}
    u.controls.algorithm.Value=algo{1}; u.controls.algorithm.ValueChangedFcn([],[]);
    u.prepare(); u.finish(); drawnow;
    assert(height(u.getLog())==400,'日志长度应等于400步');
    exportapp(fig,fullfile(folder,[algo{1} '_end.png']));
end
% 2) tracker静态命中 + MOE 有限
u.controls.algorithm.Value='tracker'; u.controls.algorithm.ValueChangedFcn([],[]);
u.controls.scenario.Value='static'; u.controls.scenario.ValueChangedFcn([],[]);
u.prepare(); u.finish();
L=u.getLog(); m=wsearch.mop_moe(L,wsearch.config('seed',11));
assert(abs(L.estimate(end)-L.optimumTrue(end))<=0.6,'tracker应跟踪时变真值最优');
assert(isfinite(m.MOE_energy)&&m.MOE_energy>0&&m.MOE_energy<=1,'MOE必须在(0,1]');
exportapp(fig,fullfile(folder,'tracker_static_end.png'));
% 3) 平移参数在线可调(幅值/时刻)
u.controls.scenario.Value='jumpUp'; u.controls.scenario.ValueChangedFcn([],[]);
u.controls.windAmp.Value=0; u.controls.windBias.Value=0; u.controls.windAmp.ValueChangedFcn([],[]); u.controls.windBias.ValueChangedFcn([],[]);
u.controls.shiftDx.Value=4.0; u.controls.shiftDx.ValueChangedFcn([],[]);
u.prepare(); u.finish();
assert(abs(u.getLog().optimumTrue(400)-10)<1e-9,'dx=4时真值最优应为10');
exportapp(fig,fullfile(folder,'dx4_end.png'));
u.controls.windAmp.Value=5.0; u.controls.windOmega.Value=0.1; u.controls.windBias.Value=0; u.controls.windAmp.ValueChangedFcn([],[]); u.controls.windOmega.ValueChangedFcn([],[]); u.controls.windBias.ValueChangedFcn([],[]);
u.controls.circleT.Value=60; u.controls.circleT.ValueChangedFcn([],[]);
u.prepare(); u.finish();
Lw=u.getLog();
assert(height(Lw)==400,'风场参数生效后日志仍为400步');
[~,dxv]=wsearch.wind_truth(wsearch.scenario('static',wsearch.config('windAmp',5,'windOmega',0.1,'windBias',0,'circlePeriod',60)),Lw.time(400));
vExp=6+u.controls.shiftDx.Value+dxv;
assert(abs(Lw.optimumTrue(400)-vExp)<1e-9,'风场真值最优应随航向计算');
u.controls.windAmp.Value=2.0; u.controls.windBias.Value=3.0; u.controls.windAmp.ValueChangedFcn([],[]); u.controls.windBias.ValueChangedFcn([],[]);
u.controls.circleT.Value=80; u.controls.circleT.ValueChangedFcn([],[]);
% 3b) 三模块切换: 三按钮 + 小窗口放大/还原
u.controls.windAmp.Value=0; u.controls.windBias.Value=0; u.controls.windAmp.ValueChangedFcn([],[]); u.controls.windBias.ValueChangedFcn([],[]);
u.setView('air'); drawnow;
ap=u.airPanel; ep=u.envPanel;
assert(any(ap.Layout.Row)==1,'airPanel应放大(跨绘图网格)');
assert(~any(ep.Layout.Row)==1 || ep.Layout.Row(1)==3,'envPanel应保持第三行小格');
u.setView('env'); drawnow;
u.setView('console'); drawnow;
assert(ap.Layout.Row(1)==3,'还原后airPanel应回第三行');
u.controls.windAmp.Value=2.0; u.controls.windBias.Value=3.0; u.controls.windAmp.ValueChangedFcn([],[]); u.controls.windBias.ValueChangedFcn([],[]);
% 4) 真值/能耗开关不改变日志
initial=u.getLog();
u.controls.truth.Value=false; u.controls.truth.ValueChangedFcn([],[]);
u.controls.energy.Value=false; u.controls.energy.ValueChangedFcn([],[]);
assert(logsEqual(initial,u.getLog()));
exportapp(fig,fullfile(folder,'energy_off.png'));
u.controls.truth.Value=true; u.controls.truth.ValueChangedFcn([],[]);
u.controls.energy.Value=true; u.controls.energy.ValueChangedFcn([],[]);
% 5) 播放/暂停/重置
u.play(); pause(.4); drawnow; u.pause(); assert(strcmp(u.timer.Running,'off'));
cur=u.getCursor(); pause(.2); drawnow; assert(u.getCursor()==cur);
u.prepare(); assert(u.getCursor()==1);
% 6) 日志栏与验收报告载入
u.logMsg('QA测试日志条目');
u.loadReport();
assert(~isempty(u.getLog),'日志句柄可用'); %#ok<NASGU>
% 7) 导出
u.exportPng();
fid=fopen(fullfile(folder,'report.md'),'w','n','UTF-8'); fcloseClean=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['# 任务4三模块面板自检\n\n算法/场景切换(tracker/esc)、dx=4平移参数生效、'...
    'tracker静态命中、开关不改变日志、播放暂停重置、PNG导出通过。\n']);
fprintf('任务4三模块面板自检通过。\n');

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
end
