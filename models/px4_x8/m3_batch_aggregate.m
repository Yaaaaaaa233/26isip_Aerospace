function result = m3_batch_aggregate(stagedDir)
%M3_BATCH_AGGREGATE Driver-facing aggregate stage: resolve the segment
%   archive dirs from the staged done stamps (every manifest segment must
%   have completed -- the batch verdict aggregates exactly the staged
%   evidence) and run the hardened aggregate. The new timestamped
%   *_aggregate archive directory is the stage's freshness marker.
S = load(fullfile(stagedDir, 'manifest.mat'), 'manifest');
[segs, ~] = m3_batch_validate(S.manifest);
segDirs = {};
for k = 1:numel(segs)
    f = fullfile(stagedDir, [segs(k).name '.done.mat']);
    assert(exist(f, 'file'), 'air:M3BatchAgg:SegmentNotDone', ...
        'segment %s has no done stamp -- the batch is incomplete', ...
        segs(k).name);
    D = load(f, 'done');
    assert(strcmp(D.done.batchId, S.manifest.batchId), ...
        'air:M3BatchAgg:StampBatchId', ...
        'done stamp of %s carries a foreign batchId', segs(k).name);
    assert(isfolder(char(D.done.archiveDir)), ...
        'air:M3BatchAgg:ArchiveGone', ...
        'archive %s of segment %s no longer exists', ...
        D.done.archiveDir, segs(k).name);
    segDirs{end + 1} = char(D.done.archiveDir); %#ok<AGROW>
end
result = m3_aggregate_batch(segDirs, stagedDir);
end
