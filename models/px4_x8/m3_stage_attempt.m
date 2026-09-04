function attempts = m3_stage_attempt(stagedDir, stageName, maxAttempts)
%M3_STAGE_ATTEMPT Bump (and budget-check) the persistent per-stage attempt
%   counter (rules v1.7 section 2 rule 7c/7d/7g). The counter lives in the
%   gitignored staged directory, is written by ATOMIC REPLACEMENT (temp
%   file + rename, so a native crash window leaves the old or the new
%   value, never a truncated marker), and the entry REFUSES an
%   over-budget execution independently of the driver. A corrupted,
%   empty or non-numeric marker is a hard failure (BadAttempts) and is
%   never auto-rebuilt -- an unexplainable marker must stop the batch,
%   not be papered over.
assert(isfolder(stagedDir), 'air:M3Stage:NoStagedDir', ...
    'staged directory %s does not exist', stagedDir);
f = fullfile(stagedDir, [stageName '.attempts']);
if exist(f, 'file')
    raw = strtrim(fileread(f));
    val = str2double(raw);
    assert(~isempty(raw) && isfinite(val) && val > 0 && ...
        val == floor(val) && val <= maxAttempts, ...
        'air:M3Stage:BadAttempts', ...
        ['persistent attempt marker %s contains "%s" -- corrupted or ' ...
        'out-of-budget markers are hard failures and are never rebuilt'], ...
        f, raw);
else
    val = 0;
end
attempts = val + 1;
assert(attempts <= maxAttempts, 'air:M3Stage:AttemptBudget', ...
    ['stage %s would start attempt %d, over the frozen budget of %d ' ...
    '(rules section 2 rule 7c): a deterministic failure must abort the ' ...
    'batch, not be retried away'], stageName, attempts, maxAttempts);
tmp = fullfile(stagedDir, [stageName '.attempts.tmp']);
fid = fopen(tmp, 'w');
assert(fid > 0, 'air:M3Stage:MarkerWrite', 'cannot write %s', tmp);
fprintf(fid, '%d\n', attempts);
fclose(fid);
movefile(tmp, f);   % atomic on NTFS same volume (replace-existing)
end
