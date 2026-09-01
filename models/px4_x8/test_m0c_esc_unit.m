%TEST_M0C_ESC_UNIT validate the m0c_vref_esc wrapper before it touches the
% model (M0-C plan §4). Pure MATLAB loop, no Simulink: the plant here is
% P(v) = 251 + 40*(v - 8)^2 (analytic bowl, optimum 8 m/s) behind a
% first-order actuation v <- v_ref (tau = 1 s, module's exact
% discretization). Checks:
%   U1 band-entry hold   : v below the band -> v_ref == center0 exactly
%   U2 bowl convergence  : center reaches 8 +/- 0.25, settled last periods
%   U3 invalid semantics : hard flag set -> hold last ref, resume after
%   U4 fixed mode        : v_ref == center0 exactly, flags ignored
% The calibrated gain is pinned into M0C_SPEED_ESC.md section 2.4.

modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));
addpath(modelDir);
addpath(fullfile(wsRoot, '26isip_Aerospace', 'modules', 'ratio_esc'));
clear m0c_vref_esc;
global M0C_ESC_PARAMS
pass = true;

GAIN = 6e-3;  % calibrated by this test; see doc section 2.4

% ---- U1 + U2: esc mode on the analytic bowl, start below the band
M0C_ESC_PARAMS = struct('mode', 'esc', 'center0', 11.0, 'gain', GAIN);
[vr, vv] = runEpisode(@bowlP, 800, @(k) zeros(1, 8));
entry = find(vv >= 6.0, 1);
u1 = entry > 1 && all(vr(1:entry - 1) == 11.0);
u1b = all(vr >= 5.7 & vr <= 12.3);
m = arrayfun(@(j) mean(vr((j - 1) * 80 + 1:j * 80)), 1:10);
u2 = abs(m(end) - 8.0) <= 0.25 && range(m(end - 3:end)) <= 0.15;
convIdx = find(abs(m - 8.0) <= 0.25, 1);
convT = NaN;
if ~isempty(convIdx) && all(abs(m(convIdx:end) - 8.0) <= 0.25)
    convT = convIdx * 4.0;  % one 4 s period per mean window
end
fprintf('U1 band-entry hold %d (speed enters band at sample %d)\n', ...
    u1 && u1b, entry);
fprintf('U2 bowl convergence %d: period means [%.2f .. %.2f], settled ~%.1f s\n', ...
    u2, m(1), m(end), convT);
pass = pass && u1 && u1b && u2;

% ---- U3: invalid samples hold the last reference exactly, then resume
M0C_ESC_PARAMS = struct('mode', 'esc', 'center0', 11.0, 'gain', GAIN);
flag3 = @(k) [1 zeros(1, 7)] * double(k >= 300 && k < 460);
vr3 = runEpisode(@bowlP, 800, flag3);
holdVal = vr3(299);
u3 = all(vr3(300:459) == holdVal) && ~all(vr3(460:end) == holdVal);
fprintf(['U3 invalid hold %d: ref pinned to %.4f during flags, ' ...
    'resumes after\n'], u3, holdVal);
pass = pass && u3;

% ---- U4: fixed mode outputs center0 exactly, flags must not matter
M0C_ESC_PARAMS = struct('mode', 'fixed', 'center0', 7.0);
vr4 = runEpisode(@bowlP, 400, @(k) [zeros(1, 7) 1]);
u4 = all(vr4 == 7.0);
fprintf('U4 fixed mode %d (v_ref == 7.0 through 400 samples)\n', u4);
pass = pass && u4;

if pass
    fprintf('M0-C ESC UNIT PASS (gain %.1e calibrated)\n', GAIN);
else
    error('m0c:UnitTestFail', 'M0-C ESC UNIT FAIL - see log above');
end

function P = bowlP(v)
P = 251 + 40 * (v - 8.0) ^ 2;
end

function [vr, vv, tt] = runEpisode(Pfcn, n, flagFcn)
Ts = 0.05;
r = exp(-Ts / 1.0);
vr = zeros(1, n);
vv = zeros(1, n);
tt = (0:n - 1) * Ts;
v = 0.0;
for k = 1:n
    P = Pfcn(v);
    vr(k) = m0c_vref_esc([tt(k), v, P, 0, zeros(1, 6), flagFcn(k)]);
    vv(k) = v;
    v = r * v + (1 - r) * vr(k);
end
end
