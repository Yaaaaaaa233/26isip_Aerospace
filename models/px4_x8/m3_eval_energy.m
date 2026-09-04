function r = m3_eval_energy(tA, PA, validA, tB, PB, validB, win, thr)
%M3_EVAL_ENERGY Paired-window energy difference (M3 doc 5/6.2).
%   Both arms integrate on the SAME continuous grid with the SAME
%   valid-mask strategy: the pairwise-common mask (validA & validB) is
%   applied to both arms so no arm can shrink its own integration set,
%   and the mask itself is returned for archival. Grid mismatches,
%   missing pair arms and empty valid windows are rejected with exact
%   error ids instead of producing a silent number.
if isempty(tB) || isempty(PB)
    error('air:M3:MissingPair', ...
        'the paired baseline arm is missing: no dangling pairings (M3 doc 5)');
end
if numel(tA) ~= numel(tB) || numel(PA) ~= numel(PB) || ...
        numel(validA) ~= numel(validB)
    error('air:M3:GridMismatch', 'arm grid lengths differ');
end
if max(abs(tA(:) - tB(:))) > 1e-9
    error('air:M3:GridMismatch', ...
        'arm time grids are not aligned (max offset %g s)', ...
        max(abs(tA(:) - tB(:))));
end
t = tA(:); Ts = t(2) - t(1);
if max(abs(diff(t) - Ts)) > 1e-9
    error('air:M3:GridMismatch', 'time grid is not uniform');
end
sel = t >= win(1) - 1e-9 & t <= win(2) + 1e-9;
if ~any(sel)
    error('air:M3:NoValidWindow', 'the evaluation window is empty on this grid');
end
mask = sel & logical(validA(:)) & logical(validB(:));
if ~any(mask)
    error('air:M3:NoValidWindow', ...
        'no pairwise-valid samples in the window: report, do not exempt');
end
EA = sum(PA(mask)) * Ts;
EB = sum(PB(mask)) * Ts;
dEPct = 100 * (EA - EB) / EB;
% dual-track statistics (round-1 finding M3-R1-F5): the frozen primary
% gate stays on the pairwise-common valid mask, but the full continuous
% window integral and the actual mask coverage are reported alongside --
% a 4.8 s / 96 s common subset must never be described as the whole
% cycle window again.
EAfull = sum(PA(sel)) * Ts;
EBfull = sum(PB(sel)) * Ts;
nWin = sum(sel);
r = struct('pass', dEPct <= thr, 'dEPct', dEPct, 'EA', EA, 'EB', EB, ...
    'nMask', sum(mask), 'mask', mask, 'Ts', Ts, ...
    'nWin', nWin, 'covA', sum(sel & logical(validA(:))) / nWin, ...
    'covB', sum(sel & logical(validB(:))) / nWin, ...
    'maskFrac', sum(mask) / nWin, ...
    'dEPctFull', 100 * (EAfull - EBfull) / EBfull, ...
    'EAfull', EAfull, 'EBfull', EBfull);
end
