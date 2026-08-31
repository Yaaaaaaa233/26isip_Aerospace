function diag_m0b_test_postmortem(archiveDir)
%DIAG_M0B_TEST_POSTMORTEM Inspect archived M0-B test runs.

if nargin < 1
    archiveDir = 'D:\Study\Sophomore_to_Junior\UAV\第二阶段\results\air_m0b_tests\20260831_224226';
end
for name = ["S1a_fixed5", "S1b_fixed9", "S2_step_6to9", "S3_safety_demo"]
    f = fullfile(archiveDir, [char(name) '.mat']);
    if ~isfile(f)
        fprintf('%s: no archive\n', name);
        continue;
    end
    S = load(f);
    Mb = S.Mb; tb = S.tb; A = S.A; Ve = S.Ve;
    fprintf('=== %s (bus %dx%d) ===\n', name, size(Mb, 1), size(Mb, 2));
    fprintf('v_ref : tail %6.3f  range [%6.3f %6.3f]\n', mean(Mb(tb > 5, 1)), min(Mb(:, 1)), max(Mb(:, 1)));
    fprintf('pitch : tail %6.3f  range [%6.3f %6.3f]\n', mean(Mb(tb > 5, 2)), min(Mb(:, 2)), max(Mb(:, 2)));
    fprintf('v     : tail %6.3f  range [%6.3f %6.3f]\n', mean(Mb(tb > 5, 7)), min(Mb(:, 7)), max(Mb(:, 7)));
    fprintf('ve_x  : tail %6.3f  range [%6.3f %6.3f]\n', mean(Mb(tb > 5, 6)), min(Mb(:, 6)), max(Mb(:, 6)));
    fprintf('ve_y  : tail %6.3f  range [%6.3f %6.3f]\n', mean(Ve(tb > 5, 2)), min(Ve(:, 2)), max(Ve(:, 2)));
    fprintf('theta : tail %6.3f  range [%6.3f %6.3f]\n', mean(A(tb > 5, 6)), min(A(:, 6)), max(A(:, 6)));
    fprintf('status: uniq [%s]\n', num2str(unique(Mb(:, 4))'));
    F = A(:, 27:34);
    fprintf('flags : max per bit [%s]\n', num2str(max(F, [], 1)));
    % sample every 2 s
    for tq = [0 2 4 6 8 10]
        [~, i] = min(abs(tb - tq));
        fprintf('  t=%4.1f  vref %5.2f  v %6.2f  vex %7.2f  pitch %+6.3f  theta %+7.4f  st %d\n', ...
            tb(i), Mb(i, 1), Mb(i, 7), Mb(i, 6), Mb(i, 2), A(i, 6), Mb(i, 4));
    end
end
end
