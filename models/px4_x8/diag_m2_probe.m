%DIAG_M2_PROBE Read-only probe for the M2 eta allocator design (v4).
%   Traces the Attitude Control wrapper's internal Outport sources, the
%   8-ch PWM downstream graph (Demux -> 6DOF, PX4 PWM Output, M0A taps),
%   and M0A Constraint Flags input sources. Never saves the model.

function diag_m2_probe()
model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
if bdIsLoaded(model)
    close_system(model, 0);
end
load_system(fullfile(modelDir, [model '.slx']));

fprintf('=== Attitude Control wrapper internals ===\n');
acw = [model '/Attitude Control'];
ops = find_system(acw, 'SearchDepth', 1, 'BlockType', 'Outport');
for k = 1:numel(ops)
    fprintf('wrapper out %s = "%s"\n', get_param(ops{k}, 'Port'), ...
        get_param(ops{k}, 'Name'));
    reportIn(ops{k}, '   ');
end
ips = find_system(acw, 'SearchDepth', 1, 'BlockType', 'Inport');
for k = 1:numel(ips)
    fprintf('wrapper in %s = "%s"\n', get_param(ips{k}, 'Port'), ...
        get_param(ips{k}, 'Name'));
end

fprintf('\n=== AC outport consumers + Demux fanout ===\n');
ac = [model '/Attitude Control'];
ph = get_param(ac, 'PortHandles');
for k = 1:numel(ph.Outport)
    dumpFanout(ph.Outport(k), sprintf('out %d', k), '   ');
end

fprintf('\n=== M0A Constraint Flags inputs ===\n');
cf = [model '/M0A Constraint Flags'];
fh = get_param(cf, 'PortHandles');
for k = 1:numel(fh.Inport)
    dumpSrc(fh.Inport(k), sprintf('flags in %d', k));
end

fprintf('\n=== selected ZOH / consumer sources ===\n');
dumpSrcAll(get_param([model '/M0A PWM ZOH 1ms'], 'PortHandles'), 'M0A PWM ZOH 1ms');
dumpSrcAll(get_param([model '/M0C P ZOH'], 'PortHandles'), 'M0C P ZOH');
dumpSrcAll(get_param([model '/M0C v ZOH'], 'PortHandles'), 'M0C v ZOH');
dumpSrcAll(get_param([model '/M0C Flags ZOH'], 'PortHandles'), 'M0C Flags ZOH');
dumpSrcAll(get_param([model '/PX4 PWM Output'], 'PortHandles'), 'PX4 PWM Output');

close_system(model, 0);
end

function reportIn(blkPath, indent)
h = get_param(blkPath, 'PortHandles');
l = get_param(h.Inport(1), 'Line');
if l == -1
    fprintf('%s(unconnected)\n', indent);
    return;
end
sp = get_param(l, 'SrcPortHandle');
fprintf('%s<- %s [out %d]\n', indent, ...
    getfullname(get_param(sp, 'Parent')), get_param(sp, 'PortNumber'));
end

function dumpSrc(dstPort, lbl)
l = get_param(dstPort, 'Line');
if l == -1
    fprintf('%s: DANGLING\n', lbl);
    return;
end
sp = get_param(l, 'SrcPortHandle');
fprintf('%s <- %s [out %d]\n', lbl, ...
    getfullname(get_param(sp, 'Parent')), get_param(sp, 'PortNumber'));
end

function dumpSrcAll(ph, lbl)
for k = 1:numel(ph.Inport)
    dumpSrc(ph.Inport(k), sprintf('%s in %d', lbl, k));
end
end

function dumpFanout(srcPort, lbl, indent)
lines = find_system(bdroot(srcPort), 'FindAll', 'on', 'Type', 'line', ...
    'SrcPortHandle', srcPort);
fprintf('%s -> %d line(s)\n', lbl, numel(lines));
for j = 1:numel(lines)
    dsts = get_param(lines(j), 'DstPortHandle');
    for m = 1:numel(dsts)
        dstBlk = getfullname(get_param(dsts(m), 'Parent'));
        fprintf('%s-> %s  [in %d]\n', indent, dstBlk, ...
            get_param(dsts(m), 'PortNumber'));
        if strcmp(get_param(dstBlk, 'BlockType'), 'Demux')
            dph = get_param(dstBlk, 'PortHandles');
            for q = 1:numel(dph.Outport)
                dumpFanout(dph.Outport(q), sprintf('%sdemux out %d', ...
                    [indent '   '], q), [indent '   ' '   ']);
            end
        end
    end
end
end
