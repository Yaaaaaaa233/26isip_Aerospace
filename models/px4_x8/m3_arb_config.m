function cfg = m3_arb_config()
%M3_ARB_CONFIG M3 arbitration global merge (M3 doc section 2.4).
%   Single source of the M3_ARB_PARAMS defaults for both adapters, the
%   trial entry and the unit tests, so the two independent blocks cannot
%   diverge on defaults. Defaults leave arbitration DISABLED: with the
%   global absent, fixed/esc semantics are bit-identical to the pre-M3
%   behavior and mode = 'm3' fails loud in m3_schedule instead of
%   silently running concurrent searches.
global M3_ARB_PARAMS
cfg = struct('enable', 'off', 'firstSlot', 'eta', ...
    'slotEta', 64.0, 'slotV', 32.0);
if ~isempty(M3_ARB_PARAMS)
    f = fieldnames(M3_ARB_PARAMS);
    for k = 1:numel(f)
        cfg.(f{k}) = M3_ARB_PARAMS.(f{k});
    end
end
end
