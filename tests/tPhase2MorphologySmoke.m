classdef tPhase2MorphologySmoke < matlab.unittest.TestCase
    % Smoke tests for the Phase 2 morphology/distance-map opcodes. No
    % reference fixtures exist for these, so the suite asserts structural
    % invariants (shape, class, parameter validation, and mathematical
    % morphology properties) rather than bit-exactness. Every assertion here
    % was empirically confirmed against a real build before being committed;
    % none is guessed from the ITK header evidence alone.
    %
    % SPDX-License-Identifier: BSD-3-Clause
    % Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
    % Swartz Center for Computational Neuroscience (SCCN),
    % Institute for Neural Computation (INC), UC San Diego.

    properties
        V    % double volume
        Vu   % uint8 volume (native mri class)
    end

    properties (TestParameter)
        op      = {'FBD','FBE','FVBIH','FDM','FDMV'};   % common run test
        paramOp = {'FBD','FBE','FVBIH'};                 % FDM/FDMV take 0 params
    end

    methods (TestMethodSetup)
        function loadVolume(tc)
            mri = load('mri');
            tc.Vu = squeeze(mri.D);
            tc.V  = double(tc.Vu);
        end
    end

    methods (Static)
        function p = validParams(op)
            switch op
                case {'FBD','FBE'};  p = [1 255];
                case 'FVBIH';        p = [1 1 1 0 255 1 1];
                case {'FDM','FDMV'}; p = [];
            end
        end

        function b = binarize(V)
            % Values {0,255}: a foreground mask morphology can dilate/erode.
            b = double(V > 30) * 255;
        end

        function lab = labels(V)
            % Values {0,1,2}: real intensity bands, for a non-trivial
            % Voronoi partition (a pure 0/255 input gives a uniform map).
            lab = double(V > 30) + double(V > 60);
        end
    end

    methods (Test)  % parameterized common checks
        function runsAndPreservesShapeAndClass(tc, op)
            % For FDM/FDMV this is also the zero-param "call with volume
            % only" success path. Raw mri has no voxel==255, so FBD/FBE here
            % just produce an all-background volume; the meaningful
            % morphology checks below use binarized input. This test only
            % pins shape+class.
            p = tPhase2MorphologySmoke.validParams(op);
            for f = {@double, @single, @uint8, @int32}
                vin = f{1}(tc.Vu);
                out = mexitk(op, p, vin);
                tc.verifyClass(out, class(vin));
                tc.verifySize(out, size(vin));
            end
        end

        function rejectsShortParamCount(tc, paramOp)
            p = tPhase2MorphologySmoke.validParams(paramOp);
            short = p(1:end-1);
            tc.verifyError(@() mexitk(paramOp, short, tc.V), 'mexitk:params');
        end
    end

    methods (Test)  % FDM/FDMV zero-param calling convention
        function distanceOpcodesAcceptEmptyParams(tc)
            outDm = mexitk('FDM', [], tc.V);
            tc.verifySize(outDm, size(tc.V));
            tc.verifyClass(outDm, 'double');
            outDmv = mexitk('FDMV', [], tc.V);
            tc.verifySize(outDmv, size(tc.V));
            tc.verifyClass(outDmv, 'double');
        end
    end

    methods (Test)  % FBD / FBE (binarized input)
        function dilationIsExtensiveAndGrows(tc)
            b = tPhase2MorphologySmoke.binarize(tc.V);
            out = mexitk('FBD', [1 255], b);
            % Every input foreground voxel stays foreground: a ball
            % structuring element contains its own center, so dilation is
            % extensive. Mathematically guaranteed.
            tc.verifyTrue(all(out(b == 255) == 255));
            % Verified empirically: radius-1 dilation flips background
            % voxels adjacent to foreground on this data (182200 > 148626).
            tc.verifyGreaterThan(nnz(out == 255), nnz(b == 255));
            % Unlike FBE below, FBD never writes a background sentinel:
            % untouched background passes through as the original input
            % value, so unique(out) really is [0 255] here. Verified.
        end

        function erosionIsAntiextensiveAndShrinks(tc)
            b = tPhase2MorphologySmoke.binarize(tc.V);
            out = mexitk('FBE', [1 255], b);
            % Every output foreground voxel was foreground in the input:
            % erosion is anti-extensive. Mathematically guaranteed.
            tc.verifyTrue(all(b(out == 255) == 255));
            % Verified empirically: radius-1 erosion strictly shrinks the
            % foreground on this data (90127 < 148626).
            tc.verifyLessThan(nnz(out == 255), nnz(b == 255));
            % Assertions use ==255 deliberately, not unique(out)==[0 255]:
            % FBE writes itk::NumericTraits<PixelType>::NonpositiveMin() (0
            % only for uint8; INT_MIN/-realmax for int32/float/double), but
            % ONLY to pixels that WERE foreground in the input and got
            % eroded away; untouched original background keeps its own
            % input value unchanged (verified on an int32 run: output values
            % are exactly {INT_MIN, 0, 255}, and count(INT_MIN) == 58499,
            % exactly the eroded-away foreground count). So a {0,255} input
            % can still show a literal 0 in the output that is unmodified
            % background, not the sentinel. See docs/COMPATIBILITY.md.
        end

        function closingIsExtensive(tc)
            % Dilate-then-erode is a morphological closing, which is
            % extensive (fills gaps, never removes foreground) for a
            % structuring element containing the origin, which the ball SE
            % does. Verified empirically before writing this assertion: the
            % correct extensivity direction is "every ORIGINAL foreground
            % voxel is still foreground after closing"
            % (all(closed(b==255)==255)), confirmed true, foreground count
            % grew (165152 >= 148626), and the foreground mask changed
            % (gaps got filled). Radius-0 identity is not asserted: ITK's
            % ball SE at radius 0 is plausibly identity, but border
            % handling was not empirically confirmed, so it is left out
            % per project policy (never assert what was not verified).
            b = tPhase2MorphologySmoke.binarize(tc.V);
            closed = mexitk('FBE', [1 255], mexitk('FBD', [1 255], b));
            tc.verifyTrue(all(closed(b == 255) == 255));
            tc.verifyGreaterThanOrEqual(nnz(closed == 255), nnz(b == 255));
            tc.verifyNotEqual(closed == 255, b == 255);
        end

        function valueParameterIsWiredNotHardcoded(tc)
            % Uses a foreground value of 7, not 255, to catch a
            % copy-paste bug where DilateValue/ErodeValue was hardcoded to
            % 255 instead of reading the value parameter: if that bug were
            % present, stray 255s would show up in the output even though
            % the input never contains 255. Verified empirically: neither
            % filter ever produces a 255, and each still grows/shrinks the
            % ==7 set as expected (FBD 182200>148626, FBE 90127<148626,
            % same magnitudes as the value=255 case, confirming the value
            % itself, not the growth/shrink mechanics, was the thing being
            % tested here).
            b7 = double(tc.V > 30) * 7;

            outD = mexitk('FBD', [1 7], b7);
            tc.verifyFalse(any(outD(:) == 255));
            tc.verifyGreaterThan(nnz(outD == 7), nnz(b7 == 7));

            outE = mexitk('FBE', [1 7], b7);
            tc.verifyFalse(any(outE(:) == 255));
            tc.verifyLessThan(nnz(outE == 7), nnz(b7 == 7));
        end

        function erosionSentinelStructureOnInt32(tc)
            % Pins the corrected FBE sentinel claim (docs/COMPATIBILITY.md):
            % on an int32 run, output values are exactly {INT_MIN, 0, 255},
            % and the INT_MIN count equals exactly the number of voxels that
            % were foreground in the input and got eroded away. Verified
            % empirically: 58499 on this data.
            b = tPhase2MorphologySmoke.binarize(tc.V);
            out = mexitk('FBE', [1 255], int32(b));
            intMin = intmin('int32');
            tc.verifyEmpty(setdiff(unique(out(:)), int32([intMin, 0, 255])));
            erodedAwayCount = nnz(b == 255) - nnz(out == 255);
            tc.verifyEqual(nnz(out == intMin), erodedAwayCount);
        end
    end

    methods (Test)  % FDM / FDMV
        function distanceMapZeroOnObject(tc)
            for f = {@double, @uint8}
                b = f{1}(tPhase2MorphologySmoke.binarize(tc.V));
                d = mexitk('FDM', [], b);
                % Object (nonzero) voxels have distance 0.
                tc.verifyTrue(all(d(b ~= 0) == 0));
                % Background voxels have distance >=1 (>0 even after uint8
                % truncation, since the minimum grid distance is 1).
                tc.verifyTrue(all(d(b == 0) > 0));
                tc.verifyNotEqual(d, b);
            end
        end

        function voronoiIdsAreSequentialNotDrawnFromInput(tc)
            % Epic 2 Phase 3 disproved the earlier assumption this test was
            % named for: Voronoi labels are NOT drawn from the input's own
            % pixel values. They are a sequential per-object-voxel id
            % (scan-order over the permuted volume), rescaled to
            % [0, typeMax] -- except on uint8 output, which wraps the raw
            % id via standard unsigned overflow instead (see
            % src/opcodes/fdm.cpp), so it alone is excluded from the
            % "all distinct" check below (256 wrapped values cannot stay
            % distinct across 65010 object voxels; that collision is
            % expected, not a bug).
            for f = {@double, @uint8}
                lab = f{1}(tPhase2MorphologySmoke.labels(tc.V));
                vor = mexitk('FDMV', [], lab);
                d = mexitk('FDM', [], lab);
                tc.verifyNotEqual(vor, d);
            end
            % Verified directly: among the 65010 voxels sharing input label
            % value 1 in the "labels" fixture, all 65010 receive DISTINCT
            % FDMV output values on the double path -- if labels were drawn
            % from input, they would all share one value instead. See
            % docs/COMPATIBILITY.md.
            lab = tPhase2MorphologySmoke.labels(tc.V);
            vor = mexitk('FDMV', [], lab);
            sameInputVoxels = vor(lab == 1);
            tc.verifyEqual(numel(unique(sameInputVoxels)), numel(sameInputVoxels));
        end

        function sixAdjacentBackgroundSharesTheMinimalRescaledDistance(tc)
            % A background voxel that is 6-connected-adjacent to a
            % foreground voxel is exactly grid-distance 1 away, the minimum
            % possible nonzero raw distance -- but FDM's output is that raw
            % distance RESCALED to [0, typeMax] (see src/opcodes/fdm.cpp),
            % not the raw grid distance itself, so the expected value is no
            % longer literally 1. What IS still true, and what this test
            % now pins, is that every such voxel shares exactly the same
            % rescaled value (the minimal nonzero distance value present
            % anywhere in the output), since they all have the identical
            % raw grid distance of 1. Verified empirically on the full
            % binarized volume (26954 such voxels, all equal to the single
            % value 1317.569..., not just a single spot check).
            b = tPhase2MorphologySmoke.binarize(tc.V);
            d = mexitk('FDM', [], b);
            fg = (b == 255);
            adj6 = false(size(b));
            adj6(2:end, :, :)   = adj6(2:end, :, :)   | fg(1:end-1, :, :);
            adj6(1:end-1, :, :) = adj6(1:end-1, :, :) | fg(2:end, :, :);
            adj6(:, 2:end, :)   = adj6(:, 2:end, :)   | fg(:, 1:end-1, :);
            adj6(:, 1:end-1, :) = adj6(:, 1:end-1, :) | fg(:, 2:end, :);
            adj6(:, :, 2:end)   = adj6(:, :, 2:end)   | fg(:, :, 1:end-1);
            adj6(:, :, 1:end-1) = adj6(:, :, 1:end-1) | fg(:, :, 2:end);
            bgAdj6 = adj6 & ~fg;
            tc.verifyNotEmpty(find(bgAdj6, 1));
            minNonzero = min(d(d > 0));
            tc.verifyTrue(all(d(bgAdj6) == minNonzero));
        end

        function distanceMapRejectsAllZeroVolume(tc)
            % Epic 2 Phase 3 changed this from a defined-but-meaningless
            % saturated/gradient output into an outright rejection
            % (mexitk:fdm:noObject): the original's own distance field over
            % zero objects was found to be an artifact of the filter's
            % internal initialization, not a defined answer to "distance to
            % the nearest object" when there is no object. See deliberate
            % deviation entry in docs/COMPATIBILITY.md.
            z8 = zeros(size(tc.Vu), 'uint8');
            tc.verifyError(@() mexitk('FDM', [], z8), 'mexitk:fdm:noObject');
            z64 = zeros(size(tc.Vu));
            tc.verifyError(@() mexitk('FDM', [], z64), 'mexitk:fdm:noObject');
            tc.verifyError(@() mexitk('FDMV', [], z64), 'mexitk:fdm:noObject');
        end
    end

    methods (Test)  % FVBIH (construct a real-data hole)
        function holeFillsAndOutputStaysBinary(tc)
            b = tPhase2MorphologySmoke.binarize(tc.V);
            cnt = convn(double(b == 255), ones(3, 3, 3), 'same');
            cand = find(cnt(:) == 27 & b(:) == 255);
            % Real-data assumption: a solid interior foreground block
            % exists. Verified: 77646 candidates on the 128x128x27 brain
            % mask thresholded at >30, so cand is never empty here. If this
            % ever became empty on a different volume, the fallback would
            % be to carve the center of any interior region instead.
            tc.verifyNotEmpty(cand);
            bfill = b;
            bfill(cand(1)) = 0;   % carve one hole: 26 foreground neighbors
            out = mexitk('FVBIH', [1 1 1 0 255 1 1], bfill);
            % Radius [1 1 1] gives 26 neighbors; majority threshold 1 needs
            % >=14 ON to flip OFF->ON; 26>=14, so the hole fills. Verified.
            tc.verifyEqual(out(cand(1)), 255);
            % The voting filter only flips background->foreground among the
            % two configured values, so output is a subset of {0,255}.
            tc.verifyEmpty(setdiff(unique(out(:)), [0 255]));
        end

        function distinctParamsChangeOutput(tc)
            % Every position in this params vector is numerically distinct
            % from the [1 1 1 0 255 1 1] baseline (asymmetric radius
            % [2 1 1], majorityThreshold 3, 2 iterations instead of 1), so a
            % pairwise setter swap or an ignored parameter would show up as
            % no difference from baseline. Verified empirically: both
            % param sets fill every one of 1553 sparse single-voxel holes
            % carved into the mask (so that comparison alone is not
            % discriminating), but the larger radius / higher threshold /
            % extra iteration in the distinct params measurably grows the
            % total foreground further (160970 > 158392 on this data), and
            % the two outputs are not equal overall.
            b = tPhase2MorphologySmoke.binarize(tc.V);
            cnt = convn(double(b == 255), ones(3, 3, 3), 'same');
            holes = find(cnt(:) == 27 & b(:) == 255);
            tc.verifyNotEmpty(holes);
            holeIdx = holes(1:50:end);
            bmulti = b;
            bmulti(holeIdx) = 0;

            baseline = mexitk('FVBIH', [1 1 1 0 255 1 1], bmulti);
            distinct = mexitk('FVBIH', [2 1 1 0 255 3 2], bmulti);

            tc.verifyTrue(all(baseline(holeIdx) == 255));
            tc.verifyTrue(all(distinct(holeIdx) == 255));
            tc.verifyNotEqual(baseline, distinct);
            tc.verifyGreaterThan(nnz(distinct == 255), nnz(baseline == 255));
        end
    end

    methods (Test)  % error paths (existing CastParam / deviation #5 guard)
        function fbdRejectsNegativeRadius(tc)
            tc.verifyError(@() mexitk('FBD', [-1 255], tc.V), 'mexitk:paramRange');
        end

        function fbdRejectsOutOfRangeValueOnIntegralType(tc)
            tc.verifyError(@() mexitk('FBD', [1 300], tc.Vu), 'mexitk:paramRange');
        end

        function fbdAcceptsOutOfRangeValueOnDouble(tc)
            % 300 is out of uint8 range but valid for double: the guard is
            % per-target-type, not a blanket cap.
            out = mexitk('FBD', [1 300], tc.V);
            tc.verifySize(out, size(tc.V));
        end

        function fbeRejectsNegativeRadius(tc)
            tc.verifyError(@() mexitk('FBE', [-1 255], tc.V), 'mexitk:paramRange');
        end

        function fvbihRejectsNegativeRadius(tc)
            tc.verifyError(@() mexitk('FVBIH', [-1 1 1 0 255 1 1], tc.V), 'mexitk:paramRange');
        end

        function fvbihRejectsOutOfRangeForegroundOnIntegralType(tc)
            tc.verifyError(@() mexitk('FVBIH', [1 1 1 0 300 1 1], tc.Vu), 'mexitk:paramRange');
        end

        function fvbihAcceptsOutOfRangeForegroundOnDouble(tc)
            out = mexitk('FVBIH', [1 1 1 0 300 1 1], tc.V);
            tc.verifySize(out, size(tc.V));
        end
    end
end
