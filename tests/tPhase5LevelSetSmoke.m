classdef tPhase5LevelSetSmoke < matlab.unittest.TestCase
    % Smoke tests for the Phase 5 (Epic 3 Phase 1) level-set opcodes, FMMCF
    % and SFM. Reference fixtures exist for both (see tests/tReferenceBounded.m
    % -- neither reproduces the original bit-for-bit, so their measured
    % deviations live there, not in tReferenceExact.m), but each fixture
    % covers exactly one parameter set on double input; this suite instead
    % asserts structural invariants (shape, class, monotonicity, and ITK's
    % own documented semantics) across all four pixel types and the
    % parameter/seed validation paths. Every non-guaranteed assertion here
    % was empirically confirmed against a real build before being
    % committed; none is guessed from the ITK header evidence alone.
    %
    % SPDX-License-Identifier: BSD-3-Clause
    % Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
    % Swartz Center for Computational Neuroscience (SCCN),
    % Institute for Neural Computation (INC), UC San Diego.

    properties
        V    % double volume
        Vu   % uint8 volume (native mri class)
    end

    properties (Constant)
        % [70 50 14], value 68: the same seed used throughout the Phase 3
        % region-growing suite (see tPhase3RegionGrowingSmoke.regionGrowSeed
        % for why this voxel and not the volume's global max). Reused here
        % for the same reason: an asymmetric-subscript seed so a transposed
        % axis in SeedPointsToIndices is caught.
        Seed = [70 50 14];
        % ITK's own LargeValue sentinel for a double level-set image:
        % NumericTraits<double>::max()/2, matched exactly against the
        % sfm_stop100_seedS1_double fixture (see src/opcodes/sfm.cpp).
        DoubleSentinel = 8.988465674311579e+307;
    end

    methods (TestMethodSetup)
        function loadVolume(tc)
            mri = load('mri');
            tc.Vu = squeeze(mri.D);
            tc.V  = double(tc.Vu);
        end
    end

    methods (Test)  % FMMCF
        function fmmcfRunsAndPreservesShapeAndClass(tc)
            for f = {@double, @single, @uint8, @int32}
                vin = f{1}(tc.Vu);
                out = mexitk('FMMCF', [10 0.0625 1], vin);
                tc.verifyClass(out, class(vin));
                tc.verifySize(out, size(vin));
                tc.verifyTrue(all(isfinite(double(out(:)))), sprintf( ...
                    'FMMCF (%s): non-finite value in output', class(vin)));
            end
        end

        function fmmcfZeroIterationsIsNoOp(tc)
            % numberOfIterations=0 must leave the input untouched: verified
            % exactly (max abs diff 0) before writing this assertion.
            out = mexitk('FMMCF', [0 0.0625 1], tc.V);
            tc.verifyEqual(out, tc.V);
        end

        function fmmcfSmooths(tc)
            % Measured: std(input)=30.30, std(10 iters)=29.98.
            out = mexitk('FMMCF', [10 0.0625 1], tc.V);
            tc.verifyLessThan(std(out(:)), std(tc.V(:)));
        end

        function fmmcfMoreIterationsSmoothMore(tc)
            % Measured: std(10 iters)=29.98, std(20 iters)=29.91.
            out10 = mexitk('FMMCF', [10 0.0625 1], tc.V);
            out20 = mexitk('FMMCF', [20 0.0625 1], tc.V);
            tc.verifyLessThan(std(out20(:)), std(out10(:)));
        end

        function fmmcfRejectsShortParamCount(tc)
            tc.verifyError(@() mexitk('FMMCF', [10 0.0625], tc.V), 'mexitk:params');
        end

        function fmmcfRejectsNegativeTimeStep(tc)
            % Same ill-posed-backward-flow rationale as FCF's own guard.
            tc.verifyError(@() mexitk('FMMCF', [10 -0.0625 1], tc.V), ...
                'mexitk:FMMCF:timeStep');
        end

        function fmmcfRejectsNonFiniteTimeStep(tc)
            % A plain `< 0.0` guard does not catch NaN (every ordered
            % comparison against NaN is false): measured directly before
            % this guard existed, a NaN timeStep crashed the whole MATLAB
            % process with a SIGBUS inside MinMaxCurvatureFlowFunction::
            % ComputeThreshold, not merely a bad result -- the same
            % severity class as the SWS/SOT crash guards. +-Inf are
            % rejected the same way as any other non-finite value.
            tc.verifyError(@() mexitk('FMMCF', [10 NaN 1], tc.V), ...
                'mexitk:FMMCF:timeStep');
            tc.verifyError(@() mexitk('FMMCF', [10 Inf 1], tc.V), ...
                'mexitk:FMMCF:timeStep');
            tc.verifyError(@() mexitk('FMMCF', [10 -Inf 1], tc.V), ...
                'mexitk:FMMCF:timeStep');
        end

        function fmmcfRejectsNegativeStencilRadius(tc)
            % RadiusValueType is unsigned; CastParam's integral path
            % rejects a negative value.
            tc.verifyError(@() mexitk('FMMCF', [10 0.0625 -1], tc.V), ...
                'mexitk:paramRange');
        end

        function fmmcfAcceptsZeroTimeStepAsNoOp(tc)
            % Matches FCF's own documented timeStep==0 convention: a
            % defined no-op, not rejected.
            out = mexitk('FMMCF', [10 0 1], tc.V);
            tc.verifyEqual(out, tc.V);
        end
    end

    methods (Test)  % SFM
        function sfmRunsAndPreservesShapeAndClass(tc)
            for f = {@double, @single, @uint8, @int32}
                vin = f{1}(tc.Vu);
                out = mexitk('SFM', 100, vin, [], tPhase5LevelSetSmoke.Seed);
                tc.verifyClass(out, class(vin));
                tc.verifySize(out, size(vin));
            end
        end

        function sfmSeedVoxelIsZero(tc)
            sub = tPhase5LevelSetSmoke.Seed;
            out = mexitk('SFM', 100, tc.V, [], sub);
            tc.verifyEqual(out(sub(1), sub(2), sub(3)), 0);
        end

        function sfmSeedConventionIsNotTransposed(tc)
            % An axis transposition would place the zero-valued trial point
            % at a different voxel; the transposed coordinate must NOT be
            % zero (verified: 0.500333 there, not 0).
            sub = tPhase5LevelSetSmoke.Seed;
            out = mexitk('SFM', 100, tc.V, [], sub);
            transposed = [sub(2), sub(1), sub(3)];
            tc.verifyNotEqual(out(transposed(1), transposed(2), transposed(3)), 0);
        end

        function sfmOutputIsNonNegative(tc)
            out = mexitk('SFM', 100, tc.V, [], tPhase5LevelSetSmoke.Seed);
            tc.verifyGreaterThanOrEqual(min(out(:)), 0);
        end

        function sfmLargerStoppingTimeReachesAtLeastAsManyVoxels(tc)
            % Measured: reached (finite, non-sentinel) voxel count grows
            % 170405 -> 171527 -> 171530 (saturating) as stoppingTime goes
            % 1 -> 2 -> 5, then stays flat through 100: the speed image
            % (the volume's own intensity) is exactly zero over the image's
            % background, so the front cannot propagate past the boundary
            % of the nonzero-intensity region no matter how large
            % stoppingTime is -- a real, ITK-documented property (a
            % zero-speed neighbor's update time is unbounded), not a bug.
            sub = tPhase5LevelSetSmoke.Seed;
            small = mexitk('SFM', 1, tc.V, [], sub);
            big = mexitk('SFM', 5, tc.V, [], sub);
            reachedSmall = nnz(small < tPhase5LevelSetSmoke.DoubleSentinel);
            reachedBig = nnz(big < tPhase5LevelSetSmoke.DoubleSentinel);
            tc.verifyGreaterThan(reachedBig, reachedSmall);
        end

        function sfmEmptySeedsAllSentinel(tc)
            % Defined behaviour, verified directly against
            % itkFastMarchingImageFilter.hxx's Initialize()/GenerateData():
            % with no trial points the marching heap is empty from the
            % start, so every voxel keeps Initialize()'s own LargeValue
            % fill, and the call returns a fully allocated, uniform
            % sentinel output rather than erroring.
            out = mexitk('SFM', 100, tc.V, [], []);
            tc.verifyEqual(numel(unique(out(:))), 1);
            tc.verifyEqual(out(1, 1, 1), tPhase5LevelSetSmoke.DoubleSentinel);
        end

        function sfmSentinelSaturatesOnIntegralExport(tc)
            % uint8/int32 promote to float internally; the (very large)
            % LargeValue sentinel saturates to the integral type's own max
            % through ClampExport, rather than an undefined-behaviour cast.
            outU8 = mexitk('SFM', 100, tc.Vu, [], []);
            outI32 = mexitk('SFM', 100, int32(tc.Vu), [], []);
            tc.verifyEqual(outU8(1, 1, 1), uint8(255));
            tc.verifyEqual(outI32(1, 1, 1), int32(intmax('int32')));
        end

        function sfmRejectsShortParamCount(tc)
            tc.verifyError(@() mexitk('SFM', [], tc.V, [], tPhase5LevelSetSmoke.Seed), ...
                'mexitk:params');
        end

        function sfmRejectsOutOfBoundsSeed(tc)
            tc.verifyError(@() mexitk('SFM', 100, tc.V, [], [9999 9999 9999]), ...
                'mexitk:seeds');
        end

        function sfmRejectsExtraOutputArgument(tc)
            % Single-output opcode per the registry; requesting a second
            % output must error, matching every other opcode's nargout
            % contract (see tFomtReference.m's own use of the same
            % withOutputs helper).
            sub = tPhase5LevelSetSmoke.Seed;
            tc.verifyError(@() withOutputs(2, @() mexitk('SFM', 100, tc.V, [], sub)), ...
                'mexitk:nargout');
        end
    end
end

function varargout = withOutputs(n, fn)
% Calls fn requesting exactly n outputs, so nargout handling can be tested.
varargout = cell(1, n);
[varargout{1:n}] = fn();
end
