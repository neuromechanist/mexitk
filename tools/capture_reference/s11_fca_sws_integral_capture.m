% Epic 2 Phase 1: fill the integral-type reference gap for FCA/SWS
% (s02/s04 only captured double/single). SWS may reject integral input on
% the original; capture the outcome either way (that is the reference).
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's11_fca_sws_integral_capture.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vi = int32(V);

classNames = {'uint8', 'int32'};
classVals = {V, Vi};

% FCA
capture_classes(cfg, 'FCA', '5_0p0625_3', [5 0.0625 3], classNames, classVals, 1:2);
capture_classes(cfg, 'FCA', '1_0p0625_3', [1 0.0625 3], classNames, classVals, 1:2);

% SWS (matches the primary s04 fixture params: sws_level0p05_thresh0p01_*)
capture_classes(cfg, 'SWS', '0p05_0p01', [0.05 0.01], classNames, classVals, 1:2);

local_mark_complete(cfg, 's11');
diary off;
