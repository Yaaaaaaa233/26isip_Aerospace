%DIAG_M0C_LOGSHAPE inspect logged variable shapes at 2 s StopTime.
modelDir = fileparts(mfilename('fullpath'));
model = 'air_spare';
load_system(fullfile(modelDir, [model '.slx']));
set_param(model, 'StopTime', '2');
global M0C_ESC_PARAMS
M0C_ESC_PARAMS = struct('mode', 'fixed', 'center0', 9.0);
set_param([model '/M0B Speed Loop Enable'], 'Value', '1');
set_param([model '/M0A Optimizer Enable'], 'Value', '1');
out = sim(model);
w = out.who;
disp(w');
Pts = out.get('m0a_P_est_W');
fprintf('P_est_W: class %s\n', class(Pts));
if isa(Pts, 'timeseries')
    fprintf('  Data %s  Time %s\n', mat2str(size(Pts.Data)), ...
        mat2str(size(Pts.Time)));
end
Ets = out.get('m0a_E_est_J');
fprintf('E_est_J: Data %s  Time %s\n', mat2str(size(Ets.Data)), ...
    mat2str(size(Ets.Time)));
Mb = out.get('m0b_log_bus');
fprintf('m0b_log_bus: Data %s  Time %s\n', mat2str(size(Mb.Data)), ...
    mat2str(size(Mb.Time)));
A = out.get('m0a_log_bus');
fprintf('m0a_log_bus: Data %s  Time %s\n', mat2str(size(A.Data)), ...
    mat2str(size(A.Time)));
set_param([model '/M0B Speed Loop Enable'], 'Value', '0');
set_param([model '/M0A Optimizer Enable'], 'Value', '0');
close_system(model, 0);
