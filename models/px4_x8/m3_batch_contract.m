function c = m3_batch_contract()
%M3_BATCH_CONTRACT The ONE fixed M3 batch contract (rules v1.7 section 2
%   rule 8 pattern; round-2 independent report M3-R2-F4 closure). The
%   staged manifest written by m3_batch_init is EVIDENCE, never authority:
%   every segment entry and the aggregate re-assert the manifest against
%   THIS source-level contract, so a coordinated tamper (raising the
%   attempt cap, dropping or duplicating a segment, editing the declared
%   arm lists) cannot forge a PASS.
%
%   What is fixed literally:
%     - the 14-arm frozen matrix (ids and their order define uniqueness);
%     - the attempt cap (maxAttempts = 3, kept in lockstep with
%       tools/run_m3_batch.ps1 -MaxAttempts);
%     - the reproducibility rule: M3-N5 and M3-R1 must share ONE segment
%       (same MATLAB process) so the sample-exact repro difference is a
%       same-session property.
%   What is parameterized (per the round-2 report's explicit request: the
%   repair must not hardcode "exactly five segments"): the SEGMENTATION --
%   any grouping of the 14 arms into non-empty segments that covers each
%   arm exactly once and co-segments the repro pair is a valid batch
%   layout. The canonical layout below is the default; the aggregate
%   accepts any manifest whose layout satisfies these rules (the
%   alternative-layout positive control in the verifier exercises this).
c.arms = { ...
    'M3-N1', 'M3-N2', 'M3-N3', 'M3-N4', 'M3-N5', ...
    'M3-D1', 'M3-D2', 'M3-R1', ...
    'B0-N', 'B0-D', 'B1-N1', 'B1-N2', 'B2-N1', 'B2-N2'};
c.maxAttempts = 3;
c.reproPair = {'M3-N5', 'M3-R1'};
c.segments = { ...
    {'B0-N', 'B0-D', 'B1-N1', 'B1-N2', 'B2-N1', 'B2-N2'}; ...
    {'M3-N1', 'M3-N2'}; ...
    {'M3-N3', 'M3-N4'}; ...
    {'M3-N5', 'M3-R1'}; ...
    {'M3-D1', 'M3-D2'}};
% verifier stages share the same staged bookkeeping (done markers +
% attempt counters); the driver's canonical stage order is fixed
c.verifierStages = {'vunit', 'vnegative', 'vaggregate', 'vreport'};
% paired gates (unchanged from the round-2 aggregate; the aggregate
% recomputes them from the per-arm archives)
c.nominalArms = {'M3-N1', 'M3-N2', 'M3-N3', 'M3-N4', 'M3-N5'};
c.etaArms = {'M3-N1', 'M3-N2', 'M3-N3', 'M3-N4', 'M3-N5', ...
    'M3-D1', 'M3-D2', 'B2-N1', 'B2-N2'};
c.gateMap = {'M3-N1', 'B1-N1', 'B2-N1'; ...
    'M3-N2', 'B1-N1', 'B2-N2'; ...
    'M3-N3', 'B1-N2', 'B2-N1'; ...
    'M3-N4', 'B1-N2', 'B2-N2'};
c.vPairs = {'M3-N1', 'B1-N1'; 'M3-N2', 'B1-N1'; ...
    'M3-N3', 'B1-N2'; 'M3-N4', 'B1-N2'};
c.gateWin = [144.0, 240.0];
c.notWorse = 0.5;
c.vTrkTol = 0.05;
end
