%DIAG_M0C_LOOPALIVE verify the speed loop actually tracks in a trial-like
% run (fixed mode center 7): mean |v - v_ref| in [8,10] s must be small.
modelDir = fileparts(mfilename('fullpath'));
model = 'air_spare';
global M0C_ESC_PARAMS
M0C_ESC_PARAMS = struct('mode', 'fixed', 'center0', 7.0);
load_system(fullfile(modelDir, [model '.slx']));
set_param(model, 'StopTime', '10');
set_param([model '/M0B Speed Loop Enable'], 'Value', '1');
set_param([model '/M0A Optimizer Enable'], 'Value', '1');
set_param([model '/Attitude Control/InputConditioning/Sine Wave'], ...
    'Amplitude', '0');
out = sim(model);
Mb = double(squeeze(out.get('m0b_log_bus').Data));
if size(Mb, 2) ~= 7
    Mb = Mb';
end
tb = out.get('m0b_log_bus').Time(:);
win = tb >= 8;
fprintf('mean |v - v_ref| in [8,10]: %.4f m/s (v %.3f, v_ref %.3f)\n', ...
    mean(abs(Mb(win, 7) - Mb(win, 1))), mean(Mb(win, 7)), ...
    mean(Mb(win, 1)));
% log shapes for the interp1 fix
Pts = out.get('m0a_P_est_W');
Ets = out.get('m0a_E_est_J');
fprintf('P time %d  E time %d\n', numel(Pts.Time), numel(Ets.Time));
set_param([model '/M0B Speed Loop Enable'], 'Value', '0');
set_param([model '/M0A Optimizer Enable'], 'Value', '0');
close_system(model, 0);
