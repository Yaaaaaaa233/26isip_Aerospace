%DIAG_M0C_FUNC_CHECK diagnose the installer functional check with the ESC
% installed: selector input-3 source, v_ref trace stats, status transitions
% and per-bit flag maxima (properly aligned).
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));
addpath(fullfile(wsRoot, '26isip_Aerospace', 'modules', 'ratio_esc'));
model = 'air_spare';
load_system(fullfile(modelDir, [model '.slx']));
set_param([model '/M0B Speed Loop Enable'], 'Value', '1');
set_param([model '/M0A Optimizer Enable'], 'Value', '1');
set_param(model, 'SimulationCommand', 'update');
selPh = get_param([model '/M0B Reference & Safety'], 'PortHandles');
l3 = get_param(selPh.Inport(3), 'Line');
if l3 == -1
    fprintf('selector in3: DISCONNECTED\n');
else
    fprintf('selector in3 from: %s\n', getfullname(get_param( ...
        get_param(l3, 'SrcPortHandle'), 'Parent')));
end
out = sim(model);
Mb = out.get('m0b_log_bus');
tb = Mb.Time;
A = double(squeeze(Mb.Data));
if size(A, 1) == 7
    A = A';
end
Fa = out.get('m0a_log_bus');
ta = Fa.Time;
B = double(squeeze(Fa.Data));
if size(B, 1) == 35
    B = B';
end
win = tb >= 6;
st = A(win, 4);
fprintf('status histogram [6,10]: ');
for s = 0:4
    fprintf('%d=%d ', s, sum(st == s));
end
fprintf('\n');
fprintf('v_ref [6,10]: mean %.3f  min %.3f  max %.3f\n', ...
    mean(A(win, 1)), min(A(win, 1)), max(A(win, 1)));
fprintf('bit maxima [6,10]: ');
fl = B(:, 27:34);
winA = ta >= 6 & ta < 10;
for b = 1:8
    fprintf('%d:%.0f ', b, max(fl(winA, b)));
end
fprintf('\n');
trans = find(diff(A(:, 4)) ~= 0);
fprintf('status transitions:\n');
for k = 1:numel(trans)
    fprintf('  t %.2f  %.0f -> %.0f\n', tb(trans(k)), A(trans(k), 4), ...
        A(trans(k) + 1, 4));
end
fprintf('flags at t<1.5 transitions (context): ');
fprintf('\n');
set_param([model '/M0B Speed Loop Enable'], 'Value', '0');
set_param([model '/M0A Optimizer Enable'], 'Value', '0');
close_system(model, 0);
