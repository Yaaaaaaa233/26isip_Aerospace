function L = run_simulink(c,data)
if nargin<2, data=speedesc.make_inputs(c); end
[file,model]=build_speed_simulink(c,data); load_system(file);
cleanup=onCleanup(@()close_system(model,0)); %#ok<NASGU>
out=sim(model); assert(isempty(out.ErrorMessage),'speedesc:Simulation','%s',out.ErrorMessage);
L=array2table(out.speed_log,'VariableNames',speedesc.log_names());
end
