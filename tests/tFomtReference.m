classdef tFomtReference < matlab.unittest.TestCase
    % Reference tests for FOMT (Otsu multiple thresholds).
    %
    % FOMT reproduces the original bit-for-bit on floating-point input at
    % every captured threshold count, and on uint8 input at N=1, so these
    % are equality assertions, not tolerances. uint8 at N=2,3,4 does NOT
    % reproduce bit-for-bit (see uint8DeviationStaysWithinMeasuredBound):
    % Epic 2 Phase 3 investigated this directly (tried, and ruled out, the
    % same histogram-auto-range root cause that explained SOT's own
    % deviation) and confirmed it is a genuine ITK 2.4-to-5.x difference in
    % integral histogram binning, not a mexitk bug. See
    % docs/COMPATIBILITY.md and FomtOpcode::StatusNote.
    %
    % SPDX-License-Identifier: BSD-3-Clause
    % Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
    % Swartz Center for Computational Neuroscience (SCCN),
    % Institute for Neural Computation (INC), UC San Diego.

    properties (TestParameter)
        % Every (N, class) combination captured from the original that is
        % bit-exact AND uses the multi-output fixture shape (numel(outs)
        % == N, one mask per threshold; see bitIdenticalToOriginal). N=2
        % and N=4 are the threshold counts NFT itself uses (segm_scalp,
        % segm_brain). N=1's fixtures (fomt_1_128_double/uint8) are
        % single-output-shaped instead (a single mask, no cell array) and
        % are asserted separately by n1IsBitIdenticalIncludingUint8 below.
        exactCase = {'fomt_N2_bins50_double', 'fomt_N2_bins50_single', ...
                     'fomt_N3_bins128_double', 'fomt_N3_bins128_single', ...
                     'fomt_N4_bins100_double', 'fomt_N4_bins100_single'};

        % uint8's worst-output voxel disagreement fraction, per N,
        % measured directly (see uint8DeviationStaysWithinMeasuredBound).
        % Struct rather than a plain cell array so each case runs as its
        % own independent test (one bad fixture does not abort the
        % others), matching the pattern tests/tReferenceBounded.m uses;
        % each value carries its own fixture name since the field name
        % itself is not passed to the test method.
        uint8DeviationCase = struct( ...
            'fomt_N2_bins50_uint8', struct('name', 'fomt_N2_bins50_uint8', ...
                'measured', 0.0017067238), ...
            'fomt_N3_bins128_uint8', struct('name', 'fomt_N3_bins128_uint8', ...
                'measured', 0.0038361726), ...
            'fomt_N4_bins100_uint8', struct('name', 'fomt_N4_bins100_uint8', ...
                'measured', 0.0084205910));
    end

    methods (Test)

        function bitIdenticalToOriginal(tc, exactCase)
            % The core claim of the project for this opcode: identical output,
            % not merely close output.
            [fx, vin] = mexitkFixture(exactCase);
            N = fx.params(1);
            outs = cell(1, N);
            [outs{1:N}] = mexitk('FOMT', fx.params, vin);

            tc.verifyNumElements(outs, N);
            for k = 1:N
                tc.verifyClass(outs{k}, fx.outputClasses{k}, ...
                    sprintf('output %d class must match the original', k));
                tc.verifyEqual(outs{k}, fx.outputs{k}, ...
                    sprintf('output %d must be bit-identical to matitk', k));
            end
        end

        function n1IsBitIdenticalIncludingUint8(tc)
            % N=1's fixtures (fomt_1_128_double, fomt_1_128_uint8) use the
            % single-output fixture shape, not the multi-output shape
            % exactCase/bitIdenticalToOriginal handle, so they get their
            % own assertion here. uint8 at N=1 is a genuinely different
            % result than uint8 at N=2,3,4 (see the class docstring): the
            % original itself computes only ONE Otsu threshold for N=1,
            % and that single-threshold binning agrees exactly, even
            % though the same ITK-version binning difference causes
            % disagreement once multiple thresholds are computed together.
            for name = {'fomt_1_128_double', 'fomt_1_128_uint8'}
                [fx, vin] = mexitkFixture(name{1});
                out = mexitk('FOMT', fx.params, vin);
                tc.verifyClass(out, fx.outputClass, sprintf( ...
                    '%s: output class must match the original', name{1}));
                tc.verifyEqual(out, fx.output, sprintf( ...
                    '%s: output must be bit-identical to matitk', name{1}));
            end
        end

        function masksAreZeroOr255(tc)
            % The original returns 0/255 masks in the input's own class, not
            % logicals and not 0/1.
            [fx, vin] = mexitkFixture('fomt_N3_bins128_double');
            [a, b, c] = mexitk('FOMT', fx.params, vin);
            for m = {a, b, c}
                tc.verifyEqual(unique(m{1}(:))', [0 255]);
            end
        end

        function topOtsuClassIsDropped(tc)
            % N thresholds yield N+1 classes; the original returns only the
            % lowest N, so the masks must NOT cover the volume. If a future ITK
            % change made this partition the volume, callers relying on not(mask)
            % would silently change meaning, so pin the quirk.
            [fx, vin] = mexitkFixture('fomt_N3_bins128_double');
            [a, b, c] = mexitk('FOMT', fx.params, vin);
            covered = (a > 0) | (b > 0) | (c > 0);
            tc.verifyLessThan(mean(covered(:)), 1, ...
                'masks must not cover the volume; the top class is dropped');

            % Masks are mutually exclusive.
            overlap = (a > 0) + (b > 0) + (c > 0);
            tc.verifyLessThanOrEqual(max(overlap(:)), 1);
        end

        function nargoutMustEqualNumberOfThresholds(tc)
            % The original errors unless nargout == numberOfThresholds exactly.
            [fx, vin] = mexitkFixture('fomt_N3_bins128_double');
            tc.verifyError(@() withOutputs(2, @() mexitk('FOMT', fx.params, vin)), ...
                'mexitk:nargout');
            tc.verifyError(@() withOutputs(4, @() mexitk('FOMT', fx.params, vin)), ...
                'mexitk:nargout');
        end

        function rejectsNonFiniteThresholdsAndBins(tc)
            % numberOfThresholds/numberOfBins previously reached a raw
            % static_cast<int> of a double with no validation at all
            % (OutputCount() runs before Execute(), so this was the FIRST
            % path a NaN/Inf value hit) -- genuine undefined behaviour for
            % a non-finite or wildly out-of-int-range value, not merely a
            % silent-NaN propagation like the other opcodes in this
            % hardening pass. Confirmed the specific failure mode was
            % platform-dependent, not just theoretical: ARM64's saturating
            % float-to-int conversion happened to produce 0 for NaN, caught
            % downstream only by luck via the ordinary nargout-mismatch
            % path, with no such guarantee on other platforms (x86 has its
            % own, differently-undefined conversion behaviour; see the
            % SeedPointsToIndices precedent in mexitk_common.h for the same
            % class of platform divergence). Both parameters now route
            % through CastParam<int> before any use, in both OutputCount()
            % and Execute(), eliminating the UB outright rather than just
            % happening to survive it (param-guard hardening, Epic 3 issue
            % #26). mexFunction calls OutputCount() before Execute(), so a
            % bad numberOfThresholds surfaces via CastParam's own
            % mexitk:paramRange (from OutputCount(), before Execute()'s own
            % mexitk:FOMT:numberOfThresholds range check even runs); a bad
            % numberOfBins with an otherwise-valid numberOfThresholds
            % surfaces the same way from Execute()'s own CastParam call.
            [~, vin] = mexitkFixture('fomt_N3_bins128_double');
            tc.verifyError(@() mexitk('FOMT', [NaN 128], vin), 'mexitk:paramRange');
            tc.verifyError(@() mexitk('FOMT', [Inf 128], vin), 'mexitk:paramRange');
            tc.verifyError(@() mexitk('FOMT', [-Inf 128], vin), 'mexitk:paramRange');
            tc.verifyError(@() mexitk('FOMT', [1e20 128], vin), 'mexitk:paramRange');
            tc.verifyError(@() withOutputs(3, @() mexitk('FOMT', [3 NaN], vin)), ...
                'mexitk:paramRange');
            tc.verifyError(@() withOutputs(3, @() mexitk('FOMT', [3 Inf], vin)), ...
                'mexitk:paramRange');
        end

        function uint8DeviationStaysWithinMeasuredBound(tc, uint8DeviationCase)
            % uint8 does NOT match the original: ITK changed how integral pixel
            % types are binned into the Otsu histogram since 2.4. This asserts
            % the measured WORST-output disagreement fraction per N, tightened
            % from an earlier flat 2% ceiling (loose enough to hide a real
            % change in any of the three cases -- the true values are 0.17%,
            % 0.38%, and 0.84%) to per-N bounds at the measured value, with
            % the same 10% headroom / floor and "did it get suspiciously
            % better" guard pattern tests/tReferenceBounded.m uses. Every
            % number here was read off an actual comparison run
            % (tools/classify_fixtures.m), not estimated or tuned to pass.
            name = uint8DeviationCase.name;
            measured = uint8DeviationCase.measured;

            [fx, vin] = mexitkFixture(name);
            N = fx.params(1);
            outs = cell(1, N);
            [outs{1:N}] = mexitk('FOMT', fx.params, vin);
            worst = 0;
            for k = 1:N
                d = mean(double(outs{k}(:)) ~= double(fx.outputs{k}(:)));
                worst = max(worst, d);
            end

            ceiling = max(measured * 1.1, measured + 1e-6);
            tc.verifyLessThan(worst, ceiling, sprintf( ...
                '%s: worst-output disagreement %.6f%% exceeds documented %.6f%%', ...
                name, 100 * worst, 100 * measured));
            tc.verifyGreaterThan(worst, measured * 0.5, sprintf( ...
                ['%s: now agrees with matitk far better than documented ' ...
                 '(%.6f%% vs %.6f%%); re-baseline and update docs/COMPATIBILITY.md'], ...
                name, 100 * worst, 100 * measured));
        end
    end
end

function varargout = withOutputs(n, fn)
% Calls fn requesting exactly n outputs, so nargout handling can be tested.
varargout = cell(1, n);
[varargout{1:n}] = fn();
end
