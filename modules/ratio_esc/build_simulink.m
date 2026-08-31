function [file,mdl] = build_simulink(c,data)
%BUILD_SIMULINK Native discrete blocks expose the complete ESC signal path.
if nargin<1, c=ratioesc.config(); end
assert(any(strcmp(c.stage,{'esc','dither'})),'ratioesc:SimulinkStage',...
    'This model expands stages C/D. Use ratioesc.run for stages A/B/E.');
if nargin<2, data=ratioesc.make_inputs(c); end
root=fileparts(mfilename('fullpath')); out=fullfile(root,'models');
if ~exist(out,'dir'), mkdir(out); end
mdl='ratio_esc_closed_loop'; file=fullfile(out,[mdl '.slx']);
if bdIsLoaded(mdl), close_system(mdl,0); end
load_system('simulink'); new_system(mdl);
set_param(mdl,'Solver','FixedStepDiscrete','FixedStep',num2str(c.Ts,17),...
    'StopTime',num2str(c.duration-c.Ts,17),'ReturnWorkspaceOutputs','on');
w=get_param(mdl,'ModelWorkspace');
assignin(w,'noise_input',[data.time data.noise]);
assignin(w,'optimum_input',[data.time data.optimum]);
assignin(w,'ratio_configuration',c);
initialPower=ratioesc.power_map(c.initialRatio,data.optimum(1),c);
initialMeasurement=initialPower+data.noise(1);
add(mdl,'Clock','simulink/Sources/Clock',[30 25 60 50]);
add(mdl,'ESC','built-in/Subsystem',[110 110 290 230]);
make_esc([mdl '/ESC'],c,initialMeasurement);
add(mdl,'Actuator_response','built-in/Subsystem',[360 110 530 200]);
make_plant([mdl '/Actuator_response'],c);
add(mdl,'Hidden_power_map','built-in/Subsystem',[600 110 780 200]);
make_map([mdl '/Hidden_power_map'],c);
add(mdl,'Measurement','built-in/Subsystem',[600 295 780 380]);
make_measurement([mdl '/Measurement'],c,initialPower);
add(mdl,'Private_optimum','simulink/Sources/From Workspace',[420 30 550 65],...
    'VariableName','optimum_input','Interpolate','off','OutputAfterFinalValue','Holding final value');
add(mdl,'Measurement_noise','simulink/Sources/From Workspace',[825 295 960 330],...
    'VariableName','noise_input','Interpolate','off','OutputAfterFinalValue','Holding final value');
line(mdl,'Clock/1','ESC/2'); line(mdl,'ESC/1','Actuator_response/1');
line(mdl,'Actuator_response/1','Hidden_power_map/1');
line(mdl,'Private_optimum/1','Hidden_power_map/2');
line(mdl,'Hidden_power_map/1','Measurement/1');
line(mdl,'Measurement_noise/1','Measurement/2');
line(mdl,'Measurement/1','ESC/1');
add(mdl,'Log_mux','simulink/Signal Routing/Mux',[1040 25 1045 390],'Inputs','12');
sources={'Clock/1','Actuator_response/1','ESC/1','ESC/2','Hidden_power_map/1',...
    'Measurement/1','ESC/3','ESC/4','ESC/5','ESC/6','ESC/7','Zero/1'};
add(mdl,'Zero','simulink/Sources/Constant',[930 390 960 415],'Value','0');
for k=1:12, line(mdl,sources{k},sprintf('Log_mux/%d',k)); end
add(mdl,'Run_log','simulink/Sinks/To Workspace',[1100 170 1200 205],...
    'VariableName','ratio_log','SaveFormat','Array','MaxDataPoints','inf');
line(mdl,'Log_mux/1','Run_log/1');
note=Simulink.Annotation(mdl,['ONLINE ESC | ratio = upper / lower' newline ...
    'Constant-thrust proxy only; no hardware, calibrated power or yaw validation.' newline ...
    'Open ESC to inspect HPF, demodulation, LPF, descent and reference limiting.' newline ...
    'Healthy-sample simulation. Freeze/invalid-sample recovery is tested in the MATLAB controller API.']);
note.Position=[30 440];
save_system(mdl,file); close_system(mdl,0);
end

function make_esc(s,c,initialMeasurement)
add(s,'Power','simulink/Sources/In1',[15 95 45 115],'Port','1');
add(s,'Time','simulink/Sources/In1',[15 15 45 35],'Port','2');
add(s,'Omega','simulink/Math Operations/Gain',[75 10 115 40],'Gain',v(2*pi*c.frequency));
add(s,'Sin','simulink/Math Operations/Trigonometric Function',[145 10 180 40],'Operator','sin');
line(s,'Time/1','Omega/1'); line(s,'Omega/1','Sin/1');
add(s,'Bias_memory','simulink/Discrete/Unit Delay',[80 185 140 215],...
    'SampleTime',v(c.Ts),'InitialCondition',v(initialMeasurement));
add(s,'Highpass','simulink/Math Operations/Sum',[185 88 210 125],'Inputs','+-');
line(s,'Power/1','Highpass/1'); line(s,'Bias_memory/1','Highpass/2');
add(s,'Bias_update_gain','simulink/Math Operations/Gain',[190 175 235 210],'Gain',v(1-exp(-c.hpOmega*c.Ts)));
add(s,'Bias_update','simulink/Math Operations/Sum',[275 180 300 210],'Inputs','++');
line(s,'Highpass/1','Bias_update_gain/1'); line(s,'Bias_memory/1','Bias_update/1');
line(s,'Bias_update_gain/1','Bias_update/2'); line(s,'Bias_update/1','Bias_memory/1');
add(s,'Demod_product','simulink/Math Operations/Product',[255 78 285 115]);
add(s,'Demod_scale','simulink/Math Operations/Gain',[315 78 370 115],'Gain',v(2/c.amplitude));
line(s,'Highpass/1','Demod_product/1'); line(s,'Sin/1','Demod_product/2'); line(s,'Demod_product/1','Demod_scale/1');
add(s,'Gradient_memory','simulink/Discrete/Unit Delay',[390 185 450 215],...
    'SampleTime',v(c.Ts),'InitialCondition','0');
add(s,'Gradient_error','simulink/Math Operations/Sum',[405 82 430 118],'Inputs','+-');
add(s,'LPF_gain','simulink/Math Operations/Gain',[465 80 510 115],'Gain',v(1-exp(-c.lpOmega*c.Ts)));
add(s,'Gradient_update','simulink/Math Operations/Sum',[550 80 575 115],'Inputs','++');
line(s,'Demod_scale/1','Gradient_error/1'); line(s,'Gradient_memory/1','Gradient_error/2');
line(s,'Gradient_error/1','LPF_gain/1'); line(s,'Gradient_memory/1','Gradient_update/1');
line(s,'LPF_gain/1','Gradient_update/2'); line(s,'Gradient_update/1','Gradient_memory/1');
center=min(max(c.initialRatio,c.lower+c.amplitude),c.upper-c.amplitude);
add(s,'Center_memory','simulink/Discrete/Unit Delay',[635 185 695 215],...
    'SampleTime',v(c.Ts),'InitialCondition',v(center));
gain=-c.gain*c.Ts*double(strcmp(c.stage,'esc'));
add(s,'Descent','simulink/Math Operations/Gain',[610 80 660 115],'Gain',v(gain));
add(s,'Center_update','simulink/Math Operations/Sum',[710 80 735 115],'Inputs','++');
add(s,'Center_projection','simulink/Discontinuities/Saturation',[770 80 830 115],...
    'LowerLimit',v(c.lower+c.amplitude),'UpperLimit',v(c.upper-c.amplitude));
line(s,'Gradient_update/1','Descent/1'); line(s,'Descent/1','Center_update/1');
line(s,'Center_memory/1','Center_update/2'); line(s,'Center_update/1','Center_projection/1');
line(s,'Center_projection/1','Center_memory/1');
add(s,'Dither_amplitude','simulink/Math Operations/Gain',[620 10 680 45],'Gain',v(c.amplitude));
add(s,'Add_dither','simulink/Math Operations/Sum',[870 80 895 115],'Inputs','++');
line(s,'Sin/1','Dither_amplitude/1'); line(s,'Dither_amplitude/1','Add_dither/1'); line(s,'Center_projection/1','Add_dither/2');
add(s,'Bounds','simulink/Discontinuities/Saturation',[930 80 990 115],...
    'LowerLimit',v(c.lower),'UpperLimit',v(c.upper)); line(s,'Add_dither/1','Bounds/1');
add(s,'Reference_memory','simulink/Discrete/Unit Delay',[1010 185 1070 215],...
    'SampleTime',v(c.Ts),'InitialCondition',v(c.initialRatio));
add(s,'Reference_delta','simulink/Math Operations/Sum',[1030 80 1055 115],'Inputs','+-');
add(s,'Slew_limit','simulink/Discontinuities/Saturation',[1100 80 1160 115],...
    'LowerLimit',v(-c.rateLimit*c.Ts),'UpperLimit',v(c.rateLimit*c.Ts));
add(s,'Applied_reference','simulink/Math Operations/Sum',[1200 80 1225 115],'Inputs','++');
line(s,'Bounds/1','Reference_delta/1'); line(s,'Reference_memory/1','Reference_delta/2');
line(s,'Reference_delta/1','Slew_limit/1'); line(s,'Slew_limit/1','Applied_reference/1');
line(s,'Reference_memory/1','Applied_reference/2'); line(s,'Applied_reference/1','Reference_memory/1');
add(s,'Clipping_error','simulink/Math Operations/Sum',[1100 275 1125 305],'Inputs','+-');
add(s,'Abs_error','simulink/Math Operations/Abs',[1160 275 1190 305]);
add(s,'Was_limited','simulink/Logic and Bit Operations/Compare To Constant',[1220 275 1285 305],...
    'relop','>','const','1e-12');
line(s,'Add_dither/1','Clipping_error/1'); line(s,'Applied_reference/1','Clipping_error/2');
line(s,'Clipping_error/1','Abs_error/1'); line(s,'Abs_error/1','Was_limited/1');
add(s,'Limit_flag_double','simulink/Signal Attributes/Data Type Conversion',[1300 275 1350 305],...
    'OutDataTypeStr','double');
line(s,'Was_limited/1','Limit_flag_double/1');
outputs={'Applied_reference','Center_projection','Dither_amplitude','Highpass','Demod_scale','Gradient_update','Limit_flag_double'};
for k=1:7
    add(s,['Out' num2str(k)],'simulink/Sinks/Out1',[1370 30+50*k 1400 50+50*k],'Port',num2str(k));
    line(s,[outputs{k} '/1'],['Out' num2str(k) '/1']);
end
end

function make_plant(s,c)
add(s,'Reference','simulink/Sources/In1',[20 50 50 70]);
add(s,'State','simulink/Discrete/Unit Delay',[270 125 335 160],...
    'SampleTime',v(c.Ts),'InitialCondition',v(c.initialRatio));
r=exp(-c.Ts/c.tau);
add(s,'Input_gain','simulink/Math Operations/Gain',[85 40 145 75],'Gain',v(1-r));
add(s,'State_gain','simulink/Math Operations/Gain',[85 130 145 165],'Gain',v(r));
add(s,'Next_state','simulink/Math Operations/Sum',[205 45 230 80],'Inputs','++');
add(s,'Actual_ratio','simulink/Sinks/Out1',[380 130 410 150]);
line(s,'Reference/1','Input_gain/1'); line(s,'State/1','State_gain/1');
line(s,'Input_gain/1','Next_state/1'); line(s,'State_gain/1','Next_state/2');
line(s,'Next_state/1','State/1'); line(s,'State/1','Actual_ratio/1');
end

function make_map(s,c)
add(s,'Actual_ratio','simulink/Sources/In1',[20 40 50 60],'Port','1');
add(s,'Private_optimum','simulink/Sources/In1',[20 110 50 130],'Port','2');
add(s,'Difference','simulink/Math Operations/Sum',[90 50 120 90],'Inputs','+-');
add(s,'Square','simulink/Math Operations/Math Function',[155 50 195 90],'Operator','square');
add(s,'Curvature','simulink/Math Operations/Gain',[230 50 290 90],'Gain',v(c.curvature));
add(s,'Base_power','simulink/Math Operations/Bias',[325 50 380 90],'Bias','1');
add(s,'True_power','simulink/Sinks/Out1',[425 60 455 80]);
line(s,'Actual_ratio/1','Difference/1'); line(s,'Private_optimum/1','Difference/2');
line(s,'Difference/1','Square/1'); line(s,'Square/1','Curvature/1');
line(s,'Curvature/1','Base_power/1'); line(s,'Base_power/1','True_power/1');
end

function make_measurement(s,c,initialPower)
add(s,'Power','simulink/Sources/In1',[20 40 50 60],'Port','1');
add(s,'Noise','simulink/Sources/In1',[140 140 170 160],'Port','2');
add(s,'Add_noise','simulink/Math Operations/Sum',[240 50 270 90],'Inputs','++');
if c.delay>0
    add(s,'Transport_delay','simulink/Discrete/Delay',[90 40 180 80],...
        'DelayLength',num2str(round(c.delay/c.Ts)),'InitialCondition',v(initialPower),...
        'SampleTime',v(c.Ts));
    line(s,'Power/1','Transport_delay/1'); line(s,'Transport_delay/1','Add_noise/1');
else
    line(s,'Power/1','Add_noise/1');
end
add(s,'Measured_power','simulink/Sinks/Out1',[320 60 350 80]);
line(s,'Noise/1','Add_noise/2'); line(s,'Add_noise/1','Measured_power/1');
end

function add(parent,name,library,position,varargin)
add_block(library,[parent '/' name],'Position',position,varargin{:});
end
function line(parent,source,destination)
add_line(parent,source,destination,'autorouting','on');
end
function text=v(x)
text=num2str(x,17);
end
