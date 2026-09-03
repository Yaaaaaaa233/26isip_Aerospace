function r = m3_check_execution(t, searchV, searchE, candV, candE, ...
    applV, applE, prmV, prmE)
%M3_CHECK_EXECUTION Execution-evidence checker (M3 doc sections 2.3/5).
%   The role inputs are the EXPECTATION (plan, reconstructed from
%   m3_schedule offline); the predicates below run on the archived
%   candidate (adapter) and applied (selector/allocator) signals, which
%   are produced independently of the schedule. A traitor adapter that
%   keeps searching while the plan says hold fails on holdConstancy; a
%   correctly rate-limited application must NOT fail (no false alarm).
%
%   Inputs (per 0.05 s sample, columns = samples):
%     t        time vector (uniform grid, only used for validation)
%     searchV  logical, true where the PLAN says the v channel searches
%     searchE  logical, true where the PLAN says the eta channel searches
%     candV/candE   adapter candidate outputs (v_ref / eta_ref)
%     applV/applE   applied outputs after the selector / allocator path
%     prmV/prmE     struct('amplitude',...,'rateLimit',...,'Ts',...)
%
%   Output r: machine-checkable struct (pass, failFields, diagnostics).
%   NOTE: the check helpers return the (possibly updated) result struct --
%   MATLAB passes structs by value, so in-place mutation would be lost.
n = numel(t);
r = struct('pass', false, 'failFields', {{}}, 'n', n, ...
    'nHoldRunsV', 0, 'nHoldRunsE', 0, 'maxHoldDevV', 0.0, ...
    'maxHoldDevE', 0.0, 'maxAppliedLagV', 0.0, 'maxAppliedLagE', 0.0);
if numel(searchV) ~= n || numel(searchE) ~= n || numel(candV) ~= n || ...
        numel(candE) ~= n || numel(applV) ~= n || numel(applE) ~= n
    error('air:M3:CheckLength', ...
        'execution-evidence inputs must be equal-length columns');
end

% 1. plan sanity: exactly one channel searches at any sample
if any(searchV & searchE) || ~all(searchV | searchE)
    r = addFailField(r, 'planNotExclusive');
end

% 2. hold constancy: within every planned hold run the candidate must be
%    constant to 1e-12 (hold outputs the clean center; the kernel state
%    that would move it is never stepped). This is the traitor detector.
r = checkHold(r, candV, searchV, 'V');
r = checkHold(r, candE, searchE, 'E');

% 3. applied slew must respect the channel rate limit everywhere
r = checkSlew(r, applV, prmV, 'V');
r = checkSlew(r, applE, prmE, 'E');

% 4. applied must track the candidate once past the transition length
%    L = ceil(amplitude/rateLimit/Ts) samples after any role change
r = checkLag(r, candV, applV, searchV, prmV, 'V');
r = checkLag(r, candE, applE, searchE, prmE, 'E');

% 5. role-change transient bound: the candidate may move by at most one
%    dither amplitude at any planned hold <-> search transition
r = checkResume(r, candV, searchV, prmV, 'V');
r = checkResume(r, candE, searchE, prmE, 'E');

r.pass = isempty(r.failFields);
end

function r = addFailField(r, name)
%ADDFAILFIELD append a failure field name, deduplicated, order preserved.
for j = 1:numel(r.failFields)
    if strcmp(r.failFields{j}, name)
        return;
    end
end
r.failFields{end + 1} = name; %#ok<AGROW>
end

function r = checkHold(r, cand, search, ch)
%CHECKHOLD candidate must be exactly constant in every planned hold run.
runs = holdRuns(~search);
for j = 1:size(runs, 1)
    seg = cand(runs(j, 1):runs(j, 2));
    dev = max(abs(seg - seg(1)));
    if strcmp(ch, 'V')
        r.nHoldRunsV = r.nHoldRunsV + 1;
        r.maxHoldDevV = max(r.maxHoldDevV, dev);
    else
        r.nHoldRunsE = r.nHoldRunsE + 1;
        r.maxHoldDevE = max(r.maxHoldDevE, dev);
    end
    if dev > 1e-12
        r = addFailField(r, sprintf('holdConstancy%s', ch));
    end
end
end

function r = checkSlew(r, appl, prm, ch)
d = prm.rateLimit * prm.Ts;
dd = abs(diff(appl));
if any(dd > d * (1 + 1e-9) + 1e-15)
    r = addFailField(r, sprintf('appliedSlew%s', ch));
end
end

function r = checkLag(r, cand, appl, search, prm, ch)
n = numel(search);
trans = find([true; diff(search) ~= 0]);
L = ceil(prm.amplitude / (prm.rateLimit * prm.Ts));
for k = 1:n
    kt = trans(find(trans <= k, 1, 'last'));
    if k - kt > L
        lag = abs(appl(k) - cand(k));
        if strcmp(ch, 'V')
            r.maxAppliedLagV = max(r.maxAppliedLagV, lag);
        else
            r.maxAppliedLagE = max(r.maxAppliedLagE, lag);
        end
        if lag > 1e-9
            r = addFailField(r, sprintf('appliedLag%s', ch));
        end
    end
end
end

function r = checkResume(r, cand, search, prm, ch)
idx = find(diff(search) ~= 0) + 1;   % planned role changes
for j = 1:numel(idx)
    k = idx(j);
    dev = abs(cand(k) - cand(k - 1));
    if dev > prm.amplitude * 1.001 + 1e-15
        r = addFailField(r, sprintf('resumeJump%s', ch));
    end
end
end

function runs = holdRuns(holdLgl)
%HOLDRUNS maximal runs of holdLgl==true as [start end] pairs.
padded = [false; holdLgl(:); false];
d = diff(padded);
runs = [find(d == 1), find(d == -1) - 1];
if isempty(runs)
    runs = zeros(0, 2);
end
end
