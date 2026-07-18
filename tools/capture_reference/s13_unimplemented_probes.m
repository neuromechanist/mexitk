% Epic 2 Phase 1: exploratory probes for the 10 opcodes mexitk does not
% implement. Registry params from docs/matitk_opcode_registry.txt; class
% hypotheses from docs/itk_opcode_mapping.md. Every probe is fault
% isolated by capture_case's inner try/catch-inside-evalc and saves its
% own .mat immediately, so a true process crash (which no MATLAB catch
% can prevent) still preserves every earlier probe's result. Ordered
% cheap/safe -> dangerous; SCSS runs LAST because it maps to
% CellularAggregate (global static state, mesh output) and may corrupt
% the session -- nothing is expected to run after it.
%
% This script may crash the MATLAB process. Run it in its OWN
% matlab -batch invocation, never combined with another script. Its
% probes are exploratory fingerprints, not faithful captures: several
% cap iteration counts well below the registry hint to keep runtime
% bounded (noted per-row below).
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's13_unimplemented_probes.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vd = double(V);

S1 = [70 50 14];
volBRecipe = 'circshift(double(V),[3 3 1])';
volB = eval(volBRecipe); %#ok<EVLCS>

% 1. FGMS: sigma sweep to fingerprint the algorithm vs. FGMRG. Pure
% filter, cheap.
capture_case(cfg, 'FGMS', 'sigma1_double', 1, Vd);
capture_case(cfg, 'FGMS', 'sigma2_double', 2, Vd);
capture_case(cfg, 'FGMS', 'sigma4_double', 4, Vd);

% 2. FMMCF: curvature flow, moderate.
capture_case(cfg, 'FMMCF', '10_0p0625_1_double', [10 0.0625 1], Vd);

% 3. FFFT: real vs complex switch.
capture_case(cfg, 'FFFT', 'real0_double', 0, Vd);
capture_case(cfg, 'FFFT', 'complex1_double', 1, Vd);

% 4. SFM: fast marching; needs a speed image (the primary input) + seed.
capture_case(cfg, 'SFM', 'stop100_seedS1_double', 100, Vd, struct('seedArg', S1));

% 5. RD: demons registration, two-image. SLOW (150 iterations).
% May crash the MATLAB process; per-probe save above preserves prior
% results.
capture_case(cfg, 'RD', 'demons_volB_double', [1024 7 150 1.0], Vd, ...
    struct('arg4', volB, 'arg4Recipe', volBRecipe));

% 6. RTPS: thin-plate spline; landmark-driven, may error.
% May crash the MATLAB process; per-probe save above preserves prior
% results.
capture_case(cfg, 'RTPS', 'tps_volB_seedS1_double', [], Vd, ...
    struct('arg4', volB, 'arg4Recipe', volBRecipe, 'seedArg', S1));

% 7. SLLS: level set. Iterations capped at 50 (registry hint is 800) to
% keep probe runtime bounded; this is an exploratory fingerprint, not a
% faithful capture. May crash the MATLAB process; per-probe save above
% preserves prior results.
capture_case(cfg, 'SLLS', 'slls_volB_seedS1_double', [0.5 1 1 0.02 50], Vd, ...
    struct('arg4', volB, 'arg4Recipe', volBRecipe, 'seedArg', S1));

% 8. SSDLS: level set. Iterations capped at 50. May crash the MATLAB
% process; per-probe save above preserves prior results.
capture_case(cfg, 'SSDLS', 'ssdls_volB_seedS1_double', [1 1 0.02 50], Vd, ...
    struct('arg4', volB, 'arg4Recipe', volBRecipe, 'seedArg', S1));

% 9. SGAC: level set. Iterations capped at 50. May crash the MATLAB
% process; per-probe save above preserves prior results.
capture_case(cfg, 'SGAC', 'sgac_volB_seedS1_double', [1 1 1 0.02 50], Vd, ...
    struct('arg4', volB, 'arg4Recipe', volBRecipe, 'seedArg', S1));

% 10. SCSS: most dangerous, LAST. Maps to CellularAggregate (global
% static state, mesh output) -- may corrupt the session; nothing runs
% after it. May crash the MATLAB process; per-probe save above preserves
% prior results.
capture_case(cfg, 'SCSS', 'scss_20_60_10_seedS1_double', [20 60 10], Vd, struct('seedArg', S1));

diary off;
