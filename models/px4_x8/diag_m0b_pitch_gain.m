function result = diag_m0b_pitch_gain()
%DIAG_M0B_PITCH_GAIN Calibrate pitch command sign/gain in memory (never saved).
%   Temporarily sets InputConditioning/Constant2 (pitch source, 1500 neutral)
%   to 1450 / 1550 and compares mean inertial velocity vs the unchanged run.

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(fullfile(modelDir, [model '.slx']));
end
cleanup = onCleanup(@() closeIfOpenedHere(model, wasLoaded)); %#ok<NASGU>
set_param(model, 'SimulationCommand', 'update');

sw = char(model + "/Attitude Control/InputConditioning/Sine Wave");
fprintf('Sine Wave: Amplitude=%s Bias=%s Frequency=%s Phase=%s SampleTime=%s\n', ...
    get_param(sw, 'Amplitude'), get_param(sw, 'Bias'), get_param(sw, 'Frequency'), ...
    get_param(sw, 'Phase'), get_param(sw, 'SampleTime'));
for cn = ["Constant2", "Constant3", "Constant4"]
    p = char(model + "/Attitude Control/InputConditioning/" + cn);
    fprintf('%s = %s\n', cn, get_param(p, 'Value'));
end

runs = {'base', 1500, 'bias_m10', 1450, 'bias_p10', 1550};
res = struct();
for r = 1:3
    name = runs{2*r - 1};
    val = runs{2*r};
    set_param(char(model + "/Attitude Control/InputConditioning/Constant2"), ...
        'Value', num2str(val));
    out = sim(model);
    veTs = out.get('m0a_Ve_inertial_mps');
    vt = veTs.Time(:);
    Ve = double(squeeze(veTs.Data));
    if size(Ve, 2) == numel(vt)
        Ve = Ve';
    end
    B = double(squeeze(out.get('m0a_log_bus').Data));
    if size(B, 2) ~= 35
        B = B';
    end
    tail = vt > 5;
    res.(name) = struct('Vex', mean(Ve(tail, 1)), 'Vey', mean(Ve(tail, 2)), ...
        'Vez', mean(Ve(tail, 3)), 'theta', mean(B(tail, 6)), ...
        'v', mean(B(tail, 1)));
    fprintf('%-8s Const2=%d  cmd_pre_gain=%+.2f  mean(t>5s): Ve_x %+7.3f  Ve_y %+7.3f  Ve_z %+7.3f  theta %+.4f  v %6.3f\n', ...
        name, val, (val - 1500)/500, res.(name).Vex, res.(name).Vey, ...
        res.(name).Vez, res.(name).theta, res.(name).v);
end

fprintf('\nsign check: dVe_x / d(theta) = (%.3f - %.3f)/(%.4f - %.4f) = %.2f\n', ...
    res.bias_p10.Vex, res.bias_m10.Vex, res.bias_p10.theta, res.bias_m10.theta, ...
    (res.bias_p10.Vex - res.bias_m10.Vex)/(res.bias_p10.theta - res.bias_m10.theta));
result = res;
end

function closeIfOpenedHere(model, wasLoaded)
if ~wasLoaded && bdIsLoaded(model)
    close_system(model, 0);
end
end
