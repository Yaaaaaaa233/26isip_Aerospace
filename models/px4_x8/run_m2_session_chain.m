%RUN_M2_SESSION_CHAIN Full M2 acceptance chain in ONE MATLAB session, in
%   AGENTS.md order, with NO manual state clearing -- whatever a previous
%   trials run left behind is normalized here (round-2 reacceptance R2-F1),
%   and every stage including the nine-scenario result is hard-asserted
%   (R2-F2). Introduced by the 2026-09-01 reacceptance fix round (Z5),
%   hardened in the round-2 fix, and FUNCTIONALIZED in the round-3 fix:
%   as a function frame its onCleanup restore executes reliably on the
%   error path too (round-3 reacceptance R3-F1; see
%   docs/evidence/M2_REACCEPT_ROUND3_FIX_20260902.md and
%   docs/ACCEPTANCE_AUTOMATION_RULES.md).
%
%   result = run_m2_session_chain(injectError)
%   injectError (default '') selects a controlled, non-destructive failure
%   injection for the round-4 closure verification:
%     'unit'      -> test_m2_eta_esc_unit fails after touching globals
%     'compare'   -> the bypass-compare result is forced to pass = false
%     'injection' -> the safety-injection result is forced to pass = false
%     'trials'    -> run_air_m2_trials short-circuits with pass = false
%   Each injection drives the chain through its real assert exit.

function result = run_m2_session_chain(injectError)
if nargin < 1
    injectError = '';
end
validInj = {'', 'unit', 'compare', 'injection', 'trials'};
assert(any(strcmp(injectError, validInj)), 'air:M2Session:BadInject', ...
    'injectError must be one of %s', strjoin(validInj, '|'));

fprintf('===== M2 SESSION CHAIN BEGIN =====\n');

% R2-F1/R3-F1: normalize the M2 session state to the safe identity BEFORE
% any entry runs, regardless of what earlier M2 runs left in this session;
% the caller's entry state is restored on exit (success or error -- the
% function-frame onCleanup runs on the error path too).
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

if strcmp(injectError, 'unit')
    test_m2_eta_esc_unit('unit');
else
    test_m2_eta_esc_unit();
end

r1 = run_air_m0a_baseline_compare();
if strcmp(injectError, 'compare')
    r1.pass = false;
end
assert(r1.pass, 'air:M2Session:CompareFailed', ...
    'bypass compare failed (max diff %.3g)', r1.maxOverallDiff);
fprintf('CHAIN: compare PASS, max diff %.3g\n', r1.maxOverallDiff);

r2 = run_air_m0b_safety_injection();
if strcmp(injectError, 'injection')
    r2.pass = false;
end
assert(r2.pass, 'air:M2Session:InjectionFailed', ...
    'M0-B safety injection failed');
fprintf('CHAIN: safety injection PASS\n');

result = run_air_m2_trials(injectError);
% R2-F2: run_air_m2_trials reports failures only through result.pass --
% without this assert the chain could print END and exit successfully on a
% failed trials run (automation false-green).
assert(result.pass, 'air:M2Session:TrialsFailed', ...
    'M2 trials failed, archive %s', result.archiveDir);
fprintf('CHAIN: M2 trials PASS, archive %s\n', result.archiveDir);

fprintf('===== M2 SESSION CHAIN END =====\n');
end

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
