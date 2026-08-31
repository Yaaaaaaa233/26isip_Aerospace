function export_model_diagrams()
root=fileparts(mfilename('fullpath')); folder=fullfile(root,'results','model_diagrams');
if ~exist(folder,'dir'), mkdir(folder); end
[file,mdl]=build_simulink(ratioesc.config()); load_system(file);
cleanup=onCleanup(@()close_system(mdl,0)); %#ok<NASGU>
print(['-s' mdl],'-dpng','-r150',fullfile(folder,'closed_loop.png'));
print(['-s' mdl '/ESC'],'-dpng','-r150',fullfile(folder,'esc_internals.png'));
end
