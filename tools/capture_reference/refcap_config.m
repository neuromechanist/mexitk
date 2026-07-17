function cfg = refcap_config()
%REFCAP_CONFIG Shared configuration for the mexitk reference-capture harness.
%
%   cfg = REFCAP_CONFIG() returns a struct with:
%     matitkDir   - directory containing matitk.mexa64, read from the
%                   MATITK_DIR environment variable. Errors with a clear
%                   message if MATITK_DIR is unset or does not exist.
%     outDir      - output root, read from the MEXITK_REFCAP_OUT
%                   environment variable, defaulting to a subfolder under
%                   the system temp directory if unset.
%     fixturesDir - outDir/fixtures (created if it does not exist).
%     logsDir     - outDir/logs (created if it does not exist).
%
%   This harness re-captures the reference fixtures committed under
%   tests/fixtures/ by exercising the original 2006 matitk.mexa64 binary.
%   See tools/capture_reference/README.md for what it is, why most users
%   will never need to run it, and how to run it if you do have the
%   binary.

matitkDir = getenv('MATITK_DIR');
if isempty(matitkDir)
    error('refcap_config:missingMatitkDir', ...
        ['MATITK_DIR is not set.\n' ...
         'Point it at the directory containing the original matitk.mexa64 ' ...
         'binary, e.g.:\n' ...
         '    MATITK_DIR=/path/to/dir matlab -batch "s00_smoke_test"\n' ...
         'See tools/capture_reference/README.md.']);
end
if ~isfolder(matitkDir)
    error('refcap_config:matitkDirNotFound', ...
        'MATITK_DIR is set to ''%s'' but that directory does not exist.', ...
        matitkDir);
end

outDir = getenv('MEXITK_REFCAP_OUT');
if isempty(outDir)
    outDir = fullfile(tempdir(), 'mexitk-refcap');
end

fixturesDir = fullfile(outDir, 'fixtures');
logsDir = fullfile(outDir, 'logs');
if ~isfolder(fixturesDir)
    mkdir(fixturesDir);
end
if ~isfolder(logsDir)
    mkdir(logsDir);
end

cfg = struct('matitkDir', matitkDir, 'outDir', outDir, ...
             'fixturesDir', fixturesDir, 'logsDir', logsDir);
end
