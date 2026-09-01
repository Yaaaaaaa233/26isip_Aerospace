%DIAG_M1_PROBE Dump the P_est wiring around 'M0A Power Measurement' and
%   'M0A Constraint Flags' (read-only; used to place the M1 degradation
%   chain after the first run asserted a wrong assumed topology).

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
if bdIsLoaded(model)
    close_system(model, 0);
end
load_system(fullfile(modelDir, [model '.slx']));

pm = [model '/M0A Power Measurement'];
ph = get_param(pm, 'PortHandles');
fprintf('Power Measurement outputs: %d\n', numel(ph.Outport));
for k = 1:numel(ph.Outport)
    lines = find_system(model, 'FindAll', 'on', 'Type', 'line', ...
        'SrcPortHandle', ph.Outport(k));
    fprintf('out %d -> %d line(s)\n', k, numel(lines));
    for j = 1:numel(lines)
        dsts = get_param(lines(j), 'DstPortHandle');
        for m = 1:numel(dsts)
            fprintf('   -> %s  [out %d]\n', ...
                getfullname(get_param(dsts(m), 'Parent')), ...
                get_param(dsts(m), 'PortNumber'));
        end
    end
end

fl = [model '/M0A Constraint Flags'];
fh = get_param(fl, 'PortHandles');
fprintf('Constraint Flags inputs: %d\n', numel(fh.Inport));
for k = 1:numel(fh.Inport)
    l = get_param(fh.Inport(k), 'Line');
    if l == -1
        fprintf('flags in %d: DANGLING\n', k);
    else
        sp = get_param(l, 'SrcPortHandle');
        fprintf('flags in %d <- %s  [out %d]\n', k, ...
            getfullname(get_param(sp, 'Parent')), ...
            get_param(sp, 'PortNumber'));
    end
end

tw = find_system(model, 'LookUnderMasks', 'all', ...
    'BlockType', 'ToWorkspace');
fprintf('ToWorkspace blocks:\n');
for k = 1:numel(tw)
    fprintf('   %s (var %s)\n', tw{k}, ...
        get_param(tw{k}, 'VariableName'));
end

close_system(model, 0);
