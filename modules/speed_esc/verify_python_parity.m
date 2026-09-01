function results = verify_python_parity()
root=fileparts(mfilename('fullpath')); folder=fullfile(root,'tests','fixtures');
files=dir(fullfile(folder,'v*.csv')); assert(numel(files)==14,'speedesc:Fixtures','Expected 14 original-Python fixtures.');
rows=cell(numel(files),3);
for k=1:numel(files)
    parts=regexp(files(k).name,'v(\d)_(debug|cubic)_([\d.]+)\.csv','tokens','once');
    version=str2double(parts{1}); initial=str2double(parts{3}); curve=parts{2};
    expected=readtable(fullfile(folder,files(k).name));
    actual=speedesc.python_reference(version,curve,initial,expected.noise);
    error=max(abs(actual{:,:}-expected{:,actual.Properties.VariableNames}),[],'all');
    rows(k,:)={files(k).name,error,error<1e-6};
end
results=cell2table(rows,'VariableNames',{'PythonCase','MaximumAbsoluteDifference','Passed'});
out=fullfile(root,'results'); if ~exist(out,'dir'), mkdir(out); end
writetable(results,fullfile(out,'python_parity.csv')); disp(results);
assert(all(results.Passed),'speedesc:Parity','Literal port differs from supplied Python.');
end
