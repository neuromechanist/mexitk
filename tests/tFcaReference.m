classdef tFcaReference < matlab.unittest.TestCase
    % Reference tests for FCA (curvature anisotropic diffusion).
    %
    % FCA does NOT reproduce the original bit-for-bit. ITK's anisotropic
    % diffusion numerics changed between 2.4 (the original's build) and 5.x, and
    % because the conductance term is derived from a global average gradient
    % magnitude recomputed each iteration, a small difference perturbs most
    % voxels slightly and compounds with iteration count.
    %
    % These tests therefore pin the *measured* deviation. The bounds below are
    % observations recorded from the actual comparison, set just above the
    % measured values so that any change in either direction fails. They are not
    % tolerances widened until the suite went green: if a bound is ever hit, the
    % correct response is to investigate and update docs/COMPATIBILITY.md, not to
    % raise the number.
    %
    % SPDX-License-Identifier: BSD-3-Clause
    % Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
    % Swartz Center for Computational Neuroscience (SCCN),
    % Institute for Neural Computation (INC), UC San Diego.

    properties (Constant)
        % name, measured RMS, measured max-abs (input intensity range is 0-88).
        % Every value here was read off an actual comparison run; none is an
        % estimate. Regenerate with tools/measure_deviation.m if ITK is upgraded.
        Cases = { ...
            'fca_fca_iter1_ts0p0625_cond3_double', 2.610852e-03, 4.652961e-02; ...
            'fca_fca_iter5_ts0p0625_cond3_double', 5.695774e-03, 1.566523e+00; ...
            'fca_fca_iter1_ts0p0625_cond3_single', 2.646971e-03, 4.717255e-02; ...
            'fca_fca_iter5_ts0p0625_cond3_single', 6.421596e-03, 1.564568e+00};
    end

    methods (Test)

        function deviationMatchesDocumentedBound(tc)
            for i = 1:size(tFcaReference.Cases, 1)
                name = tFcaReference.Cases{i, 1};
                rmsMeasured = tFcaReference.Cases{i, 2};
                maxMeasured = tFcaReference.Cases{i, 3};

                [fx, vin] = mexitkFixture(name);
                got = mexitk('FCA', fx.params, vin);

                tc.verifyClass(got, fx.outputClass);
                tc.verifySize(got, size(fx.output));

                e = abs(double(got(:)) - double(fx.output(:)));
                rms = sqrt(mean(e .^ 2));

                % 10% headroom over the measured value: enough to absorb
                % platform floating-point ordering, far too tight to hide a real
                % behavioural change.
                tc.verifyLessThan(rms, rmsMeasured * 1.1, sprintf( ...
                    '%s RMS deviation %.4g exceeds documented %.4g', name, rms, rmsMeasured));
                tc.verifyLessThan(max(e), maxMeasured * 1.1, sprintf( ...
                    '%s max deviation %.4g exceeds documented %.4g', name, max(e), maxMeasured));

                % Guard the other direction too. If ITK ever starts agreeing with
                % the 2006 build, that is a real change worth noticing rather
                % than silently benefiting from.
                tc.verifyGreaterThan(rms, rmsMeasured * 0.5, sprintf( ...
                    ['%s now agrees with matitk far better than documented ' ...
                     '(RMS %.4g vs %.4g); re-baseline and update COMPATIBILITY.md'], ...
                    name, rms, rmsMeasured));
            end
        end

        function smoothingIsStructurallyFaithful(tc)
            % Independent of bit-exactness, FCA must actually behave like
            % edge-preserving smoothing over the same intensity range, and must
            % not, say, return the input untouched.
            [fx, vin] = mexitkFixture('fca_fca_iter5_ts0p0625_cond3_double');
            got = mexitk('FCA', fx.params, vin);

            tc.verifyLessThan(abs(mean(got(:)) - mean(fx.output(:))), 1e-3, ...
                'mean intensity should track the reference closely');
            tc.verifyNotEqual(got, vin, 'filter must modify the input');
            tc.verifyLessThan(std(got(:)), std(double(vin(:))), ...
                'smoothing must reduce variance');
        end

        function singleAndDoubleAgreeToSinglePrecision(tc)
            % Type dispatch must genuinely instantiate ITK on the input type,
            % but both should describe the same filter.
            [~, vd] = mexitkFixture('fca_fca_iter1_ts0p0625_cond3_double');
            gotD = mexitk('FCA', [1 0.0625 3.0], vd);
            gotS = mexitk('FCA', [1 0.0625 3.0], single(vd));
            tc.verifyClass(gotS, 'single');
            tc.verifyLessThan(max(abs(double(gotS(:)) - gotD(:))), 1e-3);
        end
    end
end
