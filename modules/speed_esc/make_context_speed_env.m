function env = make_context_speed_env()
%MAKE_CONTEXT_SPEED_ENV Optional bridge to the previous wind/SOC experiment.
% Its power object is different: do NOT compare its reward with this project's.
root=fileparts(mfilename('fullpath')); context=fullfile(fileparts(root),'energy_data_rl');
assert(exist(fullfile(context,'+energyrl','make_env.m'),'file')==2,...
    'speedesc:ContextDependency','Keep the existing energy_data_rl sibling project for this optional bridge.');
addpath(context); c=energyrl.config('mode','speed'); env=energyrl.make_env(c);
end
