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
repoRoot = fileparts(fileparts(here));

% live identity: fresh capture via the shared fingerprint source (the
% manifest's sha block and the aggregate's re-asserted set must never
% drift apart), dirty tree is a hard failure
fp = m3_live_fingerprints();
gitCommit = fp.head;
[st2, out2] = system(sprintf('git -C "%s" status --porcelain', repoRoot));
assert(st2 == 0, 'air:M3Batch:InitBinding', ...
    'git status failed (exit %d) -- cannot establish dirty state', st2);
lines = strsplit(strtrim(out2), '\n', 'CollapseDelimiters', true);
dirtyLines = lines(~cellfun(@isempty, lines));
assert(isempty(dirtyLines), 'air:M3Batch:DirtyTree', ...
    ['batch init requires a clean working tree; uncommitted changes:\n%s'], ...
    strjoin(dirtyLines, newline));

shaFiles = fp.sha;

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
