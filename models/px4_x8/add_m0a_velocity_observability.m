function result = add_m0a_velocity_observability()
%ADD_M0A_VELOCITY_OBSERVABILITY Add M0-A velocity observation blocks.
%   Works only on air_spare.slx. It branches the 6DOF inertial velocity
%   (Ve) without changing the existing flight-control or plant connections.
%   It logs the full Ve vector and horizontal speed v_h = hypot(Ve(1),Ve(2)).

model = 'air_spare';
subsystem = string(model) + "/Subsystem";
wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(model);
end
dirtyBefore = get_param(model, 'Dirty');

try
    set_param(model, 'SimulationCommand', 'update');

    sixDof = find_system(char(subsystem), ...
        'FollowLinks', 'on', 'LookUnderMasks', 'all', ...
        'RegExp', 'on', 'Name', '^6DOF.*');
    assert(numel(sixDof) == 1, ...
        'air:M0A:SixDofNotUnique', ...
        'Expected one 6DOF block under %s; found %d.', subsystem, numel(sixDof));
    sixDof = string(sixDof{1});

    speedFcn = subsystem + "/M0A Horizontal Speed";
    veLog = subsystem + "/M0A Log Ve";
    speedLog = subsystem + "/M0A Log Horizontal Speed";
    targets = [speedFcn; veLog; speedLog];
    assert(~any(arrayfun(@(p) isBlock(p), targets)), ...
        'air:M0A:AlreadyInstalled', ...
        'M0-A velocity observability blocks already exist. No changes were made.');

    sixPosition = get_param(char(sixDof), 'Position');
    x0 = sixPosition(3) + 140;
    y0 = sixPosition(2) - 70;

    add_block('simulink/User-Defined Functions/Fcn', char(speedFcn), ...
        'Position', [x0, y0, x0 + 130, y0 + 35], ...
        'Expr', 'sqrt(u(1)^2 + u(2)^2)');
    add_block('simulink/Sinks/To Workspace', char(veLog), ...
        'Position', [x0, y0 + 85, x0 + 130, y0 + 115], ...
        'VariableName', 'm0a_Ve_inertial_mps', ...
        'SaveFormat', 'Timeseries');
    add_block('simulink/Sinks/To Workspace', char(speedLog), ...
        'Position', [x0 + 230, y0, x0 + 380, y0 + 30], ...
        'VariableName', 'm0a_horizontal_speed_mps', ...
        'SaveFormat', 'Timeseries');

    % Port 1 of 6DOF (Quaternion) is Ve, as verified in the interface audit.
    sixPorts = get_param(char(sixDof), 'PortHandles');
    speedPorts = get_param(char(speedFcn), 'PortHandles');
    veLogPorts = get_param(char(veLog), 'PortHandles');
    speedLogPorts = get_param(char(speedLog), 'PortHandles');
    add_line(char(subsystem), sixPorts.Outport(1), speedPorts.Inport(1), ...
        'autorouting', 'on');
    add_line(char(subsystem), sixPorts.Outport(1), veLogPorts.Inport(1), ...
        'autorouting', 'on');
    add_line(char(subsystem), speedPorts.Outport(1), speedLogPorts.Inport(1), ...
        'autorouting', 'on');

    set_param(model, 'SimulationCommand', 'update');
    save_system(model);

    result = struct( ...
        'model', model, ...
        'subsystem', subsystem, ...
        'sixDof', sixDof, ...
        'velocityLog', veLog, ...
        'horizontalSpeedLog', speedLog, ...
        'speedDefinition', "sqrt(Ve_x^2 + Ve_y^2) (no-wind groundspeed proxy)");
    fprintf('M0-A velocity observability PASS: %s\n', model);
    fprintf('Logged variables: m0a_Ve_inertial_mps, m0a_horizontal_speed_mps\n');
catch err
    % If this call started clean, discard only its own unsaved partial changes.
    if strcmp(dirtyBefore, 'off') && bdIsLoaded(model)
        close_system(model, 0);
        load_system(model);
    end
    rethrow(err);
end
end

function tf = isBlock(path)
try
    get_param(char(path), 'Handle');
    tf = true;
catch
    tf = false;
end
end
