function result = add_m0a_actuator_observability()
%ADD_M0A_ACTUATOR_OBSERVABILITY Add non-invasive PWM/RPM observations.
%   Works only on air_spare.slx. Branches the existing eight final motor PWM
%   commands from AttitudeControl/Demux. Estimated RPM uses the current plant's
%   documented linear PWM-to-omega mapping (1000..2000 us -> 0..1000 rad/s).

model = 'air_spare';
wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(model);
end
dirtyBefore = get_param(model, 'Dirty');

try
    set_param(model, 'SimulationCommand', 'update');

    controlLayer = [model '/Attitude Control/AttitudeControl'];
    source = [controlLayer '/Demux'];
    pwmMux = [controlLayer '/M0A Motor PWM Vector'];
    pwmDouble = [controlLayer '/M0A Motor PWM as Double'];
    rpmFcn = [controlLayer '/M0A Estimated Motor RPM'];
    pwmLog = [controlLayer '/M0A Log Motor PWM'];
    rpmLog = [controlLayer '/M0A Log Estimated RPM'];
    targets = {pwmMux, pwmDouble, rpmFcn, pwmLog, rpmLog};
    assert(~any(cellfun(@isBlock, targets)), ...
        'air:M0A:AlreadyInstalled', ...
        'M0-A actuator observability blocks already exist. No changes were made.');

    sourcePorts = get_param(source, 'PortHandles');
    assert(numel(sourcePorts.Outport) == 8, ...
        'air:M0A:UnexpectedMotorCount', ...
        'Expected eight Demux outputs; found %d.', ...
        numel(sourcePorts.Outport));

    sourcePosition = get_param(source, 'Position');
    x0 = sourcePosition(3) + 150;
    y0 = sourcePosition(4) + 100;

    add_block('simulink/Signal Routing/Mux', pwmMux, ...
        'Inputs', '8', 'Position', [x0, y0, x0 + 10, y0 + 150]);
    add_block('simulink/Signal Attributes/Data Type Conversion', pwmDouble, ...
        'Position', [x0 + 75, y0 + 55, x0 + 110, y0 + 90], ...
        'OutDataTypeStr', 'double');
    % Existing flight-control output is constrained to 1000..2000 us.
    % Therefore omega=(PWM-1000) rad/s and rpm=omega*60/(2*pi).
    add_block('simulink/User-Defined Functions/Fcn', rpmFcn, ...
        'Position', [x0 + 175, y0 + 55, x0 + 360, y0 + 95], ...
        'Expr', '9.54929658551372*(u-1000)');
    add_block('simulink/Sinks/To Workspace', pwmLog, ...
        'Position', [x0 + 100, y0 + 140, x0 + 270, y0 + 170], ...
        'VariableName', 'm0a_motor_pwm_us', 'SaveFormat', 'Timeseries');
    add_block('simulink/Sinks/To Workspace', rpmLog, ...
        'Position', [x0 + 450, y0 + 55, x0 + 625, y0 + 85], ...
        'VariableName', 'm0a_motor_rpm_est', 'SaveFormat', 'Timeseries');

    muxPorts = get_param(pwmMux, 'PortHandles');
    pwmDoublePorts = get_param(pwmDouble, 'PortHandles');
    rpmPorts = get_param(rpmFcn, 'PortHandles');
    pwmLogPorts = get_param(pwmLog, 'PortHandles');
    rpmLogPorts = get_param(rpmLog, 'PortHandles');
    for k = 1:8
        add_line(controlLayer, sourcePorts.Outport(k), muxPorts.Inport(k), ...
            'autorouting', 'on');
    end
    add_line(controlLayer, muxPorts.Outport(1), pwmDoublePorts.Inport(1), 'autorouting', 'on');
    add_line(controlLayer, pwmDoublePorts.Outport(1), rpmPorts.Inport(1), 'autorouting', 'on');
    add_line(controlLayer, muxPorts.Outport(1), pwmLogPorts.Inport(1), 'autorouting', 'on');
    add_line(controlLayer, rpmPorts.Outport(1), rpmLogPorts.Inport(1), 'autorouting', 'on');

    set_param(model, 'SimulationCommand', 'update');
    save_system(model);

    result = struct( ...
        'model', model, ...
        'source', string(source), ...
        'pwmLog', string(pwmLog), ...
        'rpmLog', string(rpmLog), ...
        'pwmVariable', "m0a_motor_pwm_us", ...
        'rpmVariable', "m0a_motor_rpm_est", ...
        'rpmDefinition', ...
        "clip((PWM_us-1000)/1000,0,1) * 1000 * 60/(2*pi)");
    fprintf('M0-A actuator observability PASS: %s\n', model);
    fprintf('Logged variables: m0a_motor_pwm_us, m0a_motor_rpm_est\n');
catch err
    if strcmp(dirtyBefore, 'off') && bdIsLoaded(model)
        close_system(model, 0);
        load_system(model);
    end
    rethrow(err);
end
end

function tf = isBlock(path)
try
    get_param(path, 'Handle');
    tf = true;
catch
    tf = false;
end
end
