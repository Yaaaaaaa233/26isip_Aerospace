function result = run_baseline(stopTime)
%RUN_BASELINE Run and archive a non-destructive baseline for air.slx.
%   RESULT = RUN_BASELINE() updates and simulates air.slx using its
%   configured 10 s stop time.  The model is never saved or modified on disk.
%   Outputs are written under results/air_baseline/<timestamp>/.
%
%   RESULT = RUN_AIR_BASELINE(STOPTIME) overrides only this run's stop time.

model = 'air';
modelDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(modelDir));
wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(fullfile(modelDir, [model '.slx']));
end
cleanup = onCleanup(@() closeIfOpenedHere(model, wasLoaded)); %#ok<NASGU>

if nargin < 1
    stopTime = str2double(get_param(model, 'StopTime'));
end
validateattributes(stopTime, {'numeric'}, {'scalar', 'finite', 'positive'});

% Update first so a missing library or unresolved signal fails before sim.
set_param(model, 'SimulationCommand', 'update');

simOut = sim(model, ...
    'StopTime', num2str(stopTime, '%.15g'), ...
    'ReturnWorkspaceOutputs', 'on', ...
    'SaveTime', 'on', ...
    'SaveOutput', 'on', ...
    'SignalLogging', 'on');

if ~isempty(simOut.ErrorMessage)
    error('air:BaselineSimulationFailed', '%s', simOut.ErrorMessage);
end

time = simOut.tout;
topBlocks = find_system(model, 'SearchDepth', 1, 'Type', 'Block');
topBlocks = topBlocks(~strcmp(topBlocks, model));
blockType = cellfun(@(b) get_param(b, 'BlockType'), topBlocks, ...
    'UniformOutput', false);
topLevel = table(string(topBlocks), string(blockType), ...
    'VariableNames', {'Path', 'BlockType'});

result = struct();
result.model = model;
result.passed = true;
result.stopTime = stopTime;
result.sampleCount = numel(time);
result.firstTime = time(1);
result.lastTime = time(end);
result.solver = get_param(model, 'Solver');
result.fixedStep = get_param(model, 'FixedStep');
result.topLevel = topLevel;

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outDir = fullfile(repoRoot, 'results', 'air_baseline', stamp);
if ~isfolder(outDir)
    mkdir(outDir);
end

summary = table( ...
    ["model"; "passed"; "stop_time_s"; "sample_count"; "first_time_s"; ...
     "last_time_s"; "solver"; "fixed_step"], ...
    [string(result.model); string(result.passed); string(result.stopTime); ...
     string(result.sampleCount); string(result.firstTime); string(result.lastTime); ...
     string(result.solver); string(result.fixedStep)], ...
    'VariableNames', {'Metric', 'Value'});

writetable(summary, fullfile(outDir, 'summary.csv'));
writetable(topLevel, fullfile(outDir, 'top_level_blocks.csv'));
save(fullfile(outDir, 'baseline.mat'), 'result', 'simOut');

fprintf('Baseline PASS: %s\n', model);
fprintf('Samples: %d, time: %.6g to %.6g s\n', ...
    result.sampleCount, result.firstTime, result.lastTime);
fprintf('Archived: %s\n', outDir);
end

function closeIfOpenedHere(model, wasLoaded)
if ~wasLoaded && bdIsLoaded(model)
    close_system(model, 0);
end
end
