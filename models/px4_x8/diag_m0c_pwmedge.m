%DIAG_M0C_PWMEDGE offline analysis of the archived pwm_edge injection log.
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));
d = dir(fullfile(wsRoot, 'results', 'air_m0b_safety_injection', ...
    '20260901_111419', 'pwm_edge.mat'));
assert(~isempty(d), 'no archived pwm_edge.mat');
S = load(fullfile(d.folder, d.name));
Mb = S.Mb; tb = S.tb; status = Mb(:, 4); vref = Mb(:, 1);
fprintf('m0b bus width %d\n', size(Mb, 2));
fprintf('--- episode trace: t vref status ve_x(Mb6) v(Mb7) ---\n');
for t = [0 0.5 1 1.5 2 2.5 3 3.5 4 4.2 4.4 4.6 4.8 5 5.2 5.4 5.6 5.8 6]
    k = find(tb >= t, 1);
    fprintf('t %.1f  vref %9.5f  st %.0f  vex %7.3f  v %7.3f\n', ...
        tb(k), vref(k), status(k), Mb(k, 6), Mb(k, 7));
end
fprintf('vref first leaves 9+/-0.001: ');
k = find(abs(vref - 9) > 0.001, 1);
if isempty(k)
    fprintf('never\n');
else
    fprintf('t %.3f (vref %.5f)\n', tb(k), vref(k));
end
fb = status == 4;
fprintf('max vref in fallback: %.4f\n', max(vref(fb)));
