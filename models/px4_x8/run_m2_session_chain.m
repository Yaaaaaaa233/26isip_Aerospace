%RUN_M2_SESSION_CHAIN Full M2 acceptance chain in ONE MATLAB session, in
%   AGENTS.md order, with NO manual state clearing -- whatever a previous
%   trials run left behind is normalized here (round-2 reacceptance R2-F1),
%   and the nine-scenario result is hard-asserted at the end (R2-F2).
%   Introduced by the 2026-09-01 reacceptance fix round (Z5), hardened in
%   the round-2 fix (docs/evidence/M2_REACCEPT_ROUND2_FIX_20260901.md).
%   Runs:
%     1. test_m2_eta_esc_unit          (self-isolating unit tests)
%     2. run_air_m0a_baseline_compare  (bypass diff must be 0)
%     3. run_air_m0b_safety_injection  (4/4)
%     4. run_air_m2_trials             (120 s settled-window protocol)

fprintf('===== M2 SESSION CHAIN BEGIN =====\n');

% R2-F1: normalize the M2 session state to the safe identity BEFORE any
% entry runs, regardless of what earlier M2 runs left in this session; the
% caller's entry state is restored on exit (success or error).
global M2_ETA_PARAMS M2_ETA_APPLIED
chainSavedParams = [];
chainSavedApplied = [];
if ~isempty(M2_ETA_PARAMS), chainSavedParams = M2_ETA_PARAMS; end
if ~isempty(M2_ETA_APPLIED) && isfinite(M2_ETA_APPLIED)
    chainSavedApplied = M2_ETA_APPLIED;
end
chainCleanup = onCleanup(@() m2chain_restore_globals( ...
    chainSavedParams, chainSavedApplied)); %#ok<NASGU>
M2_ETA_PARAMS = struct('mode', 'fixed', 'center0', 1.0);
M2_ETA_APPLIED = 1.0;
clear('m2_eta_esc');   % wipe adapter persistent state from earlier runs

test_m2_eta_esc_unit;

r1 = run_air_m0a_baseline_compare();
assert(r1.pass, 'air:M2Session:CompareFailed', ...
    'bypass compare failed (max diff %.3g)', r1.maxOverallDiff);
fprintf('CHAIN: compare PASS, max diff %.3g\n', r1.maxOverallDiff);

r2 = run_air_m0b_safety_injection();
assert(r2.pass, 'air:M2Session:InjectionFailed');
fprintf('CHAIN: safety injection PASS\n');

run_air_m2_trials;
% R2-F2: run_air_m2_trials reports failures only through result.pass --
% without this assert the chain could print END and exit successfully on a
% failed trials run (automation false-green).
assert(result.pass, 'air:M2Session:TrialsFailed', ...
    'M2 trials failed, archive %s', result.archiveDir);
fprintf('CHAIN: M2 trials PASS, archive %s\n', result.archiveDir);

fprintf('===== M2 SESSION CHAIN END =====\n');

function m2chain_restore_globals(savedParams, savedApplied)
%M2CHAIN_RESTORE_GLOBALS R2-F1: put M2 globals back to the caller's
%   entry-time values (empty stays empty -- the safe identity default),
%   on success and on any error/assert path.
global M2_ETA_PARAMS M2_ETA_APPLIED
if isempty(savedParams)
    M2_ETA_PARAMS = [];
else
    M2_ETA_PARAMS = savedParams;
end
if isempty(savedApplied)
    M2_ETA_APPLIED = [];
else
    M2_ETA_APPLIED = savedApplied;
end
end
