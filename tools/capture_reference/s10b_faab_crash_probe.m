% Epic 2 Phase 1: FAAB crash isolation. Measured directly against the
% real binary across two campaign runs: FAAB on uint8 input crashes the
% original's process with a floating point exception -- not a catchable
% itk::ExceptionObject -- regardless of whether the input is raw (run 1)
% or already binarized at bin33 (run 2). The crash is about the pixel
% type, not the pixel value distribution, so every integral-class FAAB
% case (raw and bin33, uint8 and int32) is isolated here rather than in
% s10, which keeps only FAAB double/single (both completed cleanly in
% both runs). int32 is presumed to hit the same crash by extension but
% is not yet directly confirmed -- captured first below so a run that
% dies partway still yields that new information before repeating the
% already-confirmed uint8 crash.
%
% This script may crash the MATLAB process, likely on its first case.
% Run it in its OWN matlab -batch invocation, after s10_gradients_capture,
% never combined with another script. capture_case's inner try/catch
% cannot prevent a real process crash, only an itk::ExceptionObject: a
% crash happens mid-matitk-call, before that case's own save() runs, so
% a crashed case produces no fixture and (with MEXITK_REFCAP_RESUME=1)
% will be re-attempted, not skipped, on the next invocation. Each case
% that DOES complete is still fault isolated at the case level via
% capture_case's normal per-call save.
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's10b_faab_crash_probe.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vi = int32(V);
bin33RecipeUint8 = 'uint8(255*(V>33))';
bin33Uint8 = eval(bin33RecipeUint8); %#ok<EVLCS>
bin33RecipeInt32 = 'int32(255*double(V>33))';
bin33Int32 = eval(bin33RecipeInt32); %#ok<EVLCS>

capture_case(cfg, 'FAAB', '0p01_50_2_raw_int32', [0.01 50 2], Vi);
capture_case(cfg, 'FAAB', '0p01_50_2_bin33_int32', [0.01 50 2], bin33Int32, struct('inputRecipe', bin33RecipeInt32));
capture_case(cfg, 'FAAB', '0p01_50_2_raw_uint8', [0.01 50 2], V);
capture_case(cfg, 'FAAB', '0p01_50_2_bin33_uint8', [0.01 50 2], bin33Uint8, struct('inputRecipe', bin33RecipeUint8));

local_mark_complete(cfg, 's10b');
diary off;
