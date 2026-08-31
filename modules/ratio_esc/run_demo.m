function run_demo()
%RUN_DEMO Generate the five stages without opening an interactive session.
root=fileparts(mfilename('fullpath')); addpath(root);
stages={'static','feedback','dither','esc','rl'};
for k=1:numel(stages)
    c=ratioesc.config('stage',stages{k});
    if strcmp(c.stage,'esc'), c.scenario='shift'; end
    if strcmp(c.stage,'dither'), c.initialRatio=0.8; end
    log=ratioesc.run(c);
    ratioesc.export_run(log,c,fullfile(root,'results',['stage_' stages{k}]),strcmp(c.stage,'esc'));
end
build_simulink(ratioesc.config());
disp('Stage results exported to results/. Launch launch_ratio_esc for interactive playback.');
end
