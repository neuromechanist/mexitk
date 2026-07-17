% PRIORITY 2: capture SWS (WatershedSegmentation) fixtures.
% params = [SETLEVEL SETTHRESHOLD], both nominally 0.0-1.0.
% NFT call shape: matitk('SWS', [sl st], mb-double(b3), [], WMp)  -- arg5 is a seed array
% the caller claims watershed does NOT consume; verify that empirically.
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's04_sws_capture.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vd = double(V);
fixdir = [cfg.fixturesDir filesep];

% --- Main captures ---
f_noseed_arg4empty = capture_sws('level0p05_thresh0p01_noseedarg4empty', [0.05 0.01], Vd, [], [], fixdir);
f_seed64_64_14      = capture_sws('level0p05_thresh0p01_seed64_64_14', [0.05 0.01], Vd, [], [64 64 14], fixdir);
f_seedempty          = capture_sws('level0p05_thresh0p01_seedEmptyExplicit', [0.05 0.01], Vd, [], [], fixdir);
f_seednonsense       = capture_sws('level0p05_thresh0p01_seedNonsense', [0.05 0.01], Vd, [], [9999 -500 12345 1 1 1], fixdir);
f_omitarg5           = capture_sws('level0p05_thresh0p01_omitArg5Entirely', [0.05 0.01], Vd, 'OMIT', 'OMIT', fixdir);

fprintf('\n===== Seed-arg equivalence checks =====\n');
fprintf('isequal(noseed(arg4=[],arg5=[]), seed64_64_14) = %d\n', isequal(f_noseed_arg4empty.output, f_seed64_64_14.output));
fprintf('isequal(noseed, seedEmptyExplicit)              = %d\n', isequal(f_noseed_arg4empty.output, f_seedempty.output));
fprintf('isequal(noseed, seedNonsense)                    = %d\n', isequal(f_noseed_arg4empty.output, f_seednonsense.output));
fprintf('isequal(noseed(3-arg call), omitArg5Entirely)   = %d\n', isequal(f_noseed_arg4empty.output, f_omitarg5.output));
fprintf('isequal(seed64_64_14, seedNonsense)              = %d\n', isequal(f_seed64_64_14.output, f_seednonsense.output));

seedEquivalence = struct( ...
    'noseed_vs_seed64', isequal(f_noseed_arg4empty.output, f_seed64_64_14.output), ...
    'noseed_vs_seedEmpty', isequal(f_noseed_arg4empty.output, f_seedempty.output), ...
    'noseed_vs_seedNonsense', isequal(f_noseed_arg4empty.output, f_seednonsense.output), ...
    'noseed_vs_omitArg5', isequal(f_noseed_arg4empty.output, f_omitarg5.output), ...
    'seed64_vs_seedNonsense', isequal(f_seed64_64_14.output, f_seednonsense.output) );
save(sprintf('%ssws_seed_equivalence.mat', fixdir), 'seedEquivalence', '-v7');

% --- Additional level/threshold pairs ---
fprintf('\n===== Additional level/threshold pairs =====\n');
capture_sws('level0p1_thresh0p05', [0.1 0.05], Vd, [], [], fixdir);
capture_sws('level0p02_thresh0p001', [0.02 0.001], Vd, [], [], fixdir);
capture_sws('level0p5_thresh0p5', [0.5 0.5], Vd, [], [], fixdir);
capture_sws('level0_thresh0', [0 0], Vd, [], [], fixdir);
capture_sws('level1_thresh1', [1 1], Vd, [], [], fixdir);

diary off;

function fixture = capture_sws(tag, params, inputVol, arg4, seedArg, fixdir)
    fprintf('\n===== CASE: %s (params=%s, seed=%s) =====\n', tag, mat2str(params), mat2str(seedArg));
    fixture = struct();
    fixture.opcode = 'SWS';
    fixture.params = params;
    fixture.inputClass = class(inputVol);
    fixture.inputSize = size(inputVol);
    fixture.inputHash = local_md5(inputVol);
    fixture.seedArg = seedArg;
    try
        if ischar(arg4) && strcmp(arg4, 'OMIT')
            % sentinel meaning: omit arg4/arg5 entirely (call with 3 args only)
            captured = evalc('o = matitk(''SWS'', params, inputVol);');
        else
            captured = evalc('o = matitk(''SWS'', params, inputVol, arg4, seedArg);');
        end
        fprintf('%s', captured);
        fixture.success = true;
        fixture.errmsg = '';
        fixture.consoleText = captured;
        fixture.output = o;
        fixture.outputClass = class(o);
        fixture.outputSize = size(o);
        fixture.outputHash = local_md5(o);
        u = unique(o(:))';
        fixture.outputUnique = u;
        fixture.numLabels = numel(u);
        fprintf('  -> outputClass=%s size=%s n_unique_labels=%d hash=%s\n', ...
            fixture.outputClass, mat2str(fixture.outputSize), numel(u), fixture.outputHash);
        if numel(u) <= 30
            fprintf('  unique labels: %s\n', mat2str(u));
        else
            fprintf('  unique labels (first 30 of %d): %s ...\n', numel(u), mat2str(u(1:30)));
        end
    catch ME
        fixture.success = false;
        fixture.errmsg = ME.message;
        fixture.consoleText = '';
        fixture.output = [];
        fprintf('  FAILED: %s\n', ME.message);
    end
    save(sprintf('%ssws_%s.mat', fixdir, tag), 'fixture', '-v7');
end
