classdef tPhase1FilterSmoke < matlab.unittest.TestCase
    % Smoke tests for the Phase 1 filter opcodes. This suite asserts
    % STRUCTURAL invariants (shape, class, parameter validation, and
    % per-filter behaviour) regardless of validation tier; it does not
    % itself assert bit-exactness or measured deviation bounds.
    %
    % Reference fixtures now exist for every opcode in the `op` list below
    % (captured in Epic 2 Phase 1, exactness/bounds established in Phase
    % 3): FMEDIAN, FMEAN, FBB, FF, FD, FBT, and (partially) FSN are
    % asserted bit-exact against the original in tests/tReferenceExact.m;
    % FDG and FGA are bounded-deviation opcodes with no bit-exact captured
    % point, asserted in tests/tReferenceBounded.m. This file's own
    % assertions stay useful regardless -- they catch a broken dispatch or
    % a malformed parameter guard even when the numeric comparison
    % suites are skipped or an opcode has no reference fixture at all.
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
        op = {'FMEDIAN','FMEAN','FBT','FDG','FBB','FSN','FF','FD','FGA'};
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
                case {'FMEDIAN','FMEAN'}; p = [1 1 1];
                case 'FBT';               p = [0 1 20 60];
                case {'FDG','FGA'};       p = [4 5];
                case 'FBB';               p = 1;
                case 'FSN';               p = [10 240 10 170];
                case 'FF';                p = [1 0 0];
                case 'FD';                p = [1 0];
            end
        end
    end

    methods (Test)  % parameterized common checks (all 9)
        function runsAndPreservesShapeAndClass(tc, op)
            % All four supported pixel classes; per-invariant tests below stay
            % double/uint8 since that is what mri.D natively offers.
            p = tPhase1FilterSmoke.validParams(op);
            for f = {@double, @single, @uint8, @int32}
                vin = f{1}(tc.Vu);
                out = mexitk(op, p, vin);
                tc.verifyClass(out, class(vin));
                tc.verifySize(out, size(vin));
            end
        end

        function rejectsWrongParamCount(tc, op)
            p = tPhase1FilterSmoke.validParams(op);
            short = p(1:end-1);   % one fewer than required
            tc.verifyError(@() mexitk(op, short, tc.V), 'mexitk:params');
        end
    end

    methods (Test)  % opcode-specific structural invariants
        function flipZeroAxesIsIdentity(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                tc.verifyEqual(mexitk('FF', [0 0 0], vin), vin);
            end
        end

        function flipTwiceSameAxesIsIdentity(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                once  = mexitk('FF', [1 0 1], vin);
                twice = mexitk('FF', [1 0 1], once);
                tc.verifyEqual(twice, vin);
            end
        end

        function flipMatchesBuiltinPerAxis(tc)
            % Not just a no-op / round-trip check: pin FF against MATLAB's own
            % flip() on each axis independently. XDIRECTION/YDIRECTION are
            % swapped relative to their param position: the original's
            % XDIRECTION flips MATLAB dim 2, YDIRECTION flips MATLAB dim 1
            % (ZDIRECTION flips dim 3 unchanged). Fixture-proven bit-exact
            % against ff_* reference captures; see docs/COMPATIBILITY.md.
            params = {[1 0 0], [0 1 0], [0 0 1]};
            flipAxis = [2 1 3];
            for a = 1:3
                for f = {@double, @uint8}
                    vin = f{1}(tc.Vu);
                    tc.verifyEqual(mexitk('FF', params{a}, vin), flip(vin, flipAxis(a)));
                end
            end
        end

        function binaryThresholdIsTwoValued(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                out = mexitk('FBT', [0 1 20 60], vin);
                u = unique(out(:));
                tc.verifyEmpty(setdiff(double(u), [0 1]), ...
                    'output must contain only outsideValue/insideValue');
                tc.verifyGreaterThan(nnz(out == 1), 0);  % both classes occur
                tc.verifyGreaterThan(nnz(out == 0), 0);
            end
        end

        function binaryThresholdPinsInsideOutside(tc)
            % Pin the actual outsideValue/insideValue assignment, not just
            % that the output is two-valued: the global-min voxel sits below
            % lowerThreshold, so it must come out as outsideValue (5).
            [~, minIdx] = min(tc.V(:));
            [ix, iy, iz] = ind2sub(size(tc.V), minIdx);
            minVal = tc.V(ix, iy, iz);
            maxVal = max(tc.V(:));
            out = mexitk('FBT', [5 9 minVal + 1 maxVal], tc.V);
            tc.verifyEqual(out(ix, iy, iz), 5);
        end

        function sigmoidStaysWithinOutputRange(tc)
            lo = 10; hi = 240;
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                out = mexitk('FSN', [lo hi 10 170], vin);
                tc.verifyGreaterThanOrEqual(min(double(out(:))), lo);
                tc.verifyLessThanOrEqual(max(double(out(:))), hi);
            end
        end

        function sigmoidEndpointDirection(tc)
            % With the registry's own default beta (170), the mri volume's
            % entire intensity range (0-88) sits below the sigmoid's
            % transition centre, so the whole output saturates near
            % outputMinimum and never approaches outputMaximum (measured: the
            % global-max voxel maps to ~10.06, not anywhere near 240). That is
            % correct sigmoid behaviour for that beta, just not one that
            % exercises both endpoints against this volume. To actually probe
            % low-input -> low-output and high-input -> high-output, beta is
            % placed at the volume's own intensity midpoint instead.
            lo = 10; hi = 240; mid = (lo + hi) / 2;
            beta = (min(tc.V(:)) + max(tc.V(:))) / 2;
            [~, minIdx] = min(tc.V(:));
            [~, maxIdx] = max(tc.V(:));
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                out = mexitk('FSN', [lo hi 10 beta], vin);
                tc.verifyLessThan(double(out(minIdx)), mid);
                tc.verifyGreaterThan(double(out(maxIdx)), mid);
            end
        end

        function medianZeroRadiusIsIdentity(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                tc.verifyEqual(mexitk('FMEDIAN', [0 0 0], vin), vin);
            end
        end

        function medianSmoothsWithNonzeroRadius(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                out = mexitk('FMEDIAN', [2 2 2], vin);
                tc.verifyNotEqual(out, vin);
            end
        end

        function meanZeroRadiusIsIdentity(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                tc.verifyEqual(mexitk('FMEAN', [0 0 0], vin), vin);
            end
        end

        function meanSmoothsAndReducesVariance(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                out = mexitk('FMEAN', [2 2 2], vin);
                tc.verifyNotEqual(out, vin);
                tc.verifyLessThan(std(double(out(:))), std(double(vin(:))));
            end
        end

        function radiusAxisOrderMatters(tc)
            % Catches a transposed radius assignment: an X-heavy radius must
            % not produce the same output as a Z-heavy one.
            outX = mexitk('FMEDIAN', [3 1 1], tc.V);
            outZ = mexitk('FMEDIAN', [1 1 3], tc.V);
            tc.verifyNotEqual(outX, outZ);
        end

        function gaussianSmoothsAndReducesVariance(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                out = mexitk('FDG', [4 5], vin);
                tc.verifyNotEqual(out, vin);
                tc.verifyLessThan(std(double(out(:))), std(double(vin(:))));
            end
        end

        function largerVarianceSmoothsMore(tc)
            outLo = mexitk('FDG', [1 5], tc.V);
            outHi = mexitk('FDG', [10 5], tc.V);
            tc.verifyLessThan(std(outHi(:)), std(outLo(:)));
        end

        function fgaEqualsFdgForIdenticalParams(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                tc.verifyEqual(mexitk('FGA', [4 5], vin), mexitk('FDG', [4 5], vin));
            end
        end

        function derivativeChangesInput(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                out = mexitk('FD', [1 0], vin);
                tc.verifyNotEqual(out, vin);
            end
        end

        function derivativeDirectionAffectsOutput(tc)
            out0 = mexitk('FD', [1 0], tc.V);
            out1 = mexitk('FD', [1 1], tc.V);
            tc.verifyNotEqual(out0, out1);
        end

        function derivativeOrderZeroIsIdentity(tc)
            % Verified empirically before writing this assertion (per project
            % policy: never tune a test to pass an assumption that turns out
            % false). ITK's DerivativeImageFilter with order 0 is genuinely
            % the identity operator, exactly as the math implies, for both
            % double and uint8 on the reference volume.
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                tc.verifyEqual(mexitk('FD', [0 0], vin), vin);
            end
        end

        function binomialBlurRunsWithOneRepetition(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                out = mexitk('FBB', 1, vin);
                tc.verifySize(out, size(vin));
                tc.verifyNotEqual(out, vin);
            end
        end
    end

    methods (Test)  % parameter-range and semantic-guard error paths
        function binaryThresholdRejectsOutOfRangeOnIntegralType(tc)
            tc.verifyError(@() mexitk('FBT', [0 1 20 300], tc.Vu), 'mexitk:paramRange');
        end

        function binaryThresholdAcceptsOutOfRangeOnDouble(tc)
            % 300 is out of uint8 range but perfectly valid for a double
            % pixel type: the guard is per-target-type, not a blanket cap.
            out = mexitk('FBT', [0 1 20 300], tc.V);
            tc.verifySize(out, size(tc.V));
        end

        function binaryThresholdRejectsOutOfRangeOnSingle(tc)
            % 1e39 is finite and fits a double, but exceeds float's range
            % (~3.4e38); casting it to float is undefined behaviour, distinct
            % from the integral-type case above.
            tc.verifyError(@() mexitk('FBT', [0 1 20 1e39], single(tc.Vu)), 'mexitk:paramRange');
            out = mexitk('FBT', [0 1 20 1e39], tc.V);
            tc.verifySize(out, size(tc.V));
        end

        function medianRejectsNegativeRadius(tc)
            tc.verifyError(@() mexitk('FMEDIAN', [-1 1 1], tc.V), 'mexitk:paramRange');
        end

        function binomialBlurRejectsNegativeRepetitions(tc)
            tc.verifyError(@() mexitk('FBB', -1, tc.V), 'mexitk:paramRange');
        end

        function derivativeRejectsNegativeOrder(tc)
            tc.verifyError(@() mexitk('FD', [-1 0], tc.V), 'mexitk:paramRange');
        end

        function gaussianRejectsNegativeKernelWidth(tc)
            tc.verifyError(@() mexitk('FDG', [4 -1], tc.V), 'mexitk:paramRange');
        end

        function fdgRejectsNonPositiveVariance(tc)
            tc.verifyError(@() mexitk('FDG', [-5 5], tc.V), 'mexitk:FDG:gaussianVariance');
        end

        function fdgRejectsNonFiniteVariance(tc)
            % A plain `<= 0.0` guard does not catch NaN (every ordered
            % comparison against NaN is false): verified directly before
            % this guard existed, a NaN gaussianVariance silently produced
            % an all-NaN output, no exception. +Inf is rejected the same
            % way (param-guard hardening, Epic 3 issue #26).
            tc.verifyError(@() mexitk('FDG', [NaN 5], tc.V), 'mexitk:FDG:gaussianVariance');
            tc.verifyError(@() mexitk('FDG', [Inf 5], tc.V), 'mexitk:FDG:gaussianVariance');
        end

        function fgaRejectsNonPositiveVariance(tc)
            tc.verifyError(@() mexitk('FGA', [-5 5], tc.V), 'mexitk:FGA:gaussianVariance');
        end

        function fgaRejectsNonFiniteVariance(tc)
            % Shares ExecuteDiscreteGaussian with FDG; same rationale.
            tc.verifyError(@() mexitk('FGA', [NaN 5], tc.V), 'mexitk:FGA:gaussianVariance');
            tc.verifyError(@() mexitk('FGA', [Inf 5], tc.V), 'mexitk:FGA:gaussianVariance');
        end

        function sigmoidRejectsZeroAlpha(tc)
            tc.verifyError(@() mexitk('FSN', [10 240 0 170], tc.V), 'mexitk:FSN:alpha');
        end
    end
end
