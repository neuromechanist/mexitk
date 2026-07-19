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
% Cases (all double; RTPS takes zero parameters). The one-line intents
% below are what this script's AUTHOR meant to test when the numbers were
% chosen -- before question 1 above was answered. Once landmarks were
% established as INTERLEAVED (source1,target1,source2,target2,...), not
% split-in-half, two of these decode to something DIFFERENT from that
% original intent; both are noted explicitly so a future reader does not
% have to re-derive it, the same way COMPATIBILITY.md's own writeup does:
%   pairs4_translate: INTENDED as 4 spread source points each translated by
%                     [6 -4 2], against an asymmetric volumeB. What the
%                     array [src4 tgt4] actually decodes to under
%                     interleaved reading is 4 pairs of the form
%                     (src4(k), src4(k+1)) and (tgt4(k), tgt4(k+1)) --
%                     i.e. each pair maps one of src4's own points to the
%                     NEXT one in the same block (a +[60 0 0] shift within
%                     src4, and separately within tgt4), not a [6 -4 2]
%                     shift from src to tgt. The capture is still decisive
%                     for FIXED/MOVING direction regardless: volumeB's
%                     asymmetry (flip+shift) still makes a fixed/moving
%                     mixup misplace the output visibly, independent of
%                     what the landmark correspondence itself geometrically
%                     means. See docs/COMPATIBILITY.md's "RD and RTPS"
%                     section for the actual decoded pairs and how this was
%                     established.
%   pairs4_identity : INTENDED as volumeB == input with targets == sources
%                     (a literal identity landmark set), to test mexitk's
%                     structural self-check (output ~= input if the wiring
%                     is right). [src4 src4] does NOT decode to identity
%                     pairs under interleaved reading: it decodes to the
%                     same TWO distinct pairs as pairs4_translate's own
%                     src4-internal pairs, each supplied TWICE (source1==
%                     source3, target1==target3, etc) -- a rank-deficient,
%                     not identity, landmark system. This mismatch between
%                     intent and reality is exactly what pairs4_identity's
%                     own measured residual traces to (rank-deficient
%                     duplicate pairs, not coplanarity) -- see
%                     docs/COMPATIBILITY.md.
%   pair1_minimal   : one pair (2 landmarks) -- src4's first point to
%                     tgt4's first point. Split-half and interleaved
%                     reading agree trivially for a single pair (there is
%                     only one way to split or interleave 2 points), so
%                     this one decodes exactly as intended either way.
%                     Does the original accept an underdetermined TPS?
%   odd3_reject     : 3 landmarks; expected rejection, captures the exact
%                     even-count error text for the rejection suite. Pairing
%                     convention is irrelevant here too: the original's
%                     rejection is a parity check on the total count, not a
%                     statement about how the (even) case would decode.
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

% Landmarks are INTERLEAVED (s1,t1,s2,t2,...), established from the
% captures above. These two cases test the two competing explanations for
% why pairs4_identity and pair1_minimal carry a residual while the
% well-posed captures match at the floating-point noise floor:
%   coplanar3_distinct: 3 DISTINCT pairs whose sources are coplanar. If
%     coplanarity alone were the cause, this deviates; if duplicate
%     landmark rows were the cause, this matches closely.
%   pairs2_distinct / pairs3_distinct: 2 and 3 distinct pairs, spanning
%     the gap between 1 pair (severely underdetermined) and 4+ (well
%     posed). A monotone shrink toward zero confirms underdetermination.
cop3 = [30 40 8, 90 40 8, 30 100 8];
cop3t = cop3 + repmat([6 -4 2], 1, 3);
capture_case(cfg, 'RTPS', 'coplanar3_distinct_double', [], Vd, ...
    struct('arg4', Vd, 'arg4Recipe', 'double(V)', ...
           'seedArg', reshape([reshape(cop3, 3, []); reshape(cop3t, 3, [])], 1, [])));

nc2 = src5(1:6); nc2t = tgt5(1:6);
capture_case(cfg, 'RTPS', 'pairs2_distinct_double', [], Vd, ...
    struct('arg4', Vd, 'arg4Recipe', 'double(V)', ...
           'seedArg', reshape([reshape(nc2, 3, []); reshape(nc2t, 3, [])], 1, [])));

nc3 = src5(1:9); nc3t = tgt5(1:9);
capture_case(cfg, 'RTPS', 'pairs3_distinct_double', [], Vd, ...
    struct('arg4', Vd, 'arg4Recipe', 'double(V)', ...
           'seedArg', reshape([reshape(nc3, 3, []); reshape(nc3t, 3, [])], 1, [])));

local_mark_complete(cfg, 's14');
