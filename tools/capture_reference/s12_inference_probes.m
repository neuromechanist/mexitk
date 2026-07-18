% Epic 2 Phase 1: inference probes for cross-checks this epic's Phase 3
% (reference tests, not the opcode epic's Phase 3) needs that are
% not simple per-opcode fixtures (identity/accessor/polarity/seed-order
% relationships). Deliberate deviation from s05's single end-of-script
% save: several probes store full volumes and probe 4 (SIC single-seed)
% may error or crash the process, so every probe saves its own .mat
% immediately. Probes reuse capture_case for plain calls (which already
% saves its own per-tag fixture); each probe additionally saves one
% s12_<probe>.mat summary file with the cross-check result. Probe tags
% are deliberately distinct from s07-s11's tags for the same opcode, even
% where the underlying call is identical, so no script's fixture is ever
% silently overwritten by another's. Ordered cheap/safe first,
% crash-prone (probe 4's single-seed case) nearer the end.
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's12_inference_probes.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vd = double(V);

S1 = [70 50 14];
S2 = [1 128 1];
S3 = [64 64 20];

val = double(Vd(70, 50, 14));
band = [val - 5, val + 5];
fprintf('val=%g band=%s\n', val, mat2str(band));

isDryRun = local_isdryrun();

binRecipeDouble = 'double(V>30)*255';
binDouble = eval(binRecipeDouble); %#ok<EVLCS>
labRecipeDouble = 'double(V>30)+double(V>60)';
labDouble = eval(labRecipeDouble); %#ok<EVLCS>

probe1_fga_fdg_identity(cfg, Vd, V, isDryRun);
probe2_fdmv_accessor(cfg, binDouble, binRecipeDouble, labDouble, labRecipeDouble, isDryRun);
probe3_sct_replace_value(cfg, Vd, S1, band, isDryRun);
probe5_sot_polarity(cfg, Vd, V);
probe6_seed_convention(cfg, Vd, S1, band);
probe7_nargout_arity(cfg, Vd, S1, isDryRun);
probe8_fbd_fbe_closing(cfg, binDouble, binRecipeDouble, isDryRun);
probe4_sic_seed_split(cfg, Vd, S1, S2, S3, isDryRun);  % crash-prone; runs last

diary off;

function probe1_fga_fdg_identity(cfg, Vd, Vu8, isDryRun)
% FGA vs FDG identity: capture both opcodes at the same three points,
% double+uint8, and record whether the original treats FGA as identical
% to FDG (informing mexitk's FGA=FDG choice).
points = {[4 5], [1 5], [10 5]};
pointTags = {'4_5', '1_5', '10_5'};
classNames = {'double', 'uint8'};
classVals = {Vd, Vu8};
results = struct('point', {}, 'class', {}, 'isEqual', {});
for pi = 1:numel(points)
    for ci = 1:numel(classNames)
        tag = sprintf('id_%s_%s', pointTags{pi}, classNames{ci});
        fFga = capture_case(cfg, 'FGA', tag, points{pi}, classVals{ci});
        fFdg = capture_case(cfg, 'FDG', tag, points{pi}, classVals{ci});
        if isDryRun
            eq = false;
        else
            eq = isequal(fFga.output, fFdg.output);
        end
        fprintf('  FGA vs FDG %s (%s): isequal=%d\n', pointTags{pi}, classNames{ci}, eq);
        results(end+1) = struct('point', points{pi}, 'class', classNames{ci}, 'isEqual', eq); %#ok<AGROW>
    end
end
save(fullfile(cfg.fixturesDir, 's12_fga_fdg_isequal.mat'), 'results', '-v7');
end

function probe2_fdmv_accessor(cfg, binDouble, binRecipe, labDouble, labRecipe, isDryRun)
% FDMV accessor: are FDMV's label values a subset of the input label set?
fFdmLab = capture_case(cfg, 'FDM', 'acc_lab_double', [], labDouble, struct('inputRecipe', labRecipe));
fFdmvLab = capture_case(cfg, 'FDMV', 'acc_lab_double', [], labDouble, struct('inputRecipe', labRecipe));
fFdmBin = capture_case(cfg, 'FDM', 'acc_bin_double', [], binDouble, struct('inputRecipe', binRecipe));
fFdmvBin = capture_case(cfg, 'FDMV', 'acc_bin_double', [], binDouble, struct('inputRecipe', binRecipe));
if isDryRun
    labSubset = false;
    binSubset = false;
    fdmLabOutput = [];
    fdmvLabOutput = [];
    fdmBinOutput = [];
    fdmvBinOutput = [];
else
    labSubset = isempty(setdiff(unique(fFdmvLab.output(:)), unique(labDouble(:))));
    binSubset = isempty(setdiff(unique(fFdmvBin.output(:)), unique(binDouble(:))));
    fdmLabOutput = fFdmLab.output;
    fdmvLabOutput = fFdmvLab.output;
    fdmBinOutput = fFdmBin.output;
    fdmvBinOutput = fFdmvBin.output;
end
fprintf('  FDMV label-subset (labels input): %d, (binarized input): %d\n', labSubset, binSubset);
save(fullfile(cfg.fixturesDir, 's12_fdmv_accessor.mat'), ...
    'labSubset', 'binSubset', 'fdmLabOutput', 'fdmvLabOutput', 'fdmBinOutput', 'fdmvBinOutput', '-v7');
end

function probe3_sct_replace_value(cfg, Vd, S1, band, isDryRun)
% SCT ReplaceValue: outputUnique's nonzero entry on the seed's own band
% (which grows a nonempty region) reveals the original's ReplaceValue.
% [20 60] is out-of-band for the seed value (68), so it documents the
% all-zero/no-growth case rather than revealing a replace value; both are
% captured (see plan Section 9 "Task's SCT ReplaceValue band").
fBand = capture_case(cfg, 'SCT', 'band_seed_double', band, Vd, struct('seedArg', S1));
fOutOfBand = capture_case(cfg, 'SCT', '20_60_seed_double', [20 60], Vd, struct('seedArg', S1));
if isDryRun
    replaceValue = NaN;
    outOfBandUnique = [];
else
    u = unique(fBand.output(:));
    nz = u(u ~= 0);
    if isempty(nz)
        replaceValue = NaN;
    else
        replaceValue = nz(1);
    end
    outOfBandUnique = fOutOfBand.output;
end
fprintf('  SCT ReplaceValue (band capture) = %g\n', replaceValue);
save(fullfile(cfg.fixturesDir, 's12_sct_replace_value.mat'), 'replaceValue', 'outOfBandUnique', '-v7');
end

function probe4_sic_seed_split(cfg, Vd, S1, S2, S3, isDryRun)
% SIC seed split: does seed-group order/count matter? [S1] alone may
% error or crash the original (why this probe runs last in s12).
fS1S2 = capture_case(cfg, 'SIC', 'split_s1s2', [20 255], Vd, struct('seedArg', [S1 S2]));
fS2S1 = capture_case(cfg, 'SIC', 'split_s2s1', [20 255], Vd, struct('seedArg', [S2 S1]));
fS1S2S3 = capture_case(cfg, 'SIC', 'split_s1s2s3', [20 255], Vd, struct('seedArg', [S1 S2 S3]));
if isDryRun
    eqOrder = false;
    eqThirdGroup = false;
    s1s2Output = [];
else
    eqOrder = isequal(fS1S2.output, fS2S1.output);
    eqThirdGroup = isequal(fS1S2.output, fS1S2S3.output);
    s1s2Output = fS1S2.output;
end
fprintf('  SIC [S1 S2] vs [S2 S1]: isequal=%d; vs [S1 S2 S3]: isequal=%d\n', eqOrder, eqThirdGroup);
save(fullfile(cfg.fixturesDir, 's12_sic_seedsplit.mat'), 'eqOrder', 'eqThirdGroup', 's1s2Output', '-v7');
% Single-seed group, last: may error or crash the original process.
capture_case(cfg, 'SIC', 'split_s1only', [20 255], Vd, struct('seedArg', S1));
end

function probe5_sot_polarity(cfg, Vd, Vu8)
% SOT defaults/polarity: outputUnique reveals inside/outside values
% (mexitk infers {0, typemax}: {0,255} uint8, {0,realmax} double).
capture_case(cfg, 'SOT', 'polarity_128_double', 128, Vd);
capture_case(cfg, 'SOT', 'polarity_128_uint8', 128, Vu8);
end

function probe6_seed_convention(cfg, Vd, S1, band)
% Seed convention: transposing the seed's (d1,d2) should change which
% region grows if the harness's no-transpose axis reading matches the
% original's.
capture_case(cfg, 'SCT', 'seed_70_50_14_double', band, Vd, struct('seedArg', S1));
transposedSeed = [S1(2) S1(1) S1(3)];
capture_case(cfg, 'SCT', 'seed_50_70_14_double', band, Vd, struct('seedArg', transposedSeed));
end

function probe7_nargout_arity(cfg, Vd, S1, isDryRun)
% Nargout/arity spot-probes: does the original error when asked for a
% second output on opcodes mexitk treats as strictly single-output?
opcodes = {'FMEDIAN', 'FDG', 'FGM', 'SCT'};
paramsByOp = {[1 1 1], [4 5], [], [20 60]};
probes = struct('opcode', {}, 'errored', {}, 'text', {});
for i = 1:numel(opcodes)
    opcode = opcodes{i};
    params = paramsByOp{i}; %#ok<NASGU>
    if strcmp(opcode, 'SCT')
        seedArg = S1; %#ok<NASGU>
        input = Vd; %#ok<NASGU>
        cmd = ['try; [o1,o2] = matitk(opcode, params, input, [], seedArg); ' ...
               'errored=false; catch me2; disp(["CAUGHT ERROR: " me2.message]); errored=true; end'];
    else
        input = Vd; %#ok<NASGU>
        cmd = ['try; [o1,o2] = matitk(opcode, params, input); ' ...
               'errored=false; catch me2; disp(["CAUGHT ERROR: " me2.message]); errored=true; end'];
    end
    if isDryRun
        fprintf('  [dryrun] nargout probe %s skipped\n', opcode);
        probes(end+1) = struct('opcode', opcode, 'errored', false, 'text', 'dryrun'); %#ok<AGROW>
        continue;
    end
    errored = true;
    fprintf('\n===== nargout=2 probe: %s =====\n', opcode);
    txt = evalc(cmd);
    fprintf('%s', txt);
    probes(end+1) = struct('opcode', opcode, 'errored', errored, 'text', txt); %#ok<AGROW>
end
save(fullfile(cfg.fixturesDir, 's12_nargout_probes.mat'), 'probes', '-v7');
end

function probe8_fbd_fbe_closing(cfg, binDouble, binRecipe, isDryRun)
% FBD-then-FBE closing composition: a two-call cross-check, not a
% per-opcode fixture (see s08's "Closing note"), so it is captured here
% as a bespoke probe rather than through capture_case's single-call
% contract. The intermediate FBD output is not recipe-reconstructible
% (it is itself a matitk output), so it is stored directly with its hash
% rather than as an inputRecipe.
if isDryRun
    fprintf('  [dryrun] FBD->FBE closing skipped\n');
    intermediate = [];
    final = [];
    intermediateHash = '';
    finalHash = '';
else
    intermediate = matitk('FBD', [1 255], binDouble);
    final = matitk('FBE', [1 255], intermediate);
    intermediateHash = local_md5(intermediate);
    finalHash = local_md5(final);
    fprintf('  closing: FBD->FBE hash=%s\n', finalHash);
end
save(fullfile(cfg.fixturesDir, 's12_closing_fbd_fbe.mat'), ...
    'intermediate', 'final', 'intermediateHash', 'finalHash', 'binRecipe', '-v7');
end
