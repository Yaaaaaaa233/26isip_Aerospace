function result = diag_m0b_pitch_sign()
%DIAG_M0B_PITCH_SIGN Determine set_pitch sign convention and DC gain.
%   Runs air_spare in-memory (never saved) with temporary DataLogging on the
%   set_pitch command (Demux3 out 2) plus attitude/speed from the M0A log bus,
%   then reports correlation between theta, dv/dt and the achieved speed.

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));
wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(fullfile(modelDir, [model '.slx']));
end
cleanup = onCleanup(@() closeIfOpenedHere(model, wasLoaded)); %#ok<NASGU>

set_param(model, 'SimulationCommand', 'update');

% Temporary logging: branch value of Demux3 out2 (set_pitch) without rewiring.
demux3Ports = get_param(char(model + "/Demux3"), 'PortHandles');
set_param(demux3Ports.Outport(2), 'DataLogging', 'on', ...
    'DataLoggingNameMode', 'Custom', 'DataLoggingName', 'm0b_set_pitch_cmd');

out = sim(model);

sp = out.logsout.get('m0b_set_pitch_cmd');
spV = squeeze(sp.Values.Data);
t = squeeze(sp.Values.Time);
bus = out.get('m0a_log_bus');          % To Workspace variable, direct access
B = squeeze(bus.Data)';                % [N x 35]
bt = bus.Time(:);

% theta from bus col 6; v from bus col 1, resampled onto t
theta = interp1(bt, B(:, 6), t);
v = interp1(bt, B(:, 1), t);
dvdt = [0; diff(v) ./ diff(t)];

tail = t > 5;  % post-transient window
fprintf('== baseline (air_spare, no structural change) ==\n');
fprintf('set_pitch cmd : mean %.4f  range [%.4f, %.4f]  tail-mean %.4f\n', ...
    mean(spV), min(spV), max(spV), mean(spV(tail)));
fprintf('theta rad     : mean %.4f  range [%.4f, %.4f]  tail-mean %.4f (deg %.2f)\n', ...
    mean(theta), min(theta), max(theta), mean(theta(tail)), rad2deg(mean(theta(tail))));
fprintf('v m/s         : mean %.4f  range [%.4f, %.4f]  tail-mean %.4f\n', ...
    mean(v), min(v), max(v), mean(v(tail)));
cc = corrcoef(theta(tail), v(tail));
fprintf('corr(theta, v) over tail: %.3f\n', cc(1, 2));
win = t > 0.5 & t < 4.0;
cc2 = corrcoef(theta(win), dvdt(win));
fprintf('corr(theta, dv/dt) over [0.5,4]s: %.3f\n', cc2(1, 2));

% save full diagnostic
outDir = fullfile(wsRoot, 'results', 'm0b_diagnostics', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
if ~isfolder(outDir)
    mkdir(outDir);
end
save(fullfile(outDir, 'pitch_sign_diag.mat'), 't', 'spV', 'theta', 'v', 'dvdt', 'tail');
result = struct('t', t, 'setPitch', spV, 'theta', theta, 'v', v, 'outDir', string(outDir));
fprintf('Archived: %s\n', outDir);
end

function closeIfOpenedHere(model, wasLoaded)
if ~wasLoaded && bdIsLoaded(model)
    close_system(model, 0);
end
end
