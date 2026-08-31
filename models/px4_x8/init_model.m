function model = init_model(model)
%INIT_MODEL Add the X8 model directory to the path and load a named model.
%   INIT_MODEL() loads the immutable baseline air.slx.
%   INIT_MODEL('air_spare') loads the M0-A observability development copy.

if nargin < 1 || isempty(model)
    model = 'air';
end
model = char(string(model));
modelDir = fileparts(mfilename('fullpath'));
modelFile = fullfile(modelDir, [model '.slx']);
assert(isfile(modelFile), 'px4x8:ModelNotFound', ...
    'Model file not found: %s', modelFile);
addpath(modelDir);
if ~bdIsLoaded(model)
    load_system(modelFile);
end
end
