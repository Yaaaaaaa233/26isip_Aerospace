function roles = m3_schedule(t, cfg)
%M3_SCHEDULE M3 time-division arbitration schedule (pure function of time).
%   roles = m3_schedule(t, cfg) with wall-clock time t and arbitration
%   config cfg returns roles = struct('v', 'search'|'hold',
%   'eta', 'search'|'hold'). The slot sequence is [firstSlot, other] with
%   lengths [slotFirst, slotOther], cycling from t = 0; exactly one
%   channel searches at any t (docs/interfaces/M3_V_ETA_COORDINATION.md
%   section 2.2). Switching is by wall clock only -- valid-based
%   deferral is deliberately excluded in V1 so both adapters reach the
%   same decision from the same pure function and the plan is exactly
%   reconstructible offline.
%
%   Fail loud (M3 doc section 2.4): this function is only ever called
%   from mode = 'm3', so enable ~= 'on' is an undefined combination and a
%   hard error. Unknown or missing fields, non-positive or non-finite
%   slots and a bad firstSlot are rejected.

if ~isstruct(cfg)
    error('m3:schedule:BadConfig', 'cfg must be a struct');
end
want = {'enable', 'firstSlot', 'slotEta', 'slotV'};
got = fieldnames(cfg);
if ~isequal(sort(got(:)), sort(want(:)))
    error('m3:schedule:BadConfig', ...
        'cfg fields must be exactly {%s}, got {%s}', ...
        strjoin(sort(want), ','), strjoin(sort(got), ','));
end
en = cfg.enable;
if ~(ischar(en) || isstring(en)) || ~any(strcmp(char(en), {'on', 'off'}))
    error('m3:schedule:BadConfig', ...
        'enable must be ''on'' or ''off''');
end
if ~strcmp(char(en), 'on')
    error('m3:schedule:Disabled', ...
        ['mode=''m3'' with M3_ARB_PARAMS.enable=''off'' is undefined ' ...
         '(M3 doc 2.4); it must fail loud instead of silently running ' ...
         'concurrent searches']);
end
fs = cfg.firstSlot;
if ~(ischar(fs) || isstring(fs)) || ~any(strcmp(char(fs), {'v', 'eta'}))
    error('m3:schedule:BadConfig', ...
        'firstSlot must be ''v'' or ''eta''');
end
if ~isSlotOk(cfg.slotEta)
    error('m3:schedule:BadConfig', ...
        ['slotEta must be a positive finite scalar (a zero-length slot ' ...
         'would mean concurrent search, which the design forbids)']);
end
if ~isSlotOk(cfg.slotV)
    error('m3:schedule:BadConfig', ...
        ['slotV must be a positive finite scalar (a zero-length slot ' ...
         'would mean concurrent search, which the design forbids)']);
end
if ~isscalar(t) || ~isreal(t) || ~isfinite(t) || t < 0
    error('m3:schedule:BadTime', ...
        't must be a non-negative finite scalar');
end

if strcmp(char(fs), 'eta')
    slotFirst = cfg.slotEta;
    slotOther = cfg.slotV;
else
    slotFirst = cfg.slotV;
    slotOther = cfg.slotEta;
end
cycle = slotFirst + slotOther;
% 1e-9 guard mirrors the adapters' k = floor((t + 1e-9)/Ts) convention so
% a 1-ulp time jitter cannot flip a slot boundary
phase = mod(t + 1e-9, cycle);
if strcmp(char(fs), 'eta')
    if phase < slotFirst
        roles = struct('v', 'hold', 'eta', 'search');
    else
        roles = struct('v', 'search', 'eta', 'hold');
    end
else
    if phase < slotFirst
        roles = struct('v', 'search', 'eta', 'hold');
    else
        roles = struct('v', 'hold', 'eta', 'search');
    end
end
end

function ok = isSlotOk(x)
ok = isscalar(x) && isreal(x) && isfinite(x) && x > 0;
end
