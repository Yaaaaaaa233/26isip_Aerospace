function m3_validate_channels(modeV, modeEta, arb)
%M3_VALIDATE_CHANNELS Trial-entry cross-channel legality check (M3 doc
%   sections 2.4/3.3). The two adapters are independent blocks that
%   cannot see each other's mode, so single-sided m3 and disabled
%   arbitration are rejected HERE before any run starts; the adapters
%   additionally self-check their own half at init (m3_schedule fails
%   loud on enable ~= 'on').
known = {'fixed', 'esc', 'm3'};
if ~any(strcmp(modeV, known))
    error('air:M3:BadMode', 'unknown v-channel mode %s', modeV);
end
if ~any(strcmp(modeEta, known))
    error('air:M3:BadMode', 'unknown eta-channel mode %s', modeEta);
end
isM3V = strcmp(modeV, 'm3');
isM3E = strcmp(modeEta, 'm3');
if isM3V ~= isM3E
    error('air:M3:SingleSided', ...
        ['single-sided m3 (v=%s, eta=%s): the other channel has no ' ...
         'arbitration semantics, silent concurrency is forbidden ' ...
         '(M3 doc 2.4)'], modeV, modeEta);
end
if isM3V
    % full structural + enable validation via the schedule itself; with
    % neither channel in m3 the arbitration global is never read, so
    % junk left in it cannot disturb fixed/esc runs (bit-exactness)
    m3_schedule(0.0, arb);
end
end
