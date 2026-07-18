% Epic 2 Phase 1: capture Phase-1-opcode (filter) fixtures mirroring
% tests/tPhase1FilterSmoke.m's validParams and probe points, across the
% four supported pixel classes where the smoke suite exercises them.
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's07_filters_capture.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vd = double(V);
Vs = single(V);
Vi = int32(V);

classNames = {'double', 'single', 'uint8', 'int32'};
classVals = {Vd, Vs, V, Vi};

mn = double(min(Vd(:)));
mx = double(max(Vd(:)));
beta = (mn + mx) / 2;
fprintf('mn=%g mx=%g beta=%g\n', mn, mx, beta);

% FMEDIAN
capture_classes(cfg, 'FMEDIAN', 'r1_1_1', [1 1 1], classNames, classVals, 1:4);
capture_classes(cfg, 'FMEDIAN', 'r0_0_0', [0 0 0], classNames, classVals, [1 3]);
capture_classes(cfg, 'FMEDIAN', 'r2_2_2', [2 2 2], classNames, classVals, [1 3]);
capture_case(cfg, 'FMEDIAN', 'r3_1_1_double', [3 1 1], Vd);
capture_case(cfg, 'FMEDIAN', 'r1_1_3_double', [1 1 3], Vd);

% FMEAN
capture_classes(cfg, 'FMEAN', 'r1_1_1', [1 1 1], classNames, classVals, 1:4);
capture_classes(cfg, 'FMEAN', 'r0_0_0', [0 0 0], classNames, classVals, [1 3]);
capture_classes(cfg, 'FMEAN', 'r2_2_2', [2 2 2], classNames, classVals, [1 3]);

% FBT
capture_classes(cfg, 'FBT', '0_1_20_60', [0 1 20 60], classNames, classVals, 1:4);
capture_case(cfg, 'FBT', '5_9_1_88_double', [5 9 mn+1 mx], Vd);
capture_classes(cfg, 'FBT', '0_1_20_300', [0 1 20 300], classNames, classVals, [1 3]);
capture_classes(cfg, 'FBT', '0_1_20_1e39', [0 1 20 1e39], classNames, classVals, [1 2]);

% FDG
capture_classes(cfg, 'FDG', '4_5', [4 5], classNames, classVals, 1:4);
capture_case(cfg, 'FDG', '1_5_double', [1 5], Vd);
capture_case(cfg, 'FDG', '10_5_double', [10 5], Vd);

% FGA
capture_classes(cfg, 'FGA', '4_5', [4 5], classNames, classVals, 1:4);

% FBB
capture_classes(cfg, 'FBB', '1', 1, classNames, classVals, 1:4);

% FSN
capture_classes(cfg, 'FSN', '10_240_10_170', [10 240 10 170], classNames, classVals, 1:4);
capture_classes(cfg, 'FSN', '10_240_10_44', [10 240 10 beta], classNames, classVals, [1 3]);

% FF
capture_classes(cfg, 'FF', '1_0_0', [1 0 0], classNames, classVals, 1:4);
capture_classes(cfg, 'FF', '0_0_0', [0 0 0], classNames, classVals, [1 3]);
capture_classes(cfg, 'FF', '0_1_0', [0 1 0], classNames, classVals, [1 3]);
capture_classes(cfg, 'FF', '0_0_1', [0 0 1], classNames, classVals, [1 3]);
capture_classes(cfg, 'FF', '1_0_1', [1 0 1], classNames, classVals, [1 3]);

% FD
capture_classes(cfg, 'FD', '1_0', [1 0], classNames, classVals, 1:4);
capture_case(cfg, 'FD', '1_1_double', [1 1], Vd);
capture_classes(cfg, 'FD', '0_0', [0 0], classNames, classVals, [1 3]);

diary off;
