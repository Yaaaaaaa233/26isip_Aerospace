function [file,model] = build_speed_simulink(c,data)
%BUILD_SPEED_SIMULINK Same estimator/reference kernels, explicit plant chain.
if nargin<1, c=speedesc.config(); end
if nargin<2, data=speedesc.make_inputs(c); end
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'models'); if ~exist(folder,'dir'), mkdir(folder); end
model='speed_esc_closed_loop'; file=fullfile(folder,[model '.slx']);
if bdIsLoaded(model), close_system(model,0); end
load_system('simulink'); new_system(model);
set_param(model,'Solver','FixedStepDiscrete','FixedStep',v(c.Ts),...
    'StopTime',v(c.duration-c.Ts),'ReturnWorkspaceOutputs','on',...
    'InitFcn','addpath(fileparts(fileparts(get_param(bdroot,''FileName''))));');
w=get_param(model,'ModelWorkspace'); assignin(w,'speed_configuration',c);
assignin(w,'private_optimum_input',[data.time data.optimum]);
assignin(w,'noise_input',[data.time data.noise]);
assignin(w,'valid_input',[data.time data.valid.*(1-data.freeze)]);
p=speedesc.controller_config(c); literal=struct_code(p);
add(model,'Clock','simulink/Sources/Clock',[30 30 60 55]);
add(model,'Reference_memory','simulink/Discrete/Unit Delay',[100 120 170 155],...
    'SampleTime',v(c.Ts),'InitialCondition',v(c.initialSpeed));
add(model,'Speed_response','built-in/Subsystem',[230 105 385 175]);
make_response([model '/Speed_response'],c);
add(model,'Power_proxy','built-in/Subsystem',[450 105 600 175]);
make_power([model '/Power_proxy'],c);
workspace(model,'Private_optimum','private_optimum_input',[240 20 390 55]);
workspace(model,'Noise_samples','noise_input',[445 245 585 280]);
workspace(model,'Measurement_valid','valid_input',[30 405 180 440]);
add(model,'Measurement','built-in/Subsystem',[655 190 835 295]);
make_measurement([model '/Measurement'],c,data);
estimate=sprintf(['function [hp,raw,g,ready,healthy] = estimate(J,paired_v,sample_time,now,valid)\n' ...
    '%%#codegen\npersistent s\np=%s;\nif isempty(s), s=speedesc.estimator_reset(p); end\n' ...
    '[s,d]=speedesc.estimate_step(s,J,paired_v,sample_time,now,logical(valid),p);\n' ...
    'hp=d.highpass; raw=d.rawGradient; g=d.gradient; ready=double(d.ready); healthy=double(d.healthy);\nend'],literal);
matlab_function(model,'Gradient_estimator',[890 175 1080 320],estimate);
reference=sprintf(['function [ref,center,dither,limited,frozen] = reference_update(g,ready,healthy,now)\n' ...
    '%%#codegen\npersistent s\np=%s;\nif isempty(s), s=speedesc.reference_reset(%s,p); end\n' ...
    '[ref,s,d]=speedesc.reference_step(s,g,logical(ready),logical(healthy),now,p);\n' ...
    'center=d.center; dither=d.dither; limited=double(d.limited); frozen=double(d.frozen);\nend'],literal,v(c.initialSpeed));
matlab_function(model,'Reference_update',[890 385 1080 500],reference);
connect(model,'Reference_memory/1','Speed_response/1');
connect(model,'Speed_response/1','Power_proxy/1'); connect(model,'Private_optimum/1','Power_proxy/2');
connect(model,'Power_proxy/1','Measurement/1'); connect(model,'Speed_response/1','Measurement/2');
connect(model,'Clock/1','Measurement/3'); connect(model,'Noise_samples/1','Measurement/4');
for k=1:3, connect(model,['Measurement/' num2str(k)],['Gradient_estimator/' num2str(k)]); end
connect(model,'Clock/1','Gradient_estimator/4'); connect(model,'Measurement_valid/1','Gradient_estimator/5');
connect(model,'Gradient_estimator/3','Reference_update/1');
connect(model,'Gradient_estimator/4','Reference_update/2');
connect(model,'Gradient_estimator/5','Reference_update/3');
connect(model,'Clock/1','Reference_update/4'); connect(model,'Reference_update/1','Reference_memory/1');
minimum=1; if strcmp(c.curve,'cubic'), minimum=c.minimumRatio; end
add(model,'Offline_minimum','simulink/Sources/Constant',[650 30 780 65],'Value',v(minimum));
add(model,'Log_mux','simulink/Signal Routing/Mux',[1160 20 1165 545],'Inputs','18');
sources={'Clock/1','Speed_response/1','Reference_memory/1','Reference_update/1',...
    'Reference_update/2','Power_proxy/1','Measurement/1','Measurement/2','Measurement/3',...
    'Gradient_estimator/1','Gradient_estimator/2','Gradient_estimator/3','Reference_update/3',...
    'Gradient_estimator/4','Reference_update/4','Reference_update/5','Private_optimum/1','Offline_minimum/1'};
for k=1:numel(sources), connect(model,sources{k},['Log_mux/' num2str(k)]); end
add(model,'Run_log','simulink/Sinks/To Workspace',[1230 250 1340 290],...
    'VariableName','speed_log','SaveFormat','Array','MaxDataPoints','inf');
connect(model,'Log_mux/1','Run_log/1');
note=Simulink.Annotation(model,['SPEED ESC | eta_omega fixed at 1 by assumption; NOT a flight model.' newline ...
    'Reference update -> last command -> speed response -> proxy power -> time-aligned feedback.' newline ...
    'Open Measurement: power, speed and sample timestamp share the same FIFO delay.' newline ...
    'Estimator and reference update use the same MATLAB kernels as speedesc.run.' newline ...
    'Private optimum and offline minimum are evaluator/plant-only signals.']);
note.Position=[30 570]; save_system(model,file); close_system(model,0);
end

function make_response(s,c)
add(s,'Last_reference','simulink/Sources/In1',[20 45 50 65]);
add(s,'Actual_speed','simulink/Sinks/Out1',[390 45 420 65]);
if c.version==1
    connect(s,'Last_reference/1','Actual_speed/1'); return
end
r=exp(-c.Ts/c.tau);
add(s,'Previous_speed','simulink/Discrete/Unit Delay',[90 135 170 170],...
    'SampleTime',v(c.Ts),'InitialCondition',v(c.initialSpeed));
add(s,'Reference_gain','simulink/Math Operations/Gain',[90 35 165 75],'Gain',v(1-r));
add(s,'Memory_gain','simulink/Math Operations/Gain',[200 130 275 170],'Gain',v(r));
add(s,'Response','simulink/Math Operations/Sum',[315 40 340 80],'Inputs','++');
connect(s,'Last_reference/1','Reference_gain/1'); connect(s,'Reference_gain/1','Response/1');
connect(s,'Previous_speed/1','Memory_gain/1'); connect(s,'Memory_gain/1','Response/2');
connect(s,'Response/1','Actual_speed/1'); connect(s,'Response/1','Previous_speed/1');
end

function make_power(s,c)
add(s,'Actual_speed','simulink/Sources/In1',[20 35 50 55],'Port','1');
add(s,'Hidden_optimum','simulink/Sources/In1',[20 95 50 115],'Port','2');
add(s,'Inputs','simulink/Signal Routing/Mux',[100 35 105 115],'Inputs','2');
if strcmp(c.curve,'debug'), expression='1+0.003*(u(1)-u(2))^2';
else, b=2*(1-c.minimumRatio); expression=sprintf('1-%s*(u(1)/u(2))^2+%s*(u(1)/u(2))^3',v(1.5*b),v(b)); end
add(s,'Proxy_curve','simulink/User-Defined Functions/Fcn',[155 45 350 100],'Expr',expression);
add(s,'True_normalized_power','simulink/Sinks/Out1',[405 60 435 80]);
connect(s,'Actual_speed/1','Inputs/1'); connect(s,'Hidden_optimum/1','Inputs/2');
connect(s,'Inputs/1','Proxy_curve/1'); connect(s,'Proxy_curve/1','True_normalized_power/1');
end

function make_measurement(s,c,data)
names={'True_power','Actual_speed','Sample_time','Standard_noise'};
for k=1:4, add(s,names{k},'simulink/Sources/In1',[20 30+65*k 50 50+65*k],'Port',num2str(k)); end
add(s,'Noise_scale','simulink/Math Operations/Gain',[90 280 145 315],'Gain',v(c.noiseSigma));
add(s,'Relative_noise','simulink/Math Operations/Bias',[180 280 230 315],'Bias','1');
add(s,'Measured_at_source','simulink/Math Operations/Product',[265 95 300 130]);
connect(s,'Standard_noise/1','Noise_scale/1'); connect(s,'Noise_scale/1','Relative_noise/1');
connect(s,'True_power/1','Measured_at_source/1'); connect(s,'Relative_noise/1','Measured_at_source/2');
sources={'Measured_at_source','Actual_speed','Sample_time'};
initial=[speedesc.power_map(c.initialSpeed,data.optimum(1),c)*(1+c.noiseSigma*data.noise(1)),c.initialSpeed,0];
for k=1:3
    out=['Aligned_' num2str(k)]; y=55+70*k;
    add(s,out,'simulink/Sinks/Out1',[535 y 565 y+20],'Port',num2str(k));
    if c.delay>0
        name=['Delay_' num2str(k)];
        add(s,name,'simulink/Discrete/Delay',[365 y-10 460 y+25],...
            'DelayLength',v(round(c.delay/c.Ts)),'InitialCondition',v(initial(k)),'SampleTime',v(c.Ts));
        connect(s,[sources{k} '/1'],[name '/1']); connect(s,[name '/1'],[out '/1']);
    else, connect(s,[sources{k} '/1'],[out '/1']); end
end
end

function matlab_function(parent,name,pos,script)
add(parent,name,'simulink/User-Defined Functions/MATLAB Function',pos);
root=sfroot; chart=root.find('-isa','Stateflow.EMChart','Path',[parent '/' name]); chart.Script=script;
end
function workspace(parent,name,variable,pos)
add(parent,name,'simulink/Sources/From Workspace',pos,'VariableName',variable,...
    'Interpolate','off','OutputAfterFinalValue','Holding final value');
end
function text=struct_code(p)
names=fieldnames(p); parts=cell(1,numel(names));
for k=1:numel(names), parts{k}=sprintf('''%s'',%s',names{k},v(p.(names{k}))); end
text=['struct(' strjoin(parts,',') ')'];
end
function add(parent,name,library,pos,varargin)
add_block(library,[parent '/' name],'Position',pos,varargin{:});
end
function connect(parent,from,to)
add_line(parent,from,to,'autorouting','on');
end
function s=v(x)
s=num2str(x,17);
end
