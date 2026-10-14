function file = build_air_quad(cfg,T,cmd)
%BUILD_AIR_QUAD 程序化生成 air_quad.slx 薄包装(P4/B2, 惯例同 ratio_esc/build_simulink)。
% 结构: In(v_ref/wind/reset) -> air_quad_tick(MATLAB 权威链一步) -> 记录 + 遥测组帧
%   接口位(0xF2 副帧) + Out(估计功率, SITL 插槽)。模型内无任何自有动力学/功率模型。
% cfg: quad_sim 配置(默认 b40 工作簿口径, C9); T: 仿真时长 s;
% cmd: struct('t',..,'vref',..,'wind',Nx3,'reset',..) 激励(注入模型工作区)。
% 输出: models/plane_quad/models/air_quad.slx
if nargin < 1 || isempty(cfg), cfg = quad_sim.config(quad_sim.baseline('b40')); end
if nargin < 2 || isempty(T), T = 20; end
if nargin < 3 || isempty(cmd)
    cmd = struct('t',(0:cfg.sample_time_s:T)', ...
        'vref',zeros(round(T/cfg.sample_time_s)+1,1), ...
        'wind',zeros(round(T/cfg.sample_time_s)+1,3), ...
        'reset',zeros(round(T/cfg.sample_time_s)+1,1));
end
root = fileparts(mfilename('fullpath'));
out = fullfile(root,'models');
if ~exist(out,'dir'), mkdir(out); end
mdl = 'air_quad'; file = fullfile(out,[mdl '.slx']);
if bdIsLoaded(mdl), close_system(mdl,0); end
load_system('simulink'); new_system(mdl);
set_param(mdl,'Solver','FixedStepDiscrete','FixedStep',num2str(cfg.sample_time_s,17), ...
    'StopTime',num2str(T,17),'ReturnWorkspaceOutputs','on');
w = get_param(mdl,'ModelWorkspace');
assignin(w,'air_quad_config',cfg);
assignin(w,'cmd_vref',[cmd.t cmd.vref]);
assignin(w,'cmd_wind',[cmd.t cmd.wind]);
assignin(w,'cmd_reset',[cmd.t cmd.reset]);
add(mdl,'V_ref','simulink/Sources/From Workspace',[20 25 120 55], ...
    'VariableName','cmd_vref','Interpolate','off', ...
    'OutputAfterFinalValue','Holding final value');
add(mdl,'Wind','simulink/Sources/From Workspace',[20 95 120 125], ...
    'VariableName','cmd_wind','Interpolate','off', ...
    'OutputAfterFinalValue','Holding final value');
add(mdl,'Reset','simulink/Sources/From Workspace',[20 165 120 195], ...
    'VariableName','cmd_reset','Interpolate','off', ...
    'OutputAfterFinalValue','Holding final value');
add(mdl,'Pack_in','simulink/Signal Routing/Vector Concatenate', ...
    [160 60 165 190],'NumInputs','3');   % [v_ref; wind(3); reset] = 5 宽
line(mdl,'V_ref/1','Pack_in/1');
line(mdl,'Wind/1','Pack_in/2');
line(mdl,'Reset/1','Pack_in/3');
add(mdl,'Plant','simulink/User-Defined Functions/Interpreted MATLAB Function', ...
    [220 90 360 160],'MATLABFcn','air_quad_tick','OutputDimensions','[8]');
line(mdl,'Pack_in/1','Plant/1');
add(mdl,'Split','simulink/Signal Routing/Demux',[390 90 395 165],'Outputs','8');
line(mdl,'Plant/1','Split/1');
add(mdl,'Log_mux','simulink/Signal Routing/Mux',[420 25 425 250],'Inputs','8');
for k = 1:8
    line(mdl,sprintf('Split/%d',k),sprintf('Log_mux/%d',k));
end
add(mdl,'Run_log','simulink/Sinks/To Workspace',[500 100 620 135], ...
    'VariableName','air_quad_log','SaveFormat','Array','MaxDataPoints','inf');
line(mdl,'Log_mux/1','Run_log/1');
% ---- 遥测组帧接口位(0xF2 副帧2): [V; I; th1; th2; alarm=0] ----
add(mdl,'Alarm0','simulink/Sources/Constant',[420 300 450 325],'Value','0');
add(mdl,'Tel_mux','simulink/Signal Routing/Mux',[520 260 525 355],'Inputs','5');
line(mdl,'Split/2','Tel_mux/1'); line(mdl,'Split/3','Tel_mux/2');
line(mdl,'Split/5','Tel_mux/3'); line(mdl,'Split/6','Tel_mux/4');
line(mdl,'Alarm0/1','Tel_mux/5');
add(mdl,'Telemetry','simulink/User-Defined Functions/Interpreted MATLAB Function', ...
    [580 275 740 345],'MATLABFcn','air_quad_telemetry_pack','OutputDimensions','[24]');
line(mdl,'Tel_mux/1','Telemetry/1');
add(mdl,'Tel_log','simulink/Sinks/To Workspace',[800 285 920 320], ...
    'VariableName','telemetry_bytes','SaveFormat','Array','MaxDataPoints','inf');
line(mdl,'Telemetry/1','Tel_log/1');
% ---- SITL 插槽出口: 估计功率 ----
add(mdl,'Est_power','simulink/Sinks/Out1',[500 380 540 400],'Port','1');
line(mdl,'Split/1','Est_power/1');
note = Simulink.Annotation(mdl, ['air_quad thin wrapper (P4/B2) | MATLAB chain is the ' ...
    'single authority: air_quad_tick -> quad_sim.ctrl/step, no model dynamics here.' newline ...
    'Caliber: workbook_baseline/quad_placeholder (C9, non-citable). Telemetry = ' ...
    'COMMERCIAL-AERO FC protocol 0xF2 subframe interface SLOT (quantization only, ' ...
    'no transport/CRC distribution). Existing .slx untouched.']);
note.Position = [20 420];
save_system(mdl,file); close_system(mdl,0);
end
function add(mdl,name,lib,pos,varargin)
add_block(lib,[mdl '/' name],'Position',pos,varargin{:});
end
function line(mdl,src,dst)
add_line(mdl,src,dst,'autorouting','on');
end
