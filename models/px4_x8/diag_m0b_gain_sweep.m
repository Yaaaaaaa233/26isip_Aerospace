function result = diag_m0b_gain_sweep()
%DIAG_M0B_GAIN_SWEEP In-memory Kp/Ki sweep on the fixed 9 m/s scenario.

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
combos = [0.12 0.04; 0.20 0.04; 0.30 0.08; 0.12 0.10];
best = struct('meanErr', inf);
fprintf('%-16s %10s %10s %10s %10s %10s\n', 'Kp/Ki', 'mean|err|', ...
    'max|err|', 'thetaMax', 'vMax', 'vMin');
for r = 1:size(combos, 1)
    load_system(fullfile(modelDir, [model '.slx']));
    set_param(model, 'SimulationCommand', 'update');
    set_param([model '/M0B Speed Loop Enable'], 'Value', '1');
    set_param([model '/M0B v Ref Manual'], 'Value', '9');
    set_param([model '/M0B Kp'], 'Value', num2str(combos(r, 1)));
    set_param([model '/M0B Ki'], 'Value', num2str(combos(r, 2)));
    out = sim(model);
    Mb = double(squeeze(out.get('m0b_log_bus').Data));
    if size(Mb, 1) == 7
        Mb = Mb';
    end
    A = double(squeeze(out.get('m0a_log_bus').Data));
    if size(A, 2) ~= 35
        A = A';
    end
    w = Mb(:, 1) * 0; %#ok<NASGU>
    tb = out.get('m0b_log_bus').Time(:);
    win = tb >= 6 & tb <= 10;
    errAbs = abs(Mb(win, 7) - Mb(win, 1));
    mE = mean(errAbs);
    xE = max(errAbs);
    thM = max(abs(A(:, 6)));
    vMx = max(Mb(win, 7));
    vMn = min(Mb(win, 7));
    fprintf('%-16s %10.3f %10.3f %10.3f %10.2f %10.2f\n', ...
        sprintf('%.2f/%.2f', combos(r, 1), combos(r, 2)), mE, xE, thM, vMx, vMn);
    if mE < best.meanErr
        best = struct('meanErr', mE, 'maxErr', xE, 'Kp', combos(r, 1), ...
            'Ki', combos(r, 2), 'thetaMax', thM);
    end
    close_system(model, 0);
end
fprintf('BEST: Kp=%.2f Ki=%.2f mean|err|=%.3f max|err|=%.3f thetaMax=%.3f\n', ...
    best.Kp, best.Ki, best.meanErr, best.maxErr, best.thetaMax);
result = best;
end
