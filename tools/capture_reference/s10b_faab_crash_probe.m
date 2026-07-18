% Epic 2 Phase 1: FAAB crash isolation. Measured directly against the
% real binary (run 1, s10_gradients_capture, exit 137): FAAB on raw
% (non-binary) uint8 mri triggers a floating point exception that kills
% the original's process outright -- not a catchable itk::ExceptionObject.
% double and single completed cleanly in that same run and are captured
% in s10 instead; int32 was never reached (uint8 crashed first) but is
% isolated here too as a precaution, since it is the other integral type
% FAAB could plausibly hit the same numeric edge case on.
%
% This script may crash the MATLAB process. Run it in its OWN
% matlab -batch invocation, after s10_gradients_capture, never combined
% with another script. capture_case's inner try/catch cannot prevent a
% real process crash, only an itk::ExceptionObject; each case here is
% still fault isolated at the case level via capture_case's normal
% per-call save, so a crash on the first case cannot lose the second.
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's10b_faab_crash_probe.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vi = int32(V);

capture_case(cfg, 'FAAB', '0p01_50_2_raw_uint8', [0.01 50 2], V);
capture_case(cfg, 'FAAB', '0p01_50_2_raw_int32', [0.01 50 2], Vi);

local_mark_complete(cfg, 's10b');
diary off;
