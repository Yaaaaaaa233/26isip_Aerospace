function [idx, fieldName] = m3_batch_locate(segments, arm)
%M3_BATCH_LOCATE Index of the manifest segment whose arm list contains
%   the arm (and the runs-field name). Cross-file helper shared by the
%   validator, the stage wrapper and the aggregate.
if isstruct(segments)
    lists = {segments.arms};
else
    lists = segments;
end
for k = 1:numel(lists)
    if any(strcmp(lists{k}, arm))
        idx = k;
        fieldName = strrep(arm, '-', '_');
        return
    end
end
error('air:M3Batch:Internal', 'arm %s not found in any segment', arm);
end
