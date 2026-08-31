function result = run_air_m0b_tests()
%RUN_AIR_M0B_TESTS M0-B acceptance after the 2026-09-01 review repair.
%   Scenarios (all parameter changes are IN MEMORY ONLY; the saved model is
%   reloaded after each scenario and never modified):
%
%     N1 nominal 9 m/s : speed loop on, manual v_ref = 9, and the
%         InputConditioning roll sine amplitude set to 0 for the test
%         scenario (structure untouched). Validates the outer loop proper.
%         PASS: settle window (t in [6,10] s) mean|err| <= 0.5 m/s,
%         max|err| <= 1.0 m/s, speed-miss occupancy < 10 %, longest
%         continuous miss-free interval >= 3 s.
%     D1 disturbed 5 m/s, D2 disturbed 9 m/s : baseline roll sine active.
%         PASS: mean|err| <= 2.5 m/s (roll-sine disturbance floor,
%         documented), PWM never near the 1000/2000 rails, |theta| within
%         its own 0.209 rad clamp bound, hard flags genuinely quiet.
%         Max error / miss occupancy / longest clean window are recorded
%         (evidence for the M0-C stable-window design).
%     S2 step 6 -> 9 m/s at t = 4 s (disturbed): pre window t in [3.2,4)
%         must be non-empty and finite; post window [8,10] mean|err| <= 2.5,
%         90 % rise finite.
%
%   The former S3 attitude-threshold demo is retired: it never reached the
%   active state (review P2). Safety-chain validation now lives in
%   run_air_m0b_safety_injection.m.
%
%   Hard-flag checks exclude the 5 ms initialisation window (the root PWM
%   net is genuinely 0 at t = 0, an air-model artefact).

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
wsRoot = fileparts(fileparts(modelDir));
scenarios = {'N1_nominal9', 'D1_dist5', 'D2_dist9', 'S2_step_6to9'};
rows = {};
pass = true;

outDir = fullfile(wsRoot, 'results', 'air_m0b_tests', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

for si = 1:numel(scenarios)
    name = scenarios{si};
    fprintf('=== %s ===\n', name);
    wasLoaded = bdIsLoaded(model);
    if ~wasLoaded
        load_system(fullfile(modelDir, [model '.slx']));
    end
    try
        set_param(model, 'SimulationCommand', 'update');
        applyScenario(model, name);
        out = sim(model);

        m0b = out.get('m0b_log_bus');
        Mb = double(squeeze(m0b.Data));
        if size(Mb, 2) ~= 7
            Mb = Mb';
        end
        tb = m0b.Time(:);
        m0a = out.get('m0a_log_bus');
        A = double(squeeze(m0a.Data));
        if size(A, 2) ~= 35
            A = A';
        end
        ta = m0a.Time(:);
        veTs = out.get('m0a_Ve_inertial_mps');
        Ve = double(squeeze(veTs.Data));
        if size(Ve, 2) == numel(veTs.Time)
            Ve = Ve';
        end

        % m0b columns: 1 v_ref, 2 pitch_cmd, 3 v_err, 4 status,
        %              5 loop_enable, 6 ve_x, 7 v
        okBus = size(Mb, 1) == 10001 && size(Mb, 2) == 7;
        Aw = A(ta >= 0.005, :);
        thetaMax = max(abs(Aw(:, 6)));
        pwmMin = min(Aw(:, 11:18), [], 'all');
        pwmMax = max(Aw(:, 11:18), [], 'all');
        Fw = Aw(:, 27:34);
        hardMax = max(Fw(:, [1 2 3 4 6 7]), [], 'all');
        cmdMax = max(abs(Mb(:, 2)));
        cSat = thetaMax < 0.25 && pwmMin > 1005 && pwmMax < 1995 && ...
            cmdMax <= 0.4 + 1e-9 && hardMax == 0;

        switch name
            case {'N1_nominal9', 'D1_dist5', 'D2_dist9'}
                w = tb >= 6 & tb <= 10;
                errAbs = abs(Mb(w, 7) - Mb(w, 1));
                meanErr = mean(errAbs);
                maxErr = max(errAbs);
                miss = errAbs > 1.0;
                missFrac = mean(miss);
                cleanRun = ~miss;
                runEdge = diff([false; cleanRun; false]);
                starts = find(runEdge == 1);
                ends = find(runEdge == -1);
                longestClean = max(ends - starts);   % in samples (1 ms)
                if isempty(longestClean)
                    longestClean = 0;
                end
                if strcmp(name, 'N1_nominal9')
                    cTrack = meanErr <= 0.5 && maxErr <= 1.0 && ...
                        missFrac < 0.10 && longestClean >= 3000;
                else
                    cTrack = meanErr <= 2.5;
                end
                thisPass = okBus && cTrack && cSat;
                fprintf(['  mean|err| %.3f  max|err| %.3f  miss %.1f%%  ' ...
                    'longestClean %.2f s\n'], meanErr, maxErr, ...
                    100 * missFrac, longestClean * 0.001);
                fprintf('  thetaMax %.3f  pwm [%.0f %.0f]  cmdMax %.3f  hardFlags %.0f\n', ...
                    thetaMax, pwmMin, pwmMax, cmdMax, hardMax);
                sc = struct('mean_abs_err', meanErr, 'max_abs_err', maxErr, ...
                    'miss_frac', missFrac, 'longest_clean_s', longestClean * 0.001, ...
                    'theta_max', thetaMax, 'pwm_min', pwmMin, 'pwm_max', pwmMax, ...
                    'hard_flag_max', hardMax, 'cmd_max', cmdMax, ...
                    'criteria', {okBus, cTrack, cSat});
                rows(end+1, :) = {name, sprintf('mean|err| %.3f', meanErr), ...
                    meanErr, thisPass}; %#ok<AGROW>
            case 'S2_step_6to9'
                stepT = 4.0;
                pre = tb >= 3.2 & tb < stepT;
                post = tb >= 8.0 & tb <= 10;
                assert(any(pre), 'air:M0B:EmptyPreWindow', ...
                    'step pre-window is empty (review P2 regression).');
                preErr = mean(abs(Mb(pre, 7) - Mb(pre, 1)));
                assert(isfinite(preErr), 'air:M0B:NonFinitePre', ...
                    'step pre-window metric is not finite.');
                postErr = mean(abs(Mb(post, 7) - Mb(post, 1)));
                afterStep = tb > stepT;
                vAfter = Mb(afterStep, 7);
                tAfter = tb(afterStep);
                idx90 = find(vAfter >= 8.7, 1, 'first');
                if isempty(idx90)
                    rise90 = NaN;
                else
                    rise90 = tAfter(idx90) - stepT;
                end
                cTrack = postErr <= 2.5 && isfinite(rise90);
                thisPass = okBus && cTrack && cSat;
                fprintf('  pre|err| %.3f  post|err| %.3f  rise90 %.2f s\n', ...
                    preErr, postErr, rise90);
                fprintf('  thetaMax %.3f  pwm [%.0f %.0f]  hardFlags %.0f\n', ...
                    thetaMax, pwmMin, pwmMax, hardMax);
                sc = struct('pre_err', preErr, 'post_err', postErr, ...
                    'rise90_s', rise90, 'theta_max', thetaMax, ...
                    'pwm_min', pwmMin, 'pwm_max', pwmMax, ...
                    'hard_flag_max', hardMax, 'cmd_max', cmdMax, ...
                    'criteria', {okBus, cTrack, cSat});
                rows(end+1, :) = {name, sprintf('post|err| %.3f', postErr), ...
                    postErr, thisPass}; %#ok<AGROW>
        end
        if ~thisPass
            pass = false;
        end
        save(fullfile(outDir, [name '.mat']), 'sc', 'Mb', 'tb', 'A', 'ta', 'Ve');
    catch err
        fprintf('  scenario %s FAILED: %s\n', name, err.message);
        rows(end+1, :) = {name, err.message, NaN, false}; %#ok<AGROW>
        pass = false;
    end
    if bdIsLoaded(model)
        close_system(model, 0);
    end
end

T = cell2table(rows, 'VariableNames', {'scenario', 'metric', 'value', 'pass'});
writetable(T, fullfile(outDir, 'summary.csv'));
result = struct('pass', pass, 'table', T, 'archiveDir', string(outDir));
if pass
    fprintf('M0-B TESTS PASS\n');
else
    fprintf('M0-B TESTS FAIL (see summary)\n');
end
disp(T);
fprintf('Archive: %s\n', outDir);
end

function applyScenario(model, name)
set_param([model '/M0B Speed Loop Enable'], 'Value', '1');
switch name
    case 'N1_nominal9'
        % nominal scenario: disable the roll-sine disturbance amplitude for
        % this test run only (in-memory; the roll path structure is kept)
        set_param([model '/Attitude Control/InputConditioning/Sine Wave'], ...
            'Amplitude', '0');
        set_param([model '/M0B v Ref Manual'], 'Value', '9');
    case 'D1_dist5'
        set_param([model '/M0B v Ref Manual'], 'Value', '5');
    case 'D2_dist9'
        set_param([model '/M0B v Ref Manual'], 'Value', '9');
    case 'S2_step_6to9'
        % replace the manual constant by an in-memory Step 6 -> 9 at t = 4 s
        constBlk = [model '/M0B v Ref Manual'];
        cl = get_param(get_param(constBlk, 'PortHandles').Outport(1), 'Line');
        dsts = get_param(cl, 'DstPortHandle');
        delete_line(cl);
        delete_block(constBlk);
        stepBlk = [model '/M0B v Ref Manual Step'];
        add_block('simulink/Sources/Step', stepBlk, ...
            'Position', [1180, 890, 1210, 920], ...
            'Time', '4', 'Before', '6', 'After', '9', ...
            'SampleTime', '0.001');
        for m = 1:numel(dsts)
            add_line(model, get_param(stepBlk, 'PortHandles').Outport(1), ...
                dsts(m), 'autorouting', 'on');
        end
end
set_param(model, 'SimulationCommand', 'update');
end
