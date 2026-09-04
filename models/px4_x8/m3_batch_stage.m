function result = m3_batch_stage(segName, stagedDir)
%M3_BATCH_STAGE Run ONE batch segment through run_air_m3_trials with the
%   staged bookkeeping (rules v1.7 section 2 rule 7): the trials entry
%   validates the manifest against the source contract, bumps the
%   persistent attempt counter and refuses over-budget execution; the
%   cross-segment baseline arms are loaded from the B0-N segment's done
%   stamp (that segment must already be complete -- staged execution is
%   strictly ordered). Machine-checkable result; the done stamp is the
%   driver's authoritative freshness marker.
S = load(fullfile(stagedDir, 'manifest.mat'), 'manifest');
[segs, ~] = m3_batch_validate(S.manifest);
hit = find(strcmp({segs.name}, segName), 1);
assert(~isempty(hit), 'air:M3BatchStage:UnknownSegment', ...
    'segment %s is not in the staged manifest', segName);
arms = segs(hit).arms;
[bnIdx, ~] = m3_batch_locate(segs, 'B0-N');
baseDir = '';
if bnIdx ~= hit
    f = fullfile(stagedDir, [segs(bnIdx).name '.done.mat']);
    assert(exist(f, 'file'), 'air:M3BatchStage:BaseNotDone', ...
        ['segment %s needs the B0-N segment (%s) to be complete first ' ...
        '-- staged execution is ordered'], segName, segs(bnIdx).name);
    D = load(f, 'done');
    baseDir = char(D.done.archiveDir);
    assert(isfolder(baseDir), 'air:M3BatchStage:BaseArchiveGone', ...
        'B0-N segment archive %s no longer exists', baseDir);
end
result = run_air_m3_trials('', arms, baseDir, stagedDir);
end
