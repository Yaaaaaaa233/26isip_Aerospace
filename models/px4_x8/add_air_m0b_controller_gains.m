function result = add_air_m0b_controller_gains()
%ADD_AIR_M0B_CONTROLLER_GAINS Expose the speed-loop Kp/Ki as root constants.
%   Rebuilds the M0-B speed controller chart with two extra scalar inputs so
%   gain tuning never touches the chart script again (chart script edits
%   silently sever the chart's lines on this installation). air_spare.slx
%   only; requires add_air_m0b_speed_loop to have run.

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));
wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(fullfile(modelDir, [model '.slx']));
end
dirtyBefore = get_param(model, 'Dirty');

try
    set_param(model, 'SimulationCommand', 'update');

    ctrlBlock = [model '/M0B Speed Controller'];
    coreOld = [ctrlBlock '/M0B Speed Core'];
    coreNew = [ctrlBlock '/M0B Speed Core v2'];
    kpConst = [model '/M0B Kp'];
    kiConst = [model '/M0B Ki'];
    assert(~isBlock(coreNew) && ~isBlock(kpConst) && ~isBlock(kiConst), ...
        'air:M0B:AlreadyInstalled', ...
        'controller gain inputs already exist. No changes were made.');
    assert(isBlock(coreOld), 'air:M0B:SpeedCoreMissing', ...
        'M0B Speed Core not found; run add_air_m0b_speed_loop first.');

    % --- new chart with Kp/Ki inputs ---
    add_block('simulink/User-Defined Functions/MATLAB Function', coreNew, ...
        'Position', [140, 170, 310, 240]);
    rt = sfroot;
    nchart = find(rt, '-isa', 'Stateflow.EMChart', 'Path', coreNew);
    assert(numel(nchart) == 1, 'air:M0B:ChartNotFound', 'new core chart missing');
    nchart.Script = [ ...
        'function [pitch_cmd, v_err] = fcn(enable, v, ve_x, v_ref, Ts, Kp, Ki)' newline ...
        '% M0-B speed outer loop: v_ref -> PI -> normalized pitch command' newline ...
        '% in the chart_23 domain (theta_des = 0.523 * pitch_cmd).' newline ...
        '% Sign convention (measured): positive pitch_cmd tilts thrust' newline ...
        '% against +Ve_x, i.e. decelerates +x flight and accelerates -x.' newline ...
        '% Kp (per m/s) and Ki (per m/s/s) are runtime inputs.' newline ...
        'persistent integ prev_cmd;' newline ...
        'if isempty(integ)' newline ...
        '    integ = 0.0; prev_cmd = 0.0;' newline ...
        'end' newline ...
        'integ_max = 0.15; % integral clamp, normalized units' newline ...
        'cmd_max = 0.40;   % |theta_des| <= 0.209 rad' newline ...
        'rate_max = 0.25;  % normalized units per s (soft engage)' newline ...
        'if enable < 0.5' newline ...
        '    integ = 0.0; prev_cmd = 0.0;' newline ...
        '    pitch_cmd = 0.0; v_err = 0.0;' newline ...
        '    return;' newline ...
        'end' newline ...
        'e = v_ref - v;                   % > 0: below reference' newline ...
        'if e < -0.10 && ve_x < 0.0' newline ...
        '    s2 = -1.0; % too fast while flying -x: oppose the -x motion' newline ...
        'else' newline ...
        '    s2 = 1.0;  % default: nose-down accelerates +x (bootstrap)' newline ...
        'end' newline ...
        'e_eff = e * s2;' newline ...
        'integ = min(integ_max, max(-integ_max, integ + e_eff * Ts));' newline ...
        'cmd_raw = -(Kp * e_eff + Ki * integ);' newline ...
        'cmd = min(cmd_max, max(-cmd_max, cmd_raw));' newline ...
        'step_max = rate_max * Ts;' newline ...
        'cmd = min(prev_cmd + step_max, max(prev_cmd - step_max, cmd));' newline ...
        'prev_cmd = cmd;' newline ...
        'pitch_cmd = cmd;' newline ...
        'v_err = e;' newline ...
        'end'];
    set_param(coreNew, 'SystemSampleTime', '0.001');

    % --- new controller inports + rewiring ---
    add_block('built-in/Inport', [ctrlBlock '/Kp'], ...
        'Position', [30, 183, 60, 197], 'Port', '6');
    add_block('built-in/Inport', [ctrlBlock '/Ki'], ...
        'Position', [30, 228, 60, 242], 'Port', '7');
    ctlIns = {'enable', 'v', 've_x', 'v_ref', 'Ts', 'Kp', 'Ki'};
    delete_block(coreOld);
    stale = get_param(get_param([ctrlBlock '/pitch_cmd'], ...
        'PortHandles').Inport(1), 'Line');
    if stale ~= -1
        delete_line(stale);
    end
    stale = get_param(get_param([ctrlBlock '/v_err'], ...
        'PortHandles').Inport(1), 'Line');
    if stale ~= -1
        delete_line(stale);
    end
    for k = 1:numel(ctlIns)
        ensureLine(model, ctrlBlock, ctlIns{k}, 'M0B Speed Core v2', k);
    end
    ensureLine(model, ctrlBlock, 'M0B Speed Core v2', 'pitch_cmd', 1, 1);
    ensureLine(model, ctrlBlock, 'M0B Speed Core v2', 'v_err', 1, 2);

    % --- root gain constants ---
    refPos = get_param([model '/M0B Ts'], 'Position');
    add_block('simulink/Sources/Constant', kpConst, ...
        'Position', [refPos(3) + 60, refPos(2), refPos(3) + 90, refPos(4)], ...
        'Value', '0.12');
    add_block('simulink/Sources/Constant', kiConst, ...
        'Position', [refPos(3) + 140, refPos(2), refPos(3) + 170, refPos(4)], ...
        'Value', '0.04');
    ctlPorts = get_param(ctrlBlock, 'PortHandles');
    add_line(model, get_param(kpConst, 'PortHandles').Outport(1), ...
        ctlPorts.Inport(6), 'autorouting', 'on');
    add_line(model, get_param(kiConst, 'PortHandles').Outport(1), ...
        ctlPorts.Inport(7), 'autorouting', 'on');

    set_param(model, 'SimulationCommand', 'update');

    % --- functional verification before saving ---
    set_param([model '/M0B Speed Loop Enable'], 'Value', '1');
    checkOut = sim(model);
    Mb = double(squeeze(checkOut.get('m0b_log_bus').Data));
    if size(Mb, 1) == 7
        Mb = Mb';
    end
    vexTail = mean(Mb(6001:10001, 6));
    assert(abs(vexTail) > 0.5, 'air:M0B:InjectionBroken', ...
        'pitch command did not reach the vehicle (ve_x tail %.3f).', vexTail);
    fprintf('functional check: ve_x tail mean %.3f m/s\n', vexTail);
    set_param([model '/M0B Speed Loop Enable'], 'Value', '0');
    set_param(model, 'SimulationCommand', 'update');
    save_system(model);

    outDir = fullfile(wsRoot, 'results', 'm0b_config', ...
        char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end
    cfg = struct('model', "air_spare", 'stage', "M0-B gain inputs", ...
        'Kp_default', 0.12, 'Ki_default', 0.04, ...
        'note', "Kp/Ki are root constants wired into the controller chart");
    save(fullfile(outDir, 'm0b_gains.mat'), 'cfg');

    result = struct('model', model, 'kpConst', string(kpConst), ...
        'kiConst', string(kiConst));
    fprintf('M0-B controller gain inputs PASS: Kp=0.12 Ki=0.04\n');
catch err
    if strcmp(dirtyBefore, 'off') && bdIsLoaded(model)
        close_system(model, 0);
        load_system(fullfile(modelDir, [model '.slx']));
    end
    rethrow(err);
end
end

function ensureLine(rootModel, sysName, srcName, dstName, dstPort, srcPort)
if nargin < 6
    srcPort = 1;
end
for attempt = 1:6
    dstPh = get_param(sprintf('%s/%s', sysName, dstName), 'PortHandles');
    l = get_param(dstPh.Inport(dstPort), 'Line');
    if l ~= -1
        srcParent = getfullname(get_param(get_param(l, 'SrcPortHandle'), 'Parent'));
        if strcmp(srcParent, sprintf('%s/%s', sysName, srcName))
            return;
        end
        delete_line(l);
    end
    srcPh = get_param(sprintf('%s/%s', sysName, srcName), 'PortHandles');
    add_line(sysName, srcPh.Outport(srcPort), dstPh.Inport(dstPort), ...
        'autorouting', 'on');
    try
        set_param(rootModel, 'SimulationCommand', 'update');
    catch e
        if attempt == 6
            rethrow(e);
        end
    end
end
error('air:M0B:LineUnstable', 'line %s/%s -> %s#%d unstable', ...
    sysName, srcName, dstName, dstPort);
end

function tf = isBlock(path)
try
    get_param(path, 'Handle');
    tf = true;
catch
    tf = false;
end
end
