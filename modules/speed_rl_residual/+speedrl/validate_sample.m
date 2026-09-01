function validate_sample(x)
required={'time_s','ground_velocity_ne_mps','wind_velocity_ne_mps','wind_sample_time_s',...
    'power_w','power_sample_time_s','voltage_v','soc','path_phase_rad',...
    'path_tangent_ne','radial_error_m','velocity_valid','wind_valid','power_valid'};
assert(isstruct(x) && all(isfield(x,required)),'speedrl:Sample','Adapter sample schema mismatch.');
validateattributes(x.time_s,{'double'},{'scalar','real','finite','nonnegative'});
validateattributes(x.ground_velocity_ne_mps,{'double'},{'size',[2 1],'real'});
validateattributes(x.wind_velocity_ne_mps,{'double'},{'size',[2 1],'real'});
validateattributes(x.path_tangent_ne,{'double'},{'size',[2 1],'real','finite'});
assert(abs(norm(x.path_tangent_ne)-1)<1e-8,'speedrl:Sample','Path tangent must be a unit vector.');
validateattributes(x.path_phase_rad,{'double'},{'scalar','real','finite'});
validateattributes(x.radial_error_m,{'double'},{'scalar','real','finite'});
for name={'velocity_valid','wind_valid','power_valid'}
    assert(islogical(x.(name{1})) && isscalar(x.(name{1})),'speedrl:Sample','Validity flags must be logical scalars.');
end
if x.velocity_valid, assert(all(isfinite(x.ground_velocity_ne_mps)),'speedrl:Sample','Valid velocity must be finite.'); end
if x.wind_valid
    assert(all(isfinite(x.wind_velocity_ne_mps)) && isfinite(x.wind_sample_time_s) && ...
        x.wind_sample_time_s<=x.time_s+1e-9,'speedrl:Sample','Valid wind has invalid values or timestamp.');
end
if x.power_valid
    assert(isfinite(x.power_w) && x.power_w>0 && isfinite(x.power_sample_time_s) && ...
        x.power_sample_time_s<=x.time_s+1e-9,'speedrl:Sample','Valid power has invalid values or timestamp.');
end
end
