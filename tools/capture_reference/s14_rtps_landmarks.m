% s14_rtps_landmarks: settle RTPS's landmark calling convention.
%
% The s13 probe proved RTPS rejects a single seed point with "there should
% be even number of landmarks (source->target)". That message leaves two
% open questions this script answers with real captures:
%   1. Is the even-length seed list split in HALF (sources then targets)
%      or INTERLEAVED (s1,t1,s2,t2,...)? A pure-translation target set
%      predicts a visibly different warp under each reading.
%   2. Which volume does the transform resample, and in which direction?
%      volumeB is deliberately asymmetric (flipped + shifted), so a
%      fixed/moving or source/target mixup misplaces the output visibly.
%
% Cases (all double; RTPS takes zero parameters):
%   pairs4_translate: 4 spread source points, 4 targets = source + [6 -4 2],
%                     asymmetric volumeB. The decisive convention capture.
%   pairs4_identity : volumeB == input, targets == sources. If the wiring
%                     matches mexitk's structural self-check, output ~= input.
%   pair1_minimal   : one pair (2 landmarks). Does the original accept an
%                     underdetermined TPS?
%   odd3_reject     : 3 landmarks; expected rejection, captures the exact
%                     even-count error text for the rejection suite.
%
% Run exactly like s07-s13 (own matlab -batch invocation; crash-tolerant).

cfg = refcap_config();
addpath(cfg.matitkDir);
load mri; %#ok<LOAD>
V = squeeze(D);
Vd = double(V);

volBRecipe = 'circshift(flip(double(V),1),[5 9 2])';
volB = circshift(flip(Vd, 1), [5 9 2]);

% Seeds are a FLAT ROW VECTOR of concatenated 3-tuples, exactly as the
% multi-seed SIC probes pass them ([S1 S2] = 1x6): the original rejects a
% matrix with "Seed array must be a vector." (captured in the first s14
% attempt, before this correction).
src4 = [30 40 8, 90 40 8, 30 100 20, 90 100 20];
tgt4 = src4 + repmat([6 -4 2], 1, 4);

capture_case(cfg, 'RTPS', 'pairs4_translate_double', [], Vd, ...
    struct('arg4', volB, 'arg4Recipe', volBRecipe, ...
           'seedArg', [src4 tgt4]));

capture_case(cfg, 'RTPS', 'pairs4_identity_double', [], Vd, ...
    struct('arg4', Vd, 'arg4Recipe', 'double(V)', ...
           'seedArg', [src4 src4]));

capture_case(cfg, 'RTPS', 'pair1_minimal_double', [], Vd, ...
    struct('arg4', volB, 'arg4Recipe', volBRecipe, ...
           'seedArg', [src4(1:3) tgt4(1:3)]));

capture_case(cfg, 'RTPS', 'odd3_reject_double', [], Vd, ...
    struct('arg4', volB, 'arg4Recipe', volBRecipe, ...
           'seedArg', [src4(1:6) tgt4(1:3)]));

% The src4 set above is COPLANAR (z is a function of y), which makes the
% thin-plate spline's affine part degenerate and sends the warp wildly
% extrapolating. These two cases use a non-coplanar 5-point set so the
% transform is well posed: nc5_identity is the decisive convention test
% (a correct wiring must reproduce the input exactly), nc5_translate is
% the geometry test (a source/target or fixed/moving mixup translates the
% wrong way, visibly).
src5 = [30 40 6, 96 44 9, 34 102 21, 92 98 24, 62 70 15];
tgt5 = src5 + repmat([6 -4 2], 1, 5);

capture_case(cfg, 'RTPS', 'nc5_identity_double', [], Vd, ...
    struct('arg4', Vd, 'arg4Recipe', 'double(V)', ...
           'seedArg', [src5 src5]));

capture_case(cfg, 'RTPS', 'nc5_translate_double', [], Vd, ...
    struct('arg4', Vd, 'arg4Recipe', 'double(V)', ...
           'seedArg', [src5 tgt5]));

local_mark_complete(cfg, 's14');
