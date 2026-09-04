function m3_stage_done(stagedDir, stageName, stamp)
%M3_STAGE_DONE Write the stage done stamp (rules v1.7 section 2 rule
%   7d/7e): the driver's authoritative FRESH-EVIDENCE marker, written
%   only after the stage's evidence is atomically complete, so a process
%   that dies after the stamp is harmless and a process that dies before
%   it is retried from the stage entry whatever its exit code said.
%   stamp: struct merged into the stamp (segment name / runId / batchId /
%   attempts / archiveDir / gitCommit ...).
assert(isfolder(stagedDir), 'air:M3Stage:NoStagedDir', ...
    'staged directory %s does not exist', stagedDir);
done = stamp;
done.stage = stageName;
done.finished = datetime('now');
f = fullfile(stagedDir, [stageName '.done.mat']);
tmp = fullfile(stagedDir, [stageName '.done.mat.tmp']);
save(tmp, 'done');
movefile(tmp, f);   % atomic replace: the marker appears complete or not at all
end
