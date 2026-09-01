%ADD_AIR_M0C_ESC install the M0-C ESC optimizer interface into air_spare.
%   Replaces the 'M0B v Ref Optimizer' constant placeholder with the wrapped
%   Git-module ESC kernel (m0c_vref_esc -> ratioesc.esc_step) behind the
%   roadmap contract: inputs are only t, v, P_e, E_e, attitude(6),
%   constraint_flags(8); the single output is v_ref. The M0-B reference
%   selector / safety monitor keep full authority over the reference.
%
%   New blocks: 'M0C Clock' (Digital Clock 0.05 s), 'M0C ESC Input' (Mux,
%   18-wide = 1+1+1+6+1+8), per-input 0.05 s ZOHs, 'M0C v Ref ESC'
%   (Interpreted MATLAB Fcn). The old constant stays in place but
%   disconnected (manual comparison).
%
%   Environment rules honoured (docs/interfaces/M0C_SPEED_ESC.md §2.3,
%   M0B_SPEED_LOOP.md §4): per-branch line deletion only; pre-save
%   functional simulation; re-ensure of ALL chart feed lines after the
%   simulation (compilation severs lines silently, including unrelated
%   ones); post-save disk reload with link assertions; automatic restore
%   of the pre-install backup if any step fails.

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));
addpath(fullfile(wsRoot, 'modules', 'ratio_esc'));            % repo layout
addpath(fullfile(wsRoot, '26isip_Aerospace', 'modules', 'ratio_esc')); % frozen dev layout

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
cfgDir = fullfile(wsRoot, 'results', 'm0c_config', stamp);

wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(fullfile(modelDir, [model '.slx']));
end
dirtyBefore = get_param(model, 'Dirty');

try
    set_param(model, 'SimulationCommand', 'update');

    escBlock = [model '/M0C v Ref ESC'];
    escMux = [model '/M0C ESC Input'];
    escClk = [model '/M0C Clock'];
    if isBlock(escBlock) || isBlock(escMux) || isBlock(escClk) || ...
            isBlock([model '/M0C v ZOH'])
        error('air:M0C:AlreadyInstalled', ...
            'M0-C ESC blocks already exist. No changes were made.');
    end

    selBlock = [model '/M0B Reference & Safety'];
    ctrlBlock = [model '/M0B Speed Controller'];
    vRefOpt = [model '/M0B v Ref Optimizer'];
    powerBlock = [model '/M0A Power Measurement'];
    ov = [model '/M0B Flags Override'];
    loopEnable = [model '/M0B Speed Loop Enable'];
    optEnable = [model '/M0A Optimizer Enable'];
    assert(isBlock(selBlock) && isBlock(vRefOpt) && ...
        isBlock(powerBlock) && isBlock(ov), ...
        'air:M0C:LayerMissing', 'M0-A/M0-B layers missing.');

    % pre-install backup (restored by the catch block on any failure)
    if ~exist(cfgDir, 'dir')
        mkdir(cfgDir);
    end
    backupFile = fullfile(cfgDir, 'air_spare_pre_m0c.slx');
    close_system(model, 0);
    copyfile(fullfile(modelDir, [model '.slx']), backupFile);
    load_system(fullfile(modelDir, [model '.slx']));

    % ---------- 1. redirect: delete only the constant -> selector branch
    selPorts = get_param(selBlock, 'PortHandles');
    optSrc = get_param(vRefOpt, 'PortHandles').Outport(1);
    l = get_param(selPorts.Inport(3), 'Line');
    assert(l ~= -1, 'air:M0C:OptLineMissing', ...
        'optimizer constant is not wired to the selector.');
    assert(get_param(l, 'SrcPortHandle') == optSrc, ...
        'air:M0C:OptLineWrongSource', ...
        'selector input 3 is not fed by the optimizer constant.');
    delete_line(model, optSrc, selPorts.Inport(3));

    % ---------- 2. new blocks below the M0-B row ----------
    refPos = get_param(vRefOpt, 'Position');
    y0 = refPos(4) + 380;
    x0 = refPos(1);
    add_block('simulink/Sources/Digital Clock', escClk, ...
        'Position', [x0 - 320, y0, x0 - 290, y0 + 30], 'SampleTime', '0.05');
    add_block('simulink/Signal Routing/Mux', escMux, ...
        'Inputs', '6', 'Position', [x0 - 60, y0, x0 - 50, y0 + 200]);
    add_block('simulink/User-Defined Functions/Interpreted MATLAB Function', ...
        escBlock, 'Position', [x0 + 20, y0 + 80, x0 + 190, y0 + 140], ...
        'MATLABFcn', 'm0c_vref_esc', 'SampleTime', '0.05');

    muxPorts = get_param(escMux, 'PortHandles');
    escPorts = get_param(escBlock, 'PortHandles');
    clkPorts = get_param(escClk, 'PortHandles');
    % mux port order = adapter contract: [t; v; P_e; E_e; att(6); flags(8)]
    % every non-clock input passes an explicit 0.05 s ZOH so the mux and
    % the interpreted function see a single rate (auto rate transition is
    % not insertable on the logged M0A power chart output)
    zohDefs = { ...
        'M0C v ZOH', 'M0B v ZOH 1ms', 1, 2; ...
        'M0C P ZOH', 'M0A Power Measurement', 1, 3; ...
        'M0C E ZOH', 'M0A Power Measurement', 2, 4; ...
        'M0C Att ZOH', 'Attitude Control', 3, 5; ...
        'M0C Flags ZOH', 'M0B Flags Override', 1, 6};
    for k = 1:size(zohDefs, 1)
        add_block('simulink/Discrete/Zero-Order Hold', ...
            [model '/' zohDefs{k, 1}], ...
            'Position', [x0 - 240, y0 + (k - 1) * 45, x0 - 210, ...
            y0 + (k - 1) * 45 + 30], 'SampleTime', '0.05');
        add_line(model, get_param([model '/' zohDefs{k, 1}], ...
            'PortHandles').Outport(1), muxPorts.Inport(zohDefs{k, 4}), ...
            'autorouting', 'on');
    end
    add_line(model, clkPorts.Outport(1), muxPorts.Inport(1), ...
        'autorouting', 'on');
    for k = 1:size(zohDefs, 1)
        srcPh = get_param(sprintf('%s/%s', model, zohDefs{k, 2}), ...
            'PortHandles');
        zohIn = get_param([model '/' zohDefs{k, 1}], ...
            'PortHandles').Inport(1);
        add_line(model, srcPh.Outport(zohDefs{k, 3}), zohIn, ...
            'autorouting', 'on');
    end
    add_line(model, muxPorts.Outport(1), escPorts.Inport(1), ...
        'autorouting', 'on');
    add_line(model, escPorts.Outport(1), selPorts.Inport(3), ...
        'autorouting', 'on');

    % ---------- 3. compile, then ensure every line (new + M0-B charts) ---
    selIn = {'optimizer_enable', 'v_ref_manual', 'v_ref_optimizer', ...
        'flags', 'Ts'};
    ctlIn = {'enable', 'v', 've_x', 'v_ref', 'Ts', 'Kp', 'Ki'};  % v2 chart
    triples = { ...
        'M0C Clock', 1, 'M0C ESC Input', 1; ...
        'M0B v ZOH 1ms', 1, 'M0C v ZOH', 1; ...
        'M0A Power Measurement', 1, 'M0C P ZOH', 1; ...
        'M0A Power Measurement', 2, 'M0C E ZOH', 1; ...
        'Attitude Control', 3, 'M0C Att ZOH', 1; ...
        'M0B Flags Override', 1, 'M0C Flags ZOH', 1; ...
        'M0C v ZOH', 1, 'M0C ESC Input', 2; ...
        'M0C P ZOH', 1, 'M0C ESC Input', 3; ...
        'M0C E ZOH', 1, 'M0C ESC Input', 4; ...
        'M0C Att ZOH', 1, 'M0C ESC Input', 5; ...
        'M0C Flags ZOH', 1, 'M0C ESC Input', 6; ...
        'M0C ESC Input', 1, 'M0C v Ref ESC', 1; ...
        'M0C v Ref ESC', 1, 'M0B Reference & Safety', 3};
    ensureAll(model, selBlock, ctrlBlock, selIn, ctlIn, triples);

    % ---------- 4. functional check before saving ----------
    % default globals -> esc mode, center0 = 9: the loop must reach active
    % and the selector must track the ESC reference inside the band
    set_param(loopEnable, 'Value', '1');
    set_param(optEnable, 'Value', '1');
    checkOut = sim(model);
    Mb = checkOut.get('m0b_log_bus');
    tb = Mb.Time;
    A = double(squeeze(Mb.Data));
    if size(A, 1) == 7
        A = A';
    end
    win = tb >= 6;
    statusWin = A(win, 4);
    vrefWin = A(win, 1);
    fracActive = mean(statusWin == 2);
    % with a moving optimizer target the selector is marginally slew-
    % limiting at each ESC update, so status flickers 2<->1 by design
    % (M0-B's "active" test is exact equality against the target); the
    % engaged set {1,2} matches the M0-C stable-window definition. Status
    % 3/4 (frozen/fallback) must NOT appear in the nominal check.
    fracEngaged = mean(statusWin == 1 | statusWin == 2);
    % diagnostics first: status histogram, v_ref stats and every status
    % transition over the whole episode (shown whether asserts pass or not)
    fprintf('func-check status histogram [6,10]: ');
    for s = 0:4
        fprintf('%d=%d ', s, sum(statusWin == s));
    end
    fprintf('\n');
    fprintf('func-check v_ref [6,10]: mean %.3f min %.3f max %.3f\n', ...
        mean(vrefWin), min(vrefWin), max(vrefWin));
    trans = find(diff(A(:, 4)) ~= 0);
    for k = 1:numel(trans)
        fprintf('  t %.2f  status %.0f -> %.0f\n', tb(trans(k)), ...
            A(trans(k), 4), A(trans(k) + 1, 4));
    end
    assert(fracEngaged >= 0.95, 'air:M0C:NotActive', ...
        'selector not engaged on the ESC reference (frac %.2f).', fracEngaged);
    assert(~any(statusWin >= 3), 'air:M0C:SafetyTripped', ...
        'frozen/fallback appeared in the nominal functional check.');
    assert(all(abs(vrefWin - 9) <= 0.51), 'air:M0C:RefOffCenter', ...
        'v_ref left center0 +/- dither tolerance.');
    assert(all(vrefWin >= 5.9 & vrefWin <= 12.1), 'air:M0C:RefOutOfBand', ...
        'v_ref left the search band + tolerance.');
    vexTail = mean(A(tb >= 8, 6));
    assert(abs(vexTail) > 0.5, 'air:M0C:LoopBroken', ...
        'speed loop did not drive the vehicle (ve_x tail %.3f).', vexTail);
    fprintf(['functional check: active %.2f, v_ref [%.2f %.2f] ' ...
        '(center 9), ve_x tail %.3f\n'], fracActive, min(vrefWin), ...
        max(vrefWin), vexTail);
    set_param(loopEnable, 'Value', '0');
    set_param(optEnable, 'Value', '0');

    % ---------- 5. re-ensure everything the simulation may have severed,
    % then save ----------
    set_param(model, 'SimulationCommand', 'update');
    ensureAll(model, selBlock, ctrlBlock, selIn, ctlIn, triples);
    save_system(model);

    % ---------- 6. reload verification of the saved file ----------
    close_system(model, 0);
    load_system(fullfile(modelDir, [model '.slx']));

    L = { ...
        model, 'M0C Clock', 1, 'M0C ESC Input', 1; ...
        model, 'M0B v ZOH 1ms', 1, 'M0C v ZOH', 1; ...
        model, 'M0A Power Measurement', 1, 'M0C P ZOH', 1; ...
        model, 'M0A Power Measurement', 2, 'M0C E ZOH', 1; ...
        model, 'Attitude Control', 3, 'M0C Att ZOH', 1; ...
        model, 'M0B Flags Override', 1, 'M0C Flags ZOH', 1; ...
        model, 'M0C v ZOH', 1, 'M0C ESC Input', 2; ...
        model, 'M0C P ZOH', 1, 'M0C ESC Input', 3; ...
        model, 'M0C E ZOH', 1, 'M0C ESC Input', 4; ...
        model, 'M0C Att ZOH', 1, 'M0C ESC Input', 5; ...
        model, 'M0C Flags ZOH', 1, 'M0C ESC Input', 6; ...
        model, 'M0C ESC Input', 1, 'M0C v Ref ESC', 1; ...
        model, 'M0C v Ref ESC', 1, 'M0B Reference & Safety', 3; ...
        % M0-B safety chain must be untouched (review P1 regression set)
        model, 'M0A Constraint Flags', 1, 'M0B Flags Override', 1; ...
        model, 'M0B Flags Override', 1, 'M0A Log Bus', 8; ...
        model, 'M0B Flags Override', 1, 'M0B Reference & Safety', 4; ...
        model, 'M0B Flags Override', 1, 'M0A Log Constraint Flags', 1; ...
        model, 'M0A Optimizer Enable', 1, 'M0B Reference & Safety', 1; ...
        model, 'M0B v Ref Manual', 1, 'M0B Reference & Safety', 2; ...
        model, 'M0B Ts', 1, 'M0B Reference & Safety', 5; ...
        model, 'M0B Speed Loop Enable', 1, 'M0B Speed Controller', 1; ...
        model, 'M0B v ZOH 1ms', 1, 'M0B Speed Controller', 2; ...
        model, 'M0B Reference & Safety', 1, 'M0B Speed Controller', 4};
    for k = 1:size(L, 1)
        verifyLink(L{k, 1}, L{k, 2}, L{k, 3}, L{k, 4}, L{k, 5});
    end
    for k = 1:numel(selIn)
        verifyLink(selBlock, selIn{k}, 1, 'M0B Ref Safety Core', k);
    end
    for k = 1:numel(ctlIn)
        verifyLink(ctrlBlock, ctlIn{k}, 1, 'M0B Speed Core v2', k);
    end
    % the old constant must be disconnected now
    optOut = get_param(sprintf('%s/%s', model, 'M0B v Ref Optimizer'), ...
        'PortHandles').Outport(1);
    assert(get_param(optOut, 'Line') == -1, 'air:M0C:ConstantStillWired', ...
        'M0B v Ref Optimizer is still wired after reload.');
    close_system(model, 0);
    fprintf(['reload verification: %d critical links intact after save\n'], ...
        size(L, 1) + numel(selIn) + numel(ctlIn));

    % ---------- 7. config archive ----------
    cfgLines = { ...
        "model: air_spare", "stage: M0-C", ...
        "new: M0C Clock (0.05 s), M0C ESC Input (mux 18-wide), M0C v Ref ESC", ...
        "new: per-input 0.05 s ZOHs (single-rate mux; logged P_est chart", ...
        "     output cannot take auto rate transitions)", ...
        "esc_input_bus: [t; v; P_est; E_est; att(6); flags(8)]", ...
        "esc_output: v_ref -> M0B Reference & Safety input 3", ...
        "kernel: ratioesc.esc_reset/esc_step (modules/ratio_esc, Git module)", ...
        "params: band=[6 12] m/s, amp=0.3 m/s, f=0.25 Hz, hp=lp=0.6 rad/s", ...
        "        gain=6e-3 (unit-test calibrated), rateLimit=2.0 m/s^2", ...
        "modes: esc | fixed (paired baseline; same wiring, one global)", ...
        "defaults: speed_loop_enable=0 optimizer_enable=0"};
    writelines(string(cfgLines), fullfile(cfgDir, 'm0c_config.txt'));
    cfg = struct('stage', "M0-C", 'model', "air_spare", ...
        'backup', string(backupFile), 'notes', [cfgLines(6:11)]);
    save(fullfile(cfgDir, 'm0c_config.mat'), 'cfg');

    result = struct('model', model, ...
        'escBlock', string(escBlock), ...
        'backup', string(backupFile), ...
        'configDir', string(cfgDir));
    fprintf('M0-C ESC interface PASS: %s\n', model);
    fprintf('Optimizer placeholder replaced; constant kept disconnected.\n');
    fprintf('Config archived: %s\n', cfgDir);
catch err
    if strcmp(dirtyBefore, 'off')
        if bdIsLoaded(model)
            close_system(model, 0);
        end
        if exist(fullfile(cfgDir, 'air_spare_pre_m0c.slx'), 'file')
            copyfile(fullfile(cfgDir, 'air_spare_pre_m0c.slx'), ...
                fullfile(modelDir, [model '.slx']));
            fprintf('air_spare.slx restored from pre-install backup.\n');
        end
        load_system(fullfile(modelDir, [model '.slx']));
    end
    rethrow(err);
end

function ensureAll(model, selBlock, ctrlBlock, selIn, ctlIn, triples)
%ENSUREALL re-add every critical line until it survives a diagram update:
%   the M0-C root wiring plus the M0-B chart feed lines (compilation severs
%   lines silently in this environment, including unrelated chart inputs).
    for k = 1:size(triples, 1)
        ensureRootLine(model, triples{k, 1}, triples{k, 2}, ...
            triples{k, 3}, triples{k, 4});
    end
    for k = 1:numel(selIn)
        ensureLine(model, selBlock, selIn{k}, 'M0B Ref Safety Core', k);
    end
    for k = 1:numel(ctlIn)
        ensureLine(model, ctrlBlock, ctlIn{k}, 'M0B Speed Core v2', k);
    end
end

function ensureLine(rootModel, sysName, srcName, dstName, dstPort)
%ENSURELINE Add sysName/srcName -> sysName/dstName#dstPort until it survives
%   a diagram update (M0-B pattern, single-output sources).
    for attempt = 1:6
        dstPh = get_param(sprintf('%s/%s', sysName, dstName), 'PortHandles');
        l = get_param(dstPh.Inport(dstPort), 'Line');
        if l ~= -1
            srcParent = getfullname(get_param( ...
                get_param(l, 'SrcPortHandle'), 'Parent'));
            if strcmp(srcParent, sprintf('%s/%s', sysName, srcName))
                return;
            end
            delete_line(l);
        end
        srcPh = get_param(sprintf('%s/%s', sysName, srcName), 'PortHandles');
        add_line(sysName, srcPh.Outport(1), dstPh.Inport(dstPort), ...
            'autorouting', 'on');
        try
            set_param(rootModel, 'SimulationCommand', 'update');
        catch e
            if attempt == 6
                rethrow(e);
            end
        end
    end
    error('air:M0C:LineUnstable', ...
        'line %s/%s -> %s#%d did not survive the diagram update.', ...
        sysName, srcName, dstName, dstPort);
end

function ensureRootLine(model, srcName, srcPort, dstName, dstPort)
%ENSUREROOTLINE add model/srcName#srcPort -> model/dstName#dstPort until it
%   survives a diagram update (root-level, multi-output sources).
    for attempt = 1:6
        dstPh = get_param(sprintf('%s/%s', model, dstName), 'PortHandles');
        l = get_param(dstPh.Inport(dstPort), 'Line');
        if l ~= -1
            srcParent = getfullname(get_param( ...
                get_param(l, 'SrcPortHandle'), 'Parent'));
            if strcmp(srcParent, sprintf('%s/%s', model, srcName))
                return;
            end
            delete_line(l);
        end
        srcPh = get_param(sprintf('%s/%s', model, srcName), 'PortHandles');
        add_line(model, srcPh.Outport(srcPort), dstPh.Inport(dstPort), ...
            'autorouting', 'on');
        try
            set_param(model, 'SimulationCommand', 'update');
        catch e
            if attempt == 6
                rethrow(e);
            end
        end
    end
    error('air:M0C:LineUnstable', ...
        'line %s -> %s(in%d) did not survive the diagram update.', ...
        srcName, dstName, dstPort);
end

function verifyLink(sysPath, srcName, srcPort, dstName, dstPort)
%VERIFYLINK assert one saved link: source block, exact source port number
%   and destination (port-handle equality, codex reacceptance 4.3).
    dstPh = get_param(sprintf('%s/%s', sysPath, dstName), 'PortHandles');
    l = get_param(dstPh.Inport(dstPort), 'Line');
    assert(l ~= -1, 'air:M0C:LinkMissing', ...
        'link %s -> %s(in%d) missing after reload.', srcName, dstName, dstPort);
    sp = get_param(l, 'SrcPortHandle');
    srcParent = getfullname(get_param(sp, 'Parent'));
    assert(strcmp(srcParent, sprintf('%s/%s', sysPath, srcName)), ...
        'air:M0C:LinkWrongSource', ...
        'link into %s(in%d) comes from %s, expected %s.', ...
        dstName, dstPort, srcParent, srcName);
    srcPh = get_param(sprintf('%s/%s', sysPath, srcName), 'PortHandles');
    assert(numel(srcPh.Outport) >= srcPort, 'air:M0C:LinkSrcPort', ...
        '%s has fewer than %d outputs.', srcName, srcPort);
    assert(sp == srcPh.Outport(srcPort), 'air:M0C:LinkWrongPort', ...
        'link into %s(in%d) uses %s output %d, expected output %d.', ...
        dstName, dstPort, srcName, find(srcPh.Outport == sp), srcPort);
end

function tf = isBlock(path)
try
    get_param(path, 'Handle');
    tf = true;
catch
    tf = false;
end
end
