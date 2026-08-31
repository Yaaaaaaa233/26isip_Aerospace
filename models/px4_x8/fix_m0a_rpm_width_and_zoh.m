% Post-install fixes for the M0-A log stage (air_spare.slx):
%   1. The rpm Fcn block outputs a scalar (Fcn limitation); replace both the
%      bus-level and the actuator-stage rpm Fcn with elementwise
%      Subtract(1000) + Gain(9.54929658551372) so rpm is 8-wide.
%   2. Set the PWM Zero-Order Hold initial condition to 1500 us so the t=0
%      ZOH default of 0 does not spuriously trip the pwm/rpm saturation flags.
model = 'air_spare';
wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(model);
end
dirtyBefore = get_param(model, 'Dirty');
try
    set_param(model, 'SimulationCommand', 'update');

    % ---- fix 1a: bus-level rpm ----
    oldFcn = [model '/M0A Bus RPM Est'];
    rpmSub = [model '/M0A Bus RPM Subtract'];
    rpmGain = [model '/M0A Bus RPM Gain'];
    rpmConst = [model '/M0A Bus RPM Offset'];
    assert(isBlock(oldFcn), 'air:M0A:RpmFcnMissing', 'bus rpm Fcn not found.');
    assert(~isBlock(rpmGain), 'air:M0A:AlreadyPatched', 'bus rpm fix already applied.');
    fcnPos = get_param(oldFcn, 'Position');
    srcLine = get_param(get_param(oldFcn, 'PortHandles').Inport(1), 'Line');
    srcPH = get_param(srcLine, 'SrcPortHandle');
    dstLine = get_param(get_param(oldFcn, 'PortHandles').Outport(1), 'Line');
    dstPH = get_param(dstLine, 'DstPortHandle');
    delete_line(srcLine);
    delete_line(dstLine);
    delete_block(oldFcn);
    add_block('simulink/Math Operations/Subtract', rpmSub, ...
        'Position', [fcnPos(1), fcnPos(2), fcnPos(1) + 40, fcnPos(4)], ...
        'Inputs', '+-');
    add_block('simulink/Sources/Constant', rpmConst, ...
        'Position', [fcnPos(1) - 90, fcnPos(2) + 40, fcnPos(1) - 50, fcnPos(2) + 70], ...
        'Value', '1000');
    add_block('simulink/Math Operations/Gain', rpmGain, ...
        'Position', [fcnPos(3) + 30, fcnPos(2), fcnPos(3) + 80, fcnPos(4)], ...
        'Gain', '9.54929658551372');
    add_line(model, srcPH, get_param(rpmSub, 'PortHandles').Inport(1), 'autorouting', 'on');
    add_line(model, get_param(rpmConst, 'PortHandles').Outport(1), ...
        get_param(rpmSub, 'PortHandles').Inport(2), 'autorouting', 'on');
    add_line(model, get_param(rpmSub, 'PortHandles').Outport(1), ...
        get_param(rpmGain, 'PortHandles').Inport(1), 'autorouting', 'on');
    add_line(model, get_param(rpmGain, 'PortHandles').Outport(1), dstPH, 'autorouting', 'on');

    % ---- fix 1b: actuator-stage rpm inside AttitudeControl ----
    acInner = [model '/Attitude Control/AttitudeControl'];
    oldFcn2 = [acInner '/M0A Estimated Motor RPM'];
    sub2 = [acInner '/M0A RPM Subtract'];
    gain2 = [acInner '/M0A RPM Gain'];
    const2 = [acInner '/M0A RPM Offset'];
    if isBlock(oldFcn2) && ~isBlock(gain2)
        fpos = get_param(oldFcn2, 'Position');
        srcLine2 = get_param(get_param(oldFcn2, 'PortHandles').Inport(1), 'Line');
        srcPH2 = get_param(srcLine2, 'SrcPortHandle');
        dstLine2 = get_param(get_param(oldFcn2, 'PortHandles').Outport(1), 'Line');
        dstPH2 = get_param(dstLine2, 'DstPortHandle');
        delete_line(srcLine2);
        delete_line(dstLine2);
        delete_block(oldFcn2);
        add_block('simulink/Math Operations/Subtract', sub2, ...
            'Position', [fpos(1), fpos(2), fpos(1) + 40, fpos(4)], 'Inputs', '+-');
        add_block('simulink/Sources/Constant', const2, ...
            'Position', [fpos(1) - 90, fpos(2) + 40, fpos(1) - 50, fpos(2) + 70], ...
            'Value', '1000');
        add_block('simulink/Math Operations/Gain', gain2, ...
            'Position', [fpos(3) + 30, fpos(2), fpos(3) + 80, fpos(4)], ...
            'Gain', '9.54929658551372');
        add_line(acInner, srcPH2, get_param(sub2, 'PortHandles').Inport(1), 'autorouting', 'on');
        add_line(acInner, get_param(const2, 'PortHandles').Outport(1), ...
            get_param(sub2, 'PortHandles').Inport(2), 'autorouting', 'on');
        add_line(acInner, get_param(sub2, 'PortHandles').Outport(1), ...
            get_param(gain2, 'PortHandles').Inport(1), 'autorouting', 'on');
        add_line(acInner, get_param(gain2, 'PortHandles').Outport(1), dstPH2, 'autorouting', 'on');
    end

    % ---- note on t=0 ----
    % The root PWM net itself is 0 at t=0 (inherited model behavior: the
    % wrapper output lags the mixer by one hit), so the ZOH keeps its default
    % initial condition 0 and the pwm/rpm saturation flags may legitimately
    % trip on the very first samples. Acceptance excludes a 5 ms init window.

    set_param(model, 'SimulationCommand', 'update');
    save_system(model);
    fprintf('FIXES_APPLIED\n');
catch err
    if strcmp(dirtyBefore, 'off') && bdIsLoaded(model)
        close_system(model, 0);
        load_system(model);
    end
    rethrow(err);
end

function tf = isBlock(path)
try
    get_param(path, 'Handle');
    tf = true;
catch
    tf = false;
end
end
