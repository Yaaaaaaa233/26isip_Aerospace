function f = m3_live_fingerprints()
%M3_LIVE_FINGERPRINTS Single source of the batch fingerprint set (rules
%   section 2 rule 5: every forensics point re-captures LIVE, never
%   copies). The SET of fingerprinted files is the one m3_batch_init
%   writes into the manifest and m3_aggregate_batch re-asserts: the two
%   aggregate/verifier consumers and the init must never drift apart, so
%   the list lives here. f.head is the live git HEAD (hard failure on any
%   capture problem -- no 'unknown' placeholder), f.sha the SHA-256 map
%   over {aggregate, trials, contract, evalArm, model, m0c, m2}.
here = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(here));
[st, out] = system(sprintf('git -C "%s" rev-parse HEAD', repoRoot));
assert(st == 0, 'air:M3:Fingerprints', ...
    'git rev-parse HEAD failed (exit %d) -- evidence cannot be bound', st);
f = struct();
f.head = strtrim(out);
f.sha = struct( ...
    'aggregate', sha256file(fullfile(here, 'm3_aggregate_batch.m')), ...
    'trials', sha256file(fullfile(here, 'run_air_m3_trials.m')), ...
    'contract', sha256file(fullfile(here, 'm3_batch_contract.m')), ...
    'evalArm', sha256file(fullfile(here, 'm3_eval_arm.m')), ...
    'model', sha256file(fullfile(here, 'air_spare.slx')), ...
    'm0c', sha256file(fullfile(here, 'm0c_vref_esc.m')), ...
    'm2', sha256file(fullfile(here, 'm2_eta_esc.m')));
end

function h = sha256file(fname)
%SHA256FILE lowercase hex SHA-256 of a file (m3_source_binding pattern).
fid = fopen(fname, 'rb');
assert(fid > 0, 'air:M3:Fingerprints', 'cannot open %s', fname);
data = fread(fid, '*uint8')';
fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
d = md.digest(data);
h = lower(sprintf('%02x', typecast(int8(d), 'uint8')));
end
