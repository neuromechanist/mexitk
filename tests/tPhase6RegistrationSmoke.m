classdef tPhase6RegistrationSmoke < matlab.unittest.TestCase
    % Smoke tests for the Phase 6 (Epic 4 Phase 1) registration opcodes, RD
    % and RTPS -- the first two opcodes in Category::kRegistration. Both are
    % kBoundedDeviation: RD has one successful reference fixture (see
    % tests/tReferenceBounded.m for its measured deviation); RTPS's own
    % first fixture was a rejection only, but a follow-up reference-host
    % capture round (s14, tools/capture_reference/s14_rtps_landmarks.m) then
    % supplied eight successful captures plus a second rejection (see
    % tests/tReferenceBounded.m / tests/tReferenceRejections.m, and RTPS's
    % own StatusNote in src/opcodes/rtps.cpp for the full evidence). This
    % suite instead asserts structural invariants (shape, class,
    % finiteness, and parameter/volume-B/landmark validation paths) across
    % all four pixel types, the same style as tPhase5LevelSetSmoke.m for
    % the previous epic's two-volume opcodes. Every non-guaranteed
    % assertion here was empirically confirmed against a real build before
    % being committed; none is guessed from the ITK header evidence alone.
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
        RdParams = [1024 7 150 1];
    end

    methods (TestMethodSetup)
        function loadVolume(tc)
            mri = load('mri');
            tc.Vu = squeeze(mri.D);
            tc.V  = double(tc.Vu);
        end
    end

    methods (Test)  % RD
        function rdRunsAndPreservesShapeAndClass(tc)
            for f = {@double, @single, @uint8, @int32}
                vin = f{1}(tc.Vu);
                out = mexitk('RD', tPhase6RegistrationSmoke.RdParams, vin, vin);
                tc.verifyClass(out, class(vin));
                tc.verifySize(out, size(vin));
                tc.verifyTrue(all(isfinite(double(out(:)))), sprintf( ...
                    'RD (%s): non-finite value in output', class(vin)));
            end
        end

        function rdZeroIterationsIsIdentityWarp(tc)
            % With numberOfIterations=0 the Demons displacement field is
            % all-zero, so warping the moving image with it must return
            % the moving image unchanged: verified exactly (0/442368
            % voxels differ) before writing this assertion, and asserted
            % directly here as the pipeline's own no-op sanity check (the
            % same role FMMCF/FCF's own zero-iteration no-op tests play).
            movingCircshift = circshift(tc.V, [3 3 1]);
            out = mexitk('RD', [1024 7 0 1], tc.V, movingCircshift);
            tc.verifyEqual(out, movingCircshift);
        end

        function rdIsDeterministicAcrossRuns(tc)
            % Two consecutive runs must be bit-identical: registration is
            % iterative and multithreaded, so this rules out
            % nondeterminism as a confound before any reference comparison
            % is meaningful (see tests/tReferenceBounded.m's own RD case
            % and src/opcodes/rd.cpp's StatusNote for the full writeup).
            movingCircshift = circshift(tc.V, [3 3 1]);
            out1 = mexitk('RD', tPhase6RegistrationSmoke.RdParams, tc.V, movingCircshift);
            out2 = mexitk('RD', tPhase6RegistrationSmoke.RdParams, tc.V, movingCircshift);
            tc.verifyEqual(out1, out2);
        end

        function rdRequiresVolumeB(tc)
            tc.verifyError(@() mexitk('RD', tPhase6RegistrationSmoke.RdParams, tc.V), ...
                'mexitk:RD:volumeB');
            tc.verifyError(@() mexitk('RD', tPhase6RegistrationSmoke.RdParams, tc.V, []), ...
                'mexitk:RD:volumeB');
        end

        function rdRejectsMismatchedVolumeBClass(tc)
            tc.verifyError(@() mexitk('RD', tPhase6RegistrationSmoke.RdParams, tc.V, single(tc.V)), ...
                'mexitk:RD:volumeBClass');
        end

        function rdRejectsMismatchedVolumeBSize(tc)
            small = tc.V(1:64, 1:64, 1:16);
            big = cat(3, tc.V, tc.V);
            tc.verifyError(@() mexitk('RD', tPhase6RegistrationSmoke.RdParams, tc.V, small), ...
                'mexitk:RD:volumeBSize');
            tc.verifyError(@() mexitk('RD', tPhase6RegistrationSmoke.RdParams, tc.V, big), ...
                'mexitk:RD:volumeBSize');
        end

        function rdRejectsShortParamCount(tc)
            tc.verifyError(@() mexitk('RD', [1024 7 150], tc.V, tc.V), 'mexitk:params');
        end

        function rdRejectsNonFiniteStandardDeviations(tc)
            tc.verifyError(@() mexitk('RD', [1024 7 150 NaN], tc.V, tc.V), ...
                'mexitk:RD:DemonStandardDeviations');
            tc.verifyError(@() mexitk('RD', [1024 7 150 Inf], tc.V, tc.V), ...
                'mexitk:RD:DemonStandardDeviations');
            tc.verifyError(@() mexitk('RD', [1024 7 150 -Inf], tc.V, tc.V), ...
                'mexitk:RD:DemonStandardDeviations');
        end

        function rdRejectsNonFiniteIterationCount(tc)
            % DemonNumberofIterations routes through
            % CastParam<itk::IdentifierType>, which self-guards non-finite
            % (and negative) values under the shared mexitk:paramRange id,
            % same as every other integral CastParam use in this codebase.
            tc.verifyError(@() mexitk('RD', [1024 7 NaN 1], tc.V, tc.V), 'mexitk:paramRange');
            tc.verifyError(@() mexitk('RD', [1024 7 -1 1], tc.V, tc.V), 'mexitk:paramRange');
        end

        function rdRejectsExtraOutputArgument(tc)
            tc.verifyError(@() withOutputs(2, ...
                @() mexitk('RD', tPhase6RegistrationSmoke.RdParams, tc.V, tc.V)), ...
                'mexitk:nargout');
        end

        function rdRejectsZeroHistogramLevels(tc)
            % NumberOfHistogramLevels=0 segfaults the whole MATLAB process
            % (not a catchable exception) inside ITK's own
            % HistogramMatchingImageFilter::ConstructHistogramFromIntensity
            % Range, which underflows an unsigned m_NumberOfHistogramLevels-1
            % to SIZE_MAX and writes out of the histogram's bin range --
            % measured directly, reproduced via a crash dump showing exactly
            % that frame chain, before this guard existed. The threshold is
            % 1, verified empirically: 1 itself is confirmed NOT to crash
            % (see rdRunsAndPreservesShapeAndClass and the case below), so
            % the guard refuses only the measured defect.
            tc.verifyError(@() mexitk('RD', [0 7 5 1], tc.V, tc.V), ...
                'mexitk:RD:NumberOfHistogramLevels');
            % A fractional value that truncates to 0 hits the same guard.
            tc.verifyError(@() mexitk('RD', [0.9 7 5 1], tc.V, tc.V), ...
                'mexitk:RD:NumberOfHistogramLevels');
        end

        function rdAcceptsOneHistogramLevel(tc)
            % The empirically-verified safe boundary immediately above the
            % guard in rdRejectsZeroHistogramLevels: must run and return a
            % finite result, not merely "not crash".
            out = mexitk('RD', [1 7 5 1], tc.V, tc.V);
            tc.verifyClass(out, 'double');
            tc.verifySize(out, size(tc.V));
            tc.verifyTrue(all(isfinite(out(:))));
        end
    end

    methods (Test)  % RTPS
        function rtpsRequiresVolumeB(tc)
            % Both the omitted-arg4 and explicit-[] shapes, mirroring
            % rdRequiresVolumeB: RequireVolumeB (src/mexitk_common.h) runs
            % before any landmark validation, so this fires regardless of
            % whether landmarks were ever supplied.
            landmarks = [70 50 14, 75 55 14];
            tc.verifyError(@() mexitk('RTPS', [], tc.V), 'mexitk:RTPS:volumeB');
            tc.verifyError(@() mexitk('RTPS', [], tc.V, [], landmarks), 'mexitk:RTPS:volumeB');
        end

        function rtpsRejectsEmptyLandmarks(tc)
            tc.verifyError(@() mexitk('RTPS', [], tc.V, tc.V, []), 'mexitk:RTPS:landmarks');
            tc.verifyError(@() mexitk('RTPS', [], tc.V, tc.V), 'mexitk:RTPS:landmarks');
        end

        function rtpsRejectsSingleLandmark(tc)
            % Matches the one captured RTPS fixture
            % (rtps_tps_volB_seedS1_double, see tests/tReferenceRejections.m):
            % the original rejects a single (odd-count) landmark point.
            tc.verifyError(@() mexitk('RTPS', [], tc.V, tc.V, [70 50 14]), 'mexitk:RTPS:landmarks');
        end

        function rtpsRejectsOddLandmarkCount(tc)
            tc.verifyError(@() mexitk('RTPS', [], tc.V, tc.V, ...
                [70 50 14, 30 30 10, 80 80 20]), 'mexitk:RTPS:landmarks');
        end

        function rtpsMinimalValidCaseRunsAndIsFinite(tc)
            % One landmark PAIR (source, target) under the fixture-proven
            % interleaved convention (see tests/tReferenceBounded.m's
            % rtps_pair1_minimal_double case and src/opcodes/rtps.cpp).
            landmarks = [70 50 14, 75 55 14];
            out = mexitk('RTPS', [], tc.V, tc.V, landmarks);
            tc.verifyClass(out, 'double');
            tc.verifySize(out, size(tc.V));
            tc.verifyTrue(all(isfinite(out(:))));
        end

        function rtpsRunsAndPreservesShapeAndClass(tc)
            % Four interleaved (source,target) pairs -- source1,target1,
            % source2,target2,... -- per the fixture-proven convention.
            landmarks = [70 50 14, 76 46 16, 30 30 10, 36 26 12, ...
                90 90 20, 96 86 22, 20 100 5, 26 96 7];
            for f = {@double, @single, @uint8, @int32}
                vin = f{1}(tc.Vu);
                out = mexitk('RTPS', [], vin, vin, landmarks);
                tc.verifyClass(out, class(vin));
                tc.verifySize(out, size(vin));
                tc.verifyTrue(all(isfinite(double(out(:)))), sprintf( ...
                    'RTPS (%s): non-finite value in output', class(vin)));
            end
        end

        function rtpsIdentityLandmarksReproduceInputExactly(tc)
            % A real structural check, not merely a reference comparison:
            % under the fixture-proven INTERLEAVED convention
            % (source1,target1,source2,target2,...; see
            % src/opcodes/rtps.cpp and tests/tReferenceBounded.m's
            % rtps_nc5_identity_double case), a landmark list built from
            % (p_i, p_i) pairs -- source_i == target_i for every i -- is a
            % true no-op thin-plate-spline warp, so calling with
            % volumeA==volumeB must reproduce the input exactly. This is
            % NOT the same landmark list Phase 1's disproven split-half
            % assumption would have called "identity"
            % ([p1 p2 ... pN p1 p2 ... pN]): under the interleaved
            % convention that list pairs p1 with p2, p3 with p4, etc, which
            % is not an identity map at all. Verified exactly (0/442368
            % voxels differ) before writing this assertion.
            pts = [10 10 3; 10 10 20; 10 120 3; 10 120 20; ...
                120 10 3; 120 10 20; 120 120 3; 120 120 20];
            landmarks = zeros(1, size(pts, 1) * 2 * 3);
            for i = 1:size(pts, 1)
                landmarks((i - 1) * 6 + (1:3)) = pts(i, :);
                landmarks((i - 1) * 6 + (4:6)) = pts(i, :);
            end
            out = mexitk('RTPS', [], tc.V, tc.V, landmarks);
            tc.verifyEqual(out, tc.V);
        end

        function rtpsRejectsMismatchedVolumeBClass(tc)
            % Mirrors rdRejectsMismatchedVolumeBClass: RequireVolumeB
            % (src/mexitk_common.h) is the shared code path both RD and
            % RTPS call, so the class check is opcode-agnostic; only RD's
            % own suite exercised it before.
            landmarks = [70 50 14, 75 55 14];
            tc.verifyError(@() mexitk('RTPS', [], tc.V, single(tc.V), landmarks), ...
                'mexitk:RTPS:volumeBClass');
        end

        function rtpsRejectsMismatchedVolumeBSize(tc)
            landmarks = [70 50 14, 75 55 14];
            small = tc.V(1:64, 1:64, 1:16);
            tc.verifyError(@() mexitk('RTPS', [], tc.V, small, landmarks), ...
                'mexitk:RTPS:volumeBSize');
        end

        function rtpsRejectsOutOfBoundsLandmark(tc)
            % Landmarks are validated through the same SeedPointsToIndices
            % convention as every other seed: 1-based, exclusive upper
            % bound at each dimension's own size (docs/COMPATIBILITY.md).
            tc.verifyError(@() mexitk('RTPS', [], tc.V, tc.V, ...
                [70 50 14, 9999 9999 9999]), 'mexitk:seeds');
        end

        function rtpsRejectsExtraOutputArgument(tc)
            landmarks = [70 50 14, 75 55 14];
            tc.verifyError(@() withOutputs(2, ...
                @() mexitk('RTPS', [], tc.V, tc.V, landmarks)), 'mexitk:nargout');
        end
    end
end

function varargout = withOutputs(n, fn)
% Calls fn requesting exactly n outputs, so nargout handling can be tested.
varargout = cell(1, n);
[varargout{1:n}] = fn();
end
