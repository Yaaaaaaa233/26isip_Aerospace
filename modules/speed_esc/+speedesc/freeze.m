function s = freeze(s,enabled)
validateattributes(enabled,{'logical'},{'scalar'}); s.frozen=enabled;
end
