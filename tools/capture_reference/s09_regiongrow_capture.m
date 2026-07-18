% Epic 2 Phase 1: capture Phase-3-opcode (region-growing/thresholding)
% fixtures mirroring tests/tPhase3RegionGrowingSmoke.m's validParams,
% seeds, and probe bands. Seed axis convention is no-transpose:
% (d1,d2,d3) -> ITK index (d1-1,d2-1,d3-1) (docs/COMPATIBILITY.md).
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's09_regiongrow_capture.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vd = double(V);
Vs = single(V);
Vi = int32(V);

classNames = {'double', 'single', 'uint8', 'int32'};
classVals = {Vd, Vs, V, Vi};

S1 = [70 50 14];
S2 = [1 128 1];
val = double(Vd(70, 50, 14));
band = [val - 5, val + 5];
wide = [val - 15, val + 15];
fprintf('val=%g band=%s wide=%s\n', val, mat2str(band), mat2str(wide));

% SCT
capture_classes_seeded(cfg, 'SCT', '20_60_seedS1', [20 60], classNames, classVals, 1:4, S1);
capture_case(cfg, 'SCT', 'band_seedS1_double', band, Vd, struct('seedArg', S1));
capture_case(cfg, 'SCT', 'wide_seedS1_double', wide, Vd, struct('seedArg', S1));
capture_case(cfg, 'SCT', '20_60_emptyseed_double', [20 60], Vd, struct('seedArg', []));
capture_case(cfg, 'SCT', '20_60_dimmax_double', [20 60], Vd, struct('seedArg', [70 50 27]));
capture_case(cfg, 'SCT', '20_60_fracseed_double', [20 60], Vd, struct('seedArg', [70.9 50 14]));

% SCC
capture_classes_seeded(cfg, 'SCC', '2p5_5_100_seedS1', [2.5 5 100], classNames, classVals, 1:4, S1);
capture_case(cfg, 'SCC', '4_5_100_seedS1_double', [4 5 100], Vd, struct('seedArg', S1));
capture_case(cfg, 'SCC', '1_5_100_seedS1_double', [1 5 100], Vd, struct('seedArg', S1));
capture_case(cfg, 'SCC', '2p5_5_100_emptyseed_double', [2.5 5 100], Vd, struct('seedArg', []));
capture_case(cfg, 'SCC', '2p5_5_100_dimmax_double', [2.5 5 100], Vd, struct('seedArg', [70 50 27]));

% SNC
capture_classes_seeded(cfg, 'SNC', '1_1_1_20_60_255_seedS1', [1 1 1 20 60 255], classNames, classVals, 1:4, S1);
% radius [1 1 1] with the tight seed-band: the exact combination
% seedConventionIsNotTransposed/disconnectedVoxelNotLabeled exercise.
capture_case(cfg, 'SNC', '1_1_1_band_seedS1_double', [1 1 1 band(1) band(2) 255], Vd, struct('seedArg', S1));
capture_case(cfg, 'SNC', 'r0_band_seedS1_double', [0 0 0 band(1) band(2) 255], Vd, struct('seedArg', S1));
capture_case(cfg, 'SNC', 'r2_band_seedS1_double', [2 2 2 band(1) band(2) 255], Vd, struct('seedArg', S1));
capture_case(cfg, 'SNC', 'rx_wide_seedS1_double', [3 1 1 wide(1) wide(2) 255], Vd, struct('seedArg', S1));
capture_case(cfg, 'SNC', 'rz_wide_seedS1_double', [1 1 3 wide(1) wide(2) 255], Vd, struct('seedArg', S1));
capture_case(cfg, 'SNC', 'emptyseed_double', [1 1 1 20 60 255], Vd, struct('seedArg', []));
capture_case(cfg, 'SNC', 'dimmax_double', [1 1 1 0 255 255], Vd, struct('seedArg', [70 50 27]));

% SIC
capture_classes_seeded(cfg, 'SIC', '20_255_seedS1S2', [20 255], classNames, classVals, 1:4, [S1 S2]);
capture_case(cfg, 'SIC', '20_255_extraignored_double', [20 255], Vd, struct('seedArg', [S1 S2 9999 9999 9999]));

% SOT
capture_classes(cfg, 'SOT', '128', 128, classNames, classVals, 1:4);

% FOMT (N=1 cross-check for the SOT/FOMT comparison)
capture_classes(cfg, 'FOMT', '1_128', [1 128], classNames, classVals, [1 3]);

diary off;

function capture_classes_seeded(cfg, opcode, tagPrefix, params, classNames, classVals, useIdx, seedArg)
% Same as capture_classes, but every call carries the same seedArg.
for k = useIdx
    tag = sprintf('%s_%s', tagPrefix, classNames{k});
    capture_case(cfg, opcode, tag, params, classVals{k}, struct('seedArg', seedArg));
end
end
