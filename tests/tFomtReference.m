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

        function uint8DeviationStaysWithinMeasuredBound(tc)
            % uint8 does NOT match the original: ITK changed how integral pixel
            % types are binned into the Otsu histogram since 2.4. This asserts
            % the measured size of that disagreement so a regression (or an
            % accidental fix) shows up as a test failure rather than going
            % unnoticed. The bound is an observation, not a knob tuned to pass.
            for name = {'fomt_N2_bins50_uint8', 'fomt_N3_bins128_uint8', 'fomt_N4_bins100_uint8'}
                [fx, vin] = mexitkFixture(name{1});
                N = fx.params(1);
                outs = cell(1, N);
                [outs{1:N}] = mexitk('FOMT', fx.params, vin);
                for k = 1:N
                    d = mean(double(outs{k}(:)) ~= double(fx.outputs{k}(:)));
                    tc.verifyLessThan(d, 0.02, sprintf( ...
                        ['%s output %d disagrees with matitk on %.3f%% of voxels; ' ...
                         'documented bound is 2%%'], name{1}, k, 100 * d));
                end
            end
        end
    end
end

function varargout = withOutputs(n, fn)
% Calls fn requesting exactly n outputs, so nargout handling can be tested.
varargout = cell(1, n);
[varargout{1:n}] = fn();
end
