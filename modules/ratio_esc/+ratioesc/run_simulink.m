function [log,file] = run_simulink(c,data)
if nargin<2, data=ratioesc.make_inputs(c); end
[file,mdl]=build_simulink(c,data);
load_system(file); cleanup=onCleanup(@()close_system(mdl,0)); %#ok<NASGU>
output=sim(mdl);
matrix=double(output.ratio_log);
names={'time','ratio','reference','center','truePower','measuredPower',...
    'dither','highpass','demodulated','gradient','rateLimited','frozen'};
log=array2table(matrix,'VariableNames',names);
log.optimum=data.optimum; log.offlinePower=ones(height(log),1);
end
