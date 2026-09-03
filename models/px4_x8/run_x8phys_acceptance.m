function result = run_x8phys_acceptance()
%RUN_X8PHYS_ACCEPTANCE Run the MATLAB-side X8 object and platform contract tests.
% This entry point does not open, update, or save any Simulink model.
modelDir = fileparts(mfilename('fullpath'));
addpath(modelDir);
objectResult = test_x8phys();
platformResult = test_x8phys_platform();
result = struct('passed',logical(objectResult.pass && platformResult.pass), ...
    'object',objectResult,'platform',platformResult);
assert(result.passed,'x8phys:Acceptance','X8PHYS acceptance failed.');
fprintf('X8PHYS acceptance PASS: object + platform adapter\n');
end
