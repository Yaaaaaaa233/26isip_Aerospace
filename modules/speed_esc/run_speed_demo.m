function run_speed_demo()
%RUN_SPEED_DEMO Six curve/version cases, plus a classic-demodulation comparison.
root=fileparts(mfilename('fullpath')); addpath(root);
for curve={'debug','cubic'}
    for version=1:3
        c=speedesc.config('curve',curve{1},'version',version);
        folder=fullfile(root,'results',sprintf('v%d_%s',version,curve{1}));
        speedesc.export_run(speedesc.run(c),c,folder,version==3 && strcmp(curve{1},'cubic'));
    end
end
c=speedesc.config('method','demod');
speedesc.export_run(speedesc.run(c),c,fullfile(root,'results','demod_comparison'),false);
fprintf('Speed demos exported under results/. All curves are synthetic proxies.\n');
end
