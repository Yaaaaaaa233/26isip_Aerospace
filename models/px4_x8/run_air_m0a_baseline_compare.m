function result = run_air_m0a_baseline_compare(tolerance)
%RUN_AIR_M0A_BASELINE_COMPARE Acceptance: air_spare vs air over the baseline.
%   Runs the untouched read-only baseline air.slx and the M0-A development
%   model air_spare.slx over their configured 10 s scenario and compares the
%   shared physical signals sample by sample:
%     - pwm_cmd  : the eight-channel PWM command net (Attitude Control out 2)
%     - Ve       : inertial velocity from the 6DOF block output 4
%     - quat     : quaternion entering Attitude Control/quat2eul
%   Temporary signal logging is enabled in memory only; neither model is
%   modified on disk. Also re-validates the M0-A log bus consistency.
%
%   PASS criterion: max abs difference of every compared signal is within
%   TOLERANCE (default 1e-6), i.e. adding the observation layer did not
%   change the flight trajectory, attitude or actuator commands.

if nargin < 1
    tolerance = 1e-6;
end
comparedSignals = {'pwm_cmd', 'Ve', 'quat'};

% ---------- run baseline air.slx (read-only) ----------
wasLoadedAir = bdIsLoaded('air');
if ~wasLoadedAir
    load_system('air');
end
airDirtyBefore = get_param('air', 'Dirty');
cleanupAir = onCleanup(@() cleanupModel('air', ~wasLoadedAir, airDirtyBefore));

sAir = runLogged('air', comparedSignals);

% ---------- run development air_spare.slx (read-only) ----------
wasLoadedSpare = bdIsLoaded('air_spare');
if ~wasLoadedSpare
    load_system('air_spare');
end
spareDirtyBefore = get_param('air_spare', 'Dirty');
cleanupSpare = onCleanup(@() cleanupModel('air_spare', ~wasLoadedSpare, spareDirtyBefore));

sSpare = runLogged('air_spare', comparedSignals);

% ---------- compare ----------
rows = {};
maxOverall = 0;
pass = true;
for k = 1:numel(comparedSignals)
    va = sAir.(comparedSignals{k});
    vb = sSpare.(comparedSignals{k});
    sameTime = numel(va.Time) == numel(vb.Time) && max(abs(va.Time - vb.Time)) == 0;
    if sameTime
        d = max(abs(va.Data - vb.Data), [], 'all');
    else
        d = inf;
    end
    maxOverall = max(maxOverall, d);
    ok = sameTime && d <= tolerance;
    pass = pass && ok;
    rows(end+1, :) = {comparedSignals{k}, mat2str(size(va.Data)), d, ok}; %#ok<AGROW>
end

% ---------- M0-A log bus re-validation on the spare run ----------
bus = sSpare.output.get('m0a_log_bus');
B = squeeze(bus.Data)';
tBus = bus.Time(:);
c1 = size(B, 2) == 35;
c2 = numel(tBus) == 10001;
c3 = all(B(:, 4) == 0);
c4 = all(B(:, 35) == 0);
busOk = c1 && c2 && c3 && c4;
idx = tBus >= 0.005;
F = B(idx, 27:34);
flagsQuiet = all(max(F(:, [1 2 3 4 6 7 8]), [], 1) == 0);
relE = abs(B(end, 3) - mean(B(:, 2)) * 10) / (mean(B(:, 2)) * 10);
busOk = busOk && flagsQuiet && relE < 1e-3;
fprintf('bus checks: width35=%d n10001=%d src0=%d en0=%d flagsQuiet=%d relE=%.2e\n', ...
    c1, c2, c3, c4, flagsQuiet, relE);
rows(end+1, :) = {'m0a_log_bus(35x10001, flags, E)', mat2str(size(B)), relE, busOk}; %#ok<AGROW>
pass = pass && busOk;

% ---------- archive ----------
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outDir = fullfile('results', 'air_m0a_baseline_compare', stamp);
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
T = cell2table(rows, 'VariableNames', {'check', 'size', 'max_abs_diff', 'pass'});
writetable(T, fullfile(outDir, 'summary.csv'));
save(fullfile(outDir, 'comparison.mat'), 'T', 'tolerance', 'comparedSignals', ...
    'maxOverall', 'pass', 'sAir', 'sSpare');

result = struct('pass', pass, 'maxOverallDiff', maxOverall, ...
    'tolerance', tolerance, 'archiveDir', string(outDir));
if pass
    fprintf('M0-A BASELINE COMPARE PASS: max diff %.3e (tol %.1e)\n', maxOverall, tolerance);
else
    fprintf('M0-A BASELINE COMPARE FAIL: max diff %.3e (tol %.1e)\n', maxOverall, tolerance);
end
disp(T);
fprintf('Archive: %s\n', outDir);
end

function out = runLogged(model, names)
% Enable temporary port logging for the shared physical signals, then sim.
% The changes live in memory only; the caller closes without saving.
acOut2 = get_param([model '/Attitude Control'], 'PortHandles').Outport(2);
markPort(acOut2, names{1});
sixDof = find_system([model '/Subsystem'], 'RegExp', 'on', 'Name', '^6DOF.*');
assert(numel(sixDof) == 1, 'air:M0A:SixDofNotFound', 'expected one 6DOF block');
sfPorts = get_param(sixDof{1}, 'PortHandles');
markPort(sfPorts.Outport(4), names{2});
quatInLine = get_param( ...
    get_param([model '/Attitude Control/quat2eul'], 'PortHandles').Inport(1), 'Line');
markPort(get_param(quatInLine, 'SrcPortHandle'), names{3});
set_param(model, 'SignalLogging', 'on');
out.output = sim(model);
for k = 1:numel(names)
    out.(names{k}) = out.output.logsout.getElement(names{k}).Values;
end
end

function markPort(ph, name)
l = get_param(ph, 'Line');
set_param(l, 'Name', name);
set_param(ph, 'DataLogging', 'on');
set_param(ph, 'DataLoggingNameMode', 'Custom');
set_param(ph, 'DataLoggingName', name);
end

function cleanupModel(model, wasLoaded, dirtyBefore)
if bdIsLoaded(model)
    if ~wasLoaded || strcmp(dirtyBefore, 'off')
        close_system(model, 0);
    end
end
end
