function b = m3_source_binding(entryFile)
%M3_SOURCE_BINDING Live source-identity capture for M3 batch evidence
%   (round-1 finding M3-R1-F4; rules v1.7 section 2 rules 4/5 pattern).
%   Every entry captures its OWN binding at run time: a fresh run id, the
%   LIVE git HEAD (no 'unknown' placeholder -- a failed capture is a hard
%   error), the dirty-tree state and SHA-256 fingerprints of the entry
%   file, air_spare.slx and both adapters. Entries that produce evidence
%   must reject a dirty tree themselves (see allowDirty); the aggregate
%   re-captures independently and requires equality across segments.
%
%   entryFile: absolute path of the calling entry (.m).
%   b: struct with runId, gitCommit, dirty, dirtyLines, created,
%      sha.entry / sha.model / sha.m0c / sha.m2.
repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
b = struct();
b.runId = char(java.util.UUID.randomUUID());
[st, out] = system(sprintf('git -C "%s" rev-parse HEAD', repoRoot));
assert(st == 0, 'air:M3:SourceBinding', ...
    'git rev-parse HEAD failed (exit %d) -- evidence cannot be bound', st);
b.gitCommit = strtrim(out);
[st2, out2] = system(sprintf('git -C "%s" status --porcelain', repoRoot));
assert(st2 == 0, 'air:M3:SourceBinding', ...
    'git status failed (exit %d) -- cannot establish dirty state', st2);
lines = strsplit(strtrim(out2), '\n', 'CollapseDelimiters', true);
b.dirtyLines = lines(~cellfun(@isempty, lines));
b.dirty = ~isempty(b.dirtyLines);
b.created = datetime('now');
dirHere = fileparts(mfilename('fullpath'));
b.sha = struct( ...
    'entry', sha256file(entryFile), ...
    'model', sha256file(fullfile(dirHere, 'air_spare.slx')), ...
    'm0c', sha256file(fullfile(dirHere, 'm0c_vref_esc.m')), ...
    'm2', sha256file(fullfile(dirHere, 'm2_eta_esc.m')));
end

function h = sha256file(fname)
%SHA256FILE lowercase hex SHA-256 of a file.
fid = fopen(fname, 'rb');
assert(fid > 0, 'air:M3:SourceBinding', 'cannot open %s', fname);
data = fread(fid, '*uint8')';
fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
d = md.digest(data);
h = lower(sprintf('%02x', typecast(int8(d), 'uint8')));
end
