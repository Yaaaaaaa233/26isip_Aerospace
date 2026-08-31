function result = inspect_interfaces()
%INSPECT_INTERFACES Export current port connectivity without saving air.slx.
%   RESULT = INSPECT_INTERFACES() updates the compiled diagram, reads
%   subsystem and 6DOF port connectivity, and writes a CSV under results/.

model = 'air';
modelDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(modelDir));
wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(fullfile(modelDir, [model '.slx']));
end
cleanup = onCleanup(@() closeIfOpenedHere(model, wasLoaded)); %#ok<NASGU>
set_param(model, 'SimulationCommand', 'update');

targets = string({ ...
    'air/Attitude Control', ...
    'air/Attitude Control/AttitudeControl', ...
    'air/Subsystem'});
targets = targets(:);

sixDof = find_system(model, ...
    'FollowLinks', 'on', 'LookUnderMasks', 'all', ...
    'RegExp', 'on', 'Name', '6DOF.*');
targets = unique([targets; string(sixDof(:))], 'stable');

rows = table(strings(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), strings(0, 1), ...
    zeros(0, 1), strings(0, 1), ...
    'VariableNames', {'Block', 'PortIndex', 'PortType', 'SourceBlock', ...
    'SourcePort', 'DestinationBlock', 'DestinationPort', 'SignalName'});

for target = targets'
    if ~bdIsLoaded(model) || ~ishandle(get_param(char(target), 'Handle'))
        continue;
    end
    connectivity = get_param(char(target), 'PortConnectivity');
    for k = 1:numel(connectivity)
        c = connectivity(k);
        signalName = "";
        if isfield(c, 'SignalName') && ~isempty(c.SignalName)
            signalName = string(c.SignalName);
        end
        rows = [rows; table( ... %#ok<AGROW>
            target, k, string(c.Type), blockPaths(c.SrcBlock), ...
            firstNumber(c.SrcPort), blockPaths(c.DstBlock), ...
            firstNumber(c.DstPort), signalName, ...
            'VariableNames', rows.Properties.VariableNames)];
    end
end

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outDir = fullfile(repoRoot, 'results', 'air_interface_inspection', stamp);
if ~isfolder(outDir)
    mkdir(outDir);
end
writetable(rows, fullfile(outDir, 'port_connectivity.csv'));

result = struct('model', model, 'passed', true, 'targets', targets, ...
    'sixDofBlocks', string(sixDof), 'portConnectivity', rows, ...
    'outputDirectory', string(outDir));
save(fullfile(outDir, 'interface_inspection.mat'), 'result');

fprintf('Interface inspection PASS: %s\n', model);
fprintf('6DOF blocks found: %d\n', numel(sixDof));
fprintf('Archived: %s\n', outDir);
end

function paths = blockPaths(handles)
if isempty(handles) || all(handles == -1)
    paths = "";
    return;
end

paths = strings(1, numel(handles));
for n = 1:numel(handles)
    if handles(n) == -1
        paths(n) = "";
    else
        paths(n) = string(getfullname(handles(n)));
    end
end
paths = join(paths(paths ~= ""), '; ');
end

function value = firstNumber(values)
if isempty(values)
    value = NaN;
else
    value = values(1);
end
end

function closeIfOpenedHere(model, wasLoaded)
if ~wasLoaded && bdIsLoaded(model)
    close_system(model, 0);
end
end
