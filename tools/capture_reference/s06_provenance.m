% Provenance: MD5 of the mexa64 binary, exact version string, and a standalone
% copy of the base input volume (MATLAB's built-in `mri`) used across all fixtures.
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's06_provenance.log'));
diary on;
format compact;

fixdir = [cfg.fixturesDir filesep];
binPath = fullfile(cfg.matitkDir, 'matitk.mexa64');

[status, md5out] = system(sprintf('md5sum %s', binPath));
fprintf('md5sum output: %s', md5out);

versionText = evalc('try; matitk(); catch me2; disp(me2.message); end');
fprintf('version/no-args text:\n%s\n', versionText);

load mri;
V = squeeze(D);
fprintf('Base input volume (load mri; squeeze(D)): class=%s size=%s min=%g max=%g\n', ...
    class(V), mat2str(size(V)), double(min(V(:))), double(max(V(:))));
inputHash = local_md5(V);
fprintf('inputHash (uint8)=%s\n', inputHash);
inputHashDouble = local_md5(double(V));
fprintf('inputHash (double)=%s\n', inputHashDouble);

provenance = struct();
provenance.binaryPath = binPath;
provenance.md5sumRaw = md5out;
provenance.versionText = versionText;
provenance.baseVolumeClass = class(V);
provenance.baseVolumeSize = size(V);
provenance.baseVolumeHash_uint8 = inputHash;
provenance.baseVolumeHash_double = inputHashDouble;
provenance.matlabVersion = version;
provenance.captureDate = datestr(now);

save(sprintf('%sprovenance.mat', fixdir), 'provenance', '-v7');
save(sprintf('%smri_base_volume.mat', fixdir), 'V', 'map', '-v7');
fprintf('\nSaved provenance.mat and mri_base_volume.mat\n');
diary off;
