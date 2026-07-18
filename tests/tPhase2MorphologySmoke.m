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
            % Assertions use ==255 deliberately: non-foreground output is
            % itk::NumericTraits<PixelType>::NonpositiveMin() (0 only for
            % uint8; INT_MIN/-realmax for int32/float/double), not 0. Do NOT
            % assert unique(out)==[0 255].
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

        function voronoiLabelsDrawnFromInput(tc)
            % A pure binary 0/255 input yields a uniform-255 Voronoi map
            % (still subset of the input set, still != FDM); the multi-band
            % input makes the partition non-trivial and is the honest
            % exercise of the nearest-object property.
            lab = tPhase2MorphologySmoke.labels(tc.V);
            vor = mexitk('FDMV', [], lab);
            d = mexitk('FDM', [], lab);
            tc.verifyEmpty(setdiff(unique(vor(:)), unique(lab(:))));
            tc.verifyNotEqual(vor, d);
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
