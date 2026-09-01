function adapter = make_synthetic_adapter()
%MAKE_SYNTHETIC_ADAPTER Replaceable plant/disturbance/sensor boundary.
adapter=struct('name','synthetic_v1','reset',@speedrl.synthetic_reset,...
    'step',@speedrl.synthetic_step);
end
