function result = test_m0c_installer_dirty_guard
%TEST_M0C_INSTALLER_DIRTY_GUARD prove the installer preserves unsaved work.
%   The installed air_spare snapshot is marked dirty in memory. The installer
%   must reject it before closing or saving the model, and the on-disk SLX hash
%   must remain unchanged.

model = 'air_spare';
modelDir = fileparts(mfilename('fullpath'));
modelFile = fullfile(modelDir, [model '.slx']);
assert(~bdIsLoaded(model), 'air:M0C:DirtyGuardPrecondition', ...
    'Close air_spare before running this regression test.');

hashBefore = sha256File(modelFile);
load_system(modelFile);
cleanup = onCleanup(@() closeIfLoaded(model)); %#ok<NASGU>
set_param(model, 'Dirty', 'on');

caught = false;
try
    run(fullfile(modelDir, 'add_air_m0c_esc.m'));
catch err
    caught = strcmp(err.identifier, 'air:M0C:DirtyModel');
    if ~caught
        rethrow(err);
    end
end

assert(caught, 'air:M0C:DirtyGuardMissing', ...
    'Installer did not reject a dirty model.');
assert(bdIsLoaded(model) && strcmp(get_param(model, 'Dirty'), 'on'), ...
    'air:M0C:DirtyGuardClosedModel', ...
    'Installer closed or cleared the dirty in-memory model.');
assert(strcmp(hashBefore, sha256File(modelFile)), ...
    'air:M0C:DirtyGuardDiskChanged', ...
    'Installer changed air_spare.slx on disk after rejecting the dirty model.');

result = struct('pass', true, 'model', model, 'sha256', hashBefore);
fprintf('M0-C INSTALLER DIRTY-GUARD PASS: %s\n', model);
end

function hash = sha256File(path)
fid = fopen(path, 'rb');
assert(fid ~= -1, 'air:M0C:DirtyGuardRead', 'Cannot open %s.', path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, '*uint8');
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(bytes);
digest = typecast(md.digest(), 'uint8');
hash = lower(reshape(dec2hex(digest, 2).', 1, []));
end

function closeIfLoaded(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end
