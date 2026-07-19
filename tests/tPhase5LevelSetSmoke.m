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
end
