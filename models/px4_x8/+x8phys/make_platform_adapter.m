function adapter = make_platform_adapter(c)
%X8PHYS.MAKE_PLATFORM_ADAPTER Function-handle boundary for air_spare data.
if nargin<1||isempty(c),c=x8phys.config();end
adapter=struct('name','x8phys_platform_v3','config',c, ...
    'reset',@(varargin)reset_adapter(c,varargin{:}), ...
    'step',@(state,platform,wind,dt)x8phys.platform_step(state,platform,wind,dt,c));
end

function [state,sample] = reset_adapter(c,initial)
if nargin < 2 || isempty(initial), initial=struct(); end
[state,truth]=x8phys.reset(c,initial);
[state,sample]=x8phys.platform_step(state, ...
    struct('motor_pwm_us',state.last_pwm_us), zeros(3,1), 0, c);
% Keep the reset call explicit so a future adapter can attach startup
% metadata without exposing object-only truth to the M0 consumer.
assert(sample.t == truth.time_s, 'x8phys:Platform', ...
    'Reset sample time is inconsistent with object state.');
end
