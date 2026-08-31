function s = freeze(s,enabled)
%FREEZE Hold the last applied reference; restart estimation on release.
validateattributes(enabled,{'logical'},{'scalar'});
if s.frozen && ~enabled, s.reinitialize=true; end
s.frozen=enabled;
end
