function result = add_air_m0a_power_measurement()
%ADD_AIR_M0A_POWER_MEASUREMENT Add replaceable estimated power measurement.
%   Works only on air_spare.slx. Branches the existing root-level eight-channel
%   PWM line (Attitude Control output 2, the line feeding Demux -> plant) into
%   a new M0A Power Measurement subsystem that produces P_est, E_est and a
%   power source flag (0 = estimated, 1 = measured/calibrated, reserved).
%
%   The estimate mirrors the plant's documented mapping (chart inside
%   Subsystem): omega = (PWM_us - 1000) rad/s in [0, 1000],
%   Q_i = C_M * omega_i^2, so shaft power P_i = Q_i * omega_i = C_M*omega_i^3
%   with C_M = 2.51e-7 kept identical to the plant torque coefficient.
%   UNCALIBRATED ESTIMATE: must not be reported as real energy saving.

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(fullfile(modelDir, [model '.slx']));
end
dirtyBefore = get_param(model, 'Dirty');

try
    set_param(model, 'SimulationCommand', 'update');

    acPath = [model '/Attitude Control'];
    pwmConvert = [model '/M0A PWM Vector Double'];
    powerBlock = [model '/M0A Power Measurement'];
    pCore = [powerBlock '/M0A P Est Core'];
    eInteg = [powerBlock '/M0A Energy Integrator'];
    srcConst = [powerBlock '/M0A Power Source Flag'];
    logP = [model '/M0A Log P Est'];
    logE = [model '/M0A Log E Est'];
    logSrc = [model '/M0A Log Power Source'];
    targets = {pwmConvert, powerBlock, logP, logE, logSrc};
    assert(~any(cellfun(@isBlock, targets)), ...
        'air:M0A:AlreadyInstalled', ...
        'M0-A power measurement blocks already exist. No changes were made.');

    acPorts = get_param(acPath, 'PortHandles');
    assert(numel(acPorts.Outport) >= 2, ...
        'air:M0A:UnexpectedAttitudeControlPorts', ...
        'Expected at least two Attitude Control outputs; found %d.', ...
        numel(acPorts.Outport));

    demuxPosition = get_param([model '/Demux'], 'Position');
    x0 = demuxPosition(3) + 200;
    y0 = demuxPosition(4) + 220;

    % Root: convert the muxed uint16 PWM vector to double once; later M0-A
    % stages reuse this signal for constraint flags and the unified log bus.
    add_block('simulink/Signal Attributes/Data Type Conversion', pwmConvert, ...
        'Position', [x0, y0, x0 + 45, y0 + 30], 'OutDataTypeStr', 'double');

    add_block('built-in/Subsystem', powerBlock, ...
        'Position', [x0 + 120, y0 - 10, x0 + 280, y0 + 140]);

    % --- inside M0A Power Measurement ---
    add_block('built-in/Inport', [powerBlock '/pwm_us'], ...
        'Position', [30, 63, 60, 77], 'Port', '1');

    add_block('simulink/User-Defined Functions/MATLAB Function', pCore, ...
        'Position', [110, 52, 235, 88]);
    rt = sfroot;
    chart = find(rt, '-isa', 'Stateflow.EMChart', 'Path', pCore);
    assert(numel(chart) == 1, 'air:M0A:ChartNotFound', ...
        'Cannot locate the MATLAB Function chart at %s.', pCore);
    chart.Script = [ ...
        'function P_est = fcn(pwm_in)' newline ...
        '% Estimated total shaft power proxy of all eight rotors, in W.' newline ...
        '% UNCALIBRATED ESTIMATE (source flag 0). Mirrors the plant chart:' newline ...
        '% omega = (pwm-1000) rad/s in [0,1000]; Q_i = C_M*omega_i^2 N*m;' newline ...
        '% P_i = Q_i*omega_i = C_M*omega_i^3. C_M identical to plant.' newline ...
        'pwm_min = 1000.0; pwm_max = 2000.0; omega_max = 1000.0;' newline ...
        'C_M = 2.51e-7;' newline ...
        'pwm_clamped = max(min(double(pwm_in), pwm_max), pwm_min);' newline ...
        'omega = (pwm_clamped - pwm_min) / (pwm_max - pwm_min) * omega_max;' newline ...
        'P_est = sum(C_M * omega .^ 3);' newline ...
        'end'];

    add_block('simulink/Continuous/Integrator', eInteg, ...
        'Position', [290, 155, 320, 185], 'InitialCondition', '0');

    add_block('simulink/Sources/Constant', srcConst, ...
        'Position', [110, 200, 140, 230], 'Value', '0');

    add_block('built-in/Outport', [powerBlock '/P_est_W'], ...
        'Position', [400, 48, 430, 62], 'Port', '1');
    add_block('built-in/Outport', [powerBlock '/E_est_J'], ...
        'Position', [400, 108, 430, 122], 'Port', '2');
    add_block('built-in/Outport', [powerBlock '/power_source'], ...
        'Position', [400, 153, 430, 167], 'Port', '3');

    pwmInPorts = get_param([powerBlock '/pwm_us'], 'PortHandles');
    corePorts = get_param(pCore, 'PortHandles');
    integPorts = get_param(eInteg, 'PortHandles');
    srcPorts = get_param(srcConst, 'PortHandles');
    add_line(powerBlock, pwmInPorts.Outport(1), corePorts.Inport(1), 'autorouting', 'on');
    add_line(powerBlock, corePorts.Outport(1), integPorts.Inport(1), 'autorouting', 'on');
    add_line(powerBlock, corePorts.Outport(1), ...
        get_param([powerBlock '/P_est_W'], 'PortHandles').Inport(1), 'autorouting', 'on');
    add_line(powerBlock, integPorts.Outport(1), ...
        get_param([powerBlock '/E_est_J'], 'PortHandles').Inport(1), 'autorouting', 'on');
    add_line(powerBlock, srcPorts.Outport(1), ...
        get_param([powerBlock '/power_source'], 'PortHandles').Inport(1), 'autorouting', 'on');

    % --- root wiring ---
    add_block('simulink/Sinks/To Workspace', logP, ...
        'Position', [x0 + 360, y0 + 5, x0 + 530, y0 + 35], ...
        'VariableName', 'm0a_P_est_W', 'SaveFormat', 'Timeseries');
    add_block('simulink/Sinks/To Workspace', logE, ...
        'Position', [x0 + 360, y0 + 55, x0 + 530, y0 + 85], ...
        'VariableName', 'm0a_E_est_J', 'SaveFormat', 'Timeseries');
    add_block('simulink/Sinks/To Workspace', logSrc, ...
        'Position', [x0 + 360, y0 + 105, x0 + 530, y0 + 135], ...
        'VariableName', 'm0a_power_source', 'SaveFormat', 'Timeseries');

    powerPorts = get_param(powerBlock, 'PortHandles');
    add_line(model, acPorts.Outport(2), ...
        get_param(pwmConvert, 'PortHandles').Inport(1), 'autorouting', 'on');
    add_line(model, get_param(pwmConvert, 'PortHandles').Outport(1), ...
        powerPorts.Inport(1), 'autorouting', 'on');
    add_line(model, powerPorts.Outport(1), ...
        get_param(logP, 'PortHandles').Inport(1), 'autorouting', 'on');
    add_line(model, powerPorts.Outport(2), ...
        get_param(logE, 'PortHandles').Inport(1), 'autorouting', 'on');
    add_line(model, powerPorts.Outport(3), ...
        get_param(logSrc, 'PortHandles').Inport(1), 'autorouting', 'on');

    set_param(model, 'SimulationCommand', 'update');
    save_system(model);

    result = struct( ...
        'model', model, ...
        'pwmSource', "Attitude Control output 2 (root branch)", ...
        'powerBlock', string(powerBlock), ...
        'loggedVariables', ["m0a_P_est_W", "m0a_E_est_J", "m0a_power_source"], ...
        'powerDefinition', "C_M * sum(clip(pwm,1000,2000)-1000)^3, C_M=2.51e-7", ...
        'powerSourceFlag', "0 = estimated (uncalibrated)");
    fprintf('M0-A power measurement PASS: %s\n', model);
    fprintf('Logged variables: m0a_P_est_W, m0a_E_est_J, m0a_power_source\n');
catch err
    if strcmp(dirtyBefore, 'off') && bdIsLoaded(model)
        close_system(model, 0);
        load_system(fullfile(modelDir, [model '.slx']));
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
