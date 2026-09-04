function manifest = m3_batch_init(stagedDir, segments)
%M3_BATCH_INIT Batch init (rules v1.7 section 2 rules 4/5): generate the
%   COMMON BATCH ID (distinct from every segment's own execution runId),
%   capture the LIVE source identity (commit, clean-tree gate, SHA-256 of
%   every governance-relevant file -- no 'unknown' placeholders, nothing
%   copied from a previous moment), and write the staged manifest that
%   every segment entry and the aggregate will re-validate against
%   m3_batch_contract (the manifest is evidence, not authority).
%   segments: optional override of the canonical segmentation (any valid
%   layout per the contract); default = the contract's canonical layout.
%   The caller (tools/run_m3_batch.ps1) creates the staged directory
%   under results/ (gitignored, so the markers never dirty the tree).
if nargin < 2 || isempty(segments)
    segments = m3_batch_contract().segments;
end
if ~isfolder(stagedDir)
    mkdir(stagedDir);
end
c = m3_batch_contract();
here = fileparts(mfilename('fullpath'));

% live identity: fresh capture, dirty tree is a hard failure
repoRoot = fileparts(fileparts(here));
[st, out] = system(sprintf('git -C "%s" rev-parse HEAD', repoRoot));
assert(st == 0, 'air:M3Batch:InitBinding', ...
    'git rev-parse HEAD failed (exit %d) -- evidence cannot be bound', st);
gitCommit = strtrim(out);
[st2, out2] = system(sprintf('git -C "%s" status --porcelain', repoRoot));
assert(st2 == 0, 'air:M3Batch:InitBinding', ...
    'git status failed (exit %d) -- cannot establish dirty state', st2);
lines = strsplit(strtrim(out2), '\n', 'CollapseDelimiters', true);
dirtyLines = lines(~cellfun(@isempty, lines));
assert(isempty(dirtyLines), 'air:M3Batch:DirtyTree', ...
    ['batch init requires a clean working tree; uncommitted changes:\n%s'], ...
    strjoin(dirtyLines, newline));

shaFiles = struct( ...
    'aggregate', sha256file(fullfile(here, 'm3_aggregate_batch.m')), ...
    'trials', sha256file(fullfile(here, 'run_air_m3_trials.m')), ...
    'contract', sha256file(fullfile(here, 'm3_batch_contract.m')), ...
    'evalArm', sha256file(fullfile(here, 'm3_eval_arm.m')), ...
    'model', sha256file(fullfile(here, 'air_spare.slx')), ...
    'm0c', sha256file(fullfile(here, 'm0c_vref_esc.m')), ...
    'm2', sha256file(fullfile(here, 'm2_eta_esc.m')));

manifest = struct();
manifest.batchId = char(java.util.UUID.randomUUID());
manifest.gitCommit = gitCommit;
manifest.created = datetime('now');
manifest.maxAttempts = c.maxAttempts;
manifest.segments = struct('name', {}, 'arms', {{}});
for k = 1:numel(segments)
    manifest.segments(k).name = sprintf('s%d', k);
    manifest.segments(k).arms = segments{k};
end
manifest.sha = shaFiles;
% round-trip through the shared validator: the manifest init writes must
% itself satisfy the contract it will be checked against
[~, ~] = m3_batch_validate(manifest);
f = fullfile(stagedDir, 'manifest.mat');
tmp = fullfile(stagedDir, 'manifest.mat.tmp');
save(tmp, 'manifest');
movefile(tmp, f);
fprintf('batch init: batchId %s, commit %s, %d segments, maxAttempts %d\n', ...
    manifest.batchId, gitCommit(1:7), numel(manifest.segments), ...
    manifest.maxAttempts);
end

function h = sha256file(fname)
%SHA256FILE lowercase hex SHA-256 of a file (m3_source_binding pattern).
fid = fopen(fname, 'rb');
assert(fid > 0, 'air:M3Batch:InitBinding', 'cannot open %s', fname);
data = fread(fid, '*uint8')';
fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
d = md.digest(data);
h = lower(sprintf('%02x', typecast(int8(d), 'uint8')));
end
