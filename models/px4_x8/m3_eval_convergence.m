function r = m3_eval_convergence(t, center, isSearch, freq, tolDist, tolMono)
%M3_EVAL_CONVERGENCE Eta-center convergence criterion (M3 doc 6.4).
%   Uses ONLY the last maximal contiguous search run (hold samples never
%   count -- a hold-only "convergence" must not pass). Within that run
%   the trace is split into full dither periods (1/freq); converged when
%   the mean of the period means over the whole run is within tolDist of
%   the target 1.0, monotonic when the period-end distances to 1.0 never
%   regress by more than tolMono between adjacent periods.
%
%   t: time column; center: center-trace column (search samples only
%   meaningful); isSearch: logical plan column; freq: dither frequency
%   [Hz]; tolDist / tolMono: frozen tolerances (M3 doc 6.4: 0.01/5e-3).
if numel(t) ~= numel(center) || numel(t) ~= numel(isSearch)
    error('air:M3:ConvergenceLength', 'inputs must be equal-length columns');
end
Ts = t(2) - t(1);
runs = searchRuns(isSearch);
if isempty(runs)
    error('air:M3:NoSearchWindow', ...
        'no search samples in the trace: hold-only pseudo-convergence is not admissible evidence (M3 doc 6.4)');
end
i0 = runs(end, 1); i1 = runs(end, 2);
pLen = round((1 / freq) / Ts);
nAvail = floor((i1 - i0 + 1) / pLen);
if nAvail < 2
    error('air:M3:NoSearchWindow', ...
        'last search run shorter than two dither periods');
end
win = (i1 + 1) - nAvail * pLen : i1;   % trailing full periods only
idx = reshape(win, pLen, nAvail);
pm = mean(center(idx), 1);             % period means over search samples
pe = center(idx(pLen, :));             % period-end centers
m = mean(pm);
dist = abs(pe(:).');                    % force a row: pe keeps the column
reg = diff(dist);                       % orientation of the source vector
r = struct('converged', abs(m - 1.0) <= tolDist, ...
    'periodMean', m, 'monotonic', all(reg <= tolMono), ...
    'maxRegression', max([0, reg]), 'nPeriods', nAvail, ...
    'periodMeans', pm, 'periodEndDist', dist);
end

function runs = searchRuns(isSearch)
s = isSearch(:);
padded = [false; s; false];
d = diff(padded);
runs = [find(d == 1), find(d == -1) - 1];
if isempty(runs)
    runs = zeros(0, 2);
end
end
