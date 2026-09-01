%RUN_M2_SESSION_CHAIN Full M2 acceptance chain in ONE MATLAB session, in
%   AGENTS.md order, with NO manual state clearing -- the unit test
%   self-isolates (reacceptance Z1) so the rest of the chain passes.
%   Introduced by the 2026-09-01 reacceptance fix round (Z5) and used for
%   the 3-session verification (docs/evidence/M2_REACCEPT_FIX_20260901.md).
%   Runs:
%     1. test_m2_eta_esc_unit          (session-isolation fix under test)
%     2. run_air_m0a_baseline_compare  (bypass diff must be 0)
%     3. run_air_m0b_safety_injection  (4/4)
%     4. run_air_m2_trials             (120 s settled-window protocol)

fprintf('===== M2 SESSION CHAIN BEGIN =====\n');
test_m2_eta_esc_unit;

r1 = run_air_m0a_baseline_compare();
assert(r1.pass, 'air:M2Session:CompareFailed', ...
    'bypass compare failed (max diff %.3g)', r1.maxOverallDiff);
fprintf('CHAIN: compare PASS, max diff %.3g\n', r1.maxOverallDiff);

r2 = run_air_m0b_safety_injection();
assert(r2.pass, 'air:M2Session:InjectionFailed');
fprintf('CHAIN: safety injection PASS\n');

run_air_m2_trials;
fprintf('===== M2 SESSION CHAIN END =====\n');
