classdef tPhase7DispositionsSmoke < matlab.unittest.TestCase
    % Smoke tests for the Phase 7 (Epic 4 Phase 2) opcode dispositions:
    % FFFT and FGMS. SCSS's own disposition (a deliberate refusal, not an
    % implementation) is exercised in tests/tReferenceRejections.m instead,
    % since it already has a captured fixture proving the original itself
    % succeeded on that input.
    %
    % FFFT (kBoundedDeviation, promoted from kSmokeTested by a follow-up
    % s15 controlled-capture round) has its packing fully confirmed and
    % its double-precision fixtures covered in tests/tReferenceExact.m /
    % tests/tReferenceBounded.m -- see src/opcodes/ffft.cpp's StatusNote
    % for the full evidence trail. This suite adds only what the
    % double-only fixtures do not cover: structural invariants (shape,
    % class, finiteness, both output modes, across all four pixel types),
    % the same role tPhase6RegistrationSmoke.m plays for RD/RTPS.
    %
    % FGMS (kBoundedDeviation) already has full reference-fixture coverage
    % in tests/tReferenceBounded.m (it measures the identical residual as
    % FGMRG, since the two are a registry duplicate -- see
    % src/opcodes/fgmrg.cpp's FgmsOpcode::StatusNote). This suite adds only
    % the guard-path coverage tReferenceBounded.m does not exercise:
    % FGMS's own non-finite/non-positive sigma rejection, mirroring
    % tPhase4GradientsSmoke.m's fgmrgRejectsNonPositiveSigma/
    % fgmrgRejectsNonFiniteSigma, under FGMS's own error id.
    %
    % Every non-guaranteed assertion here was empirically confirmed against
    % a real build before being committed; none is guessed from the ITK
    % header evidence alone.
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

    methods (Test)  % FFFT
        function ffftRealModePreservesShapeAndClass(tc)
            for f = {@double, @single, @uint8, @int32}
                vin = f{1}(tc.Vu);
                out = mexitk('FFFT', 0, vin);
                tc.verifyClass(out, class(vin));
                tc.verifySize(out, size(vin));
                tc.verifyTrue(all(isfinite(double(out(:)))), sprintf( ...
                    'FFFT mode 0 (%s): non-finite value in output', class(vin)));
            end
        end

        function ffftComplexModePreservesShapeAndClass(tc)
            for f = {@double, @single, @uint8, @int32}
                vin = f{1}(tc.Vu);
                out = mexitk('FFFT', 1, vin);
                tc.verifyClass(out, class(vin));
                tc.verifySize(out, size(vin));
                tc.verifyTrue(all(isfinite(double(out(:)))), sprintf( ...
                    'FFFT mode 1 (%s): non-finite value in output', class(vin)));
            end
        end

        function ffftRealModeStaysWithinDeclaredRange(tc)
            % Mode 0's own rescale targets [0,255] explicitly (see
            % src/opcodes/ffft.cpp); a real structural check independent
            % of matching the fixture's exact values.
            out = mexitk('FFFT', 0, tc.V);
            tc.verifyGreaterThanOrEqual(min(out(:)), 0);
            tc.verifyLessThanOrEqual(max(out(:)), 255);
        end

        function ffftIsDeterministicAcrossRuns(tc)
            out1 = mexitk('FFFT', 0, tc.V);
            out2 = mexitk('FFFT', 0, tc.V);
            tc.verifyEqual(out1, out2);
        end

        function ffftRejectsExtraOutputArgument(tc)
            tc.verifyError(@() withOutputs(2, @() mexitk('FFFT', 0, tc.V)), ...
                'mexitk:nargout');
        end

        function ffftModeParamIsUnguardedByDesign(tc)
            % Execute() deliberately leaves the mode parameter unguarded
            % (`p0 != 0.0`, the same FF XDIRECTION/YDIRECTION/ZDIRECTION
            % precedent, deviation 12) rather than restricting it to
            % exactly {0, 1} -- this locks that decision in with a real
            % assertion, not just a code comment, so a future "tighten
            % the guard to {0,1}" change or an accidentally-broken
            % `!= 0.0` (e.g. swapped to `== 1.0`) is caught either
            % direction. Every value here was run against a real build
            % before being asserted, not guessed from the comparison's
            % own IEEE semantics alone.
            ref1 = mexitk('FFFT', 1, tc.V);
            for m = [NaN, Inf, -Inf, 2, -1, 0.5]
                out = mexitk('FFFT', m, tc.V);
                tc.verifyEqual(out, ref1, sprintf( ...
                    'FFFT mode=%g: expected the complex-mode path (== ref1.0), IEEE ~= 0.0 is true for this value', m));
            end

            % -0.0 == 0.0 under IEEE 754, so `p0 != 0.0` is false and this
            % must route to the REAL mode path, the opposite of the block
            % above -- the one value in this test that must NOT match
            % ref1, confirming the comparison direction itself is right
            % and not merely "always true, test is vacuous".
            ref0 = mexitk('FFFT', 0, tc.V);
            outNegZero = mexitk('FFFT', -0.0, tc.V);
            tc.verifyEqual(outNegZero, ref0, ...
                'FFFT mode=-0.0: expected the real-mode path (== ref0), IEEE -0.0 == 0.0');
        end
    end

    methods (Test)  % FGMS guard paths (structural coverage lives in tReferenceBounded.m)
        function fgmsRejectsNonPositiveSigma(tc)
            % Same ITK exception as FGMRG's own guard (shared
            % RecursiveGaussian construction path, src/opcodes/fgmrg.cpp):
            % ITK itself rejects sigma<=0 before mexitk's own finite-guard
            % would ever see it.
            tc.verifyError(@() mexitk('FGMS', 0, tc.V), 'mexitk:itkException');
        end

        function fgmsRejectsNonFiniteSigma(tc)
            % Mirrors fgmrgRejectsNonFiniteSigma (tests/tPhase4GradientsSmoke.m)
            % under FGMS's own error id: ExecuteGradientMagnitudeRecursiveGaussian
            % is shared code, called with "mexitk:FGMS:sigma" for this opcode.
            tc.verifyError(@() mexitk('FGMS', NaN, tc.V), 'mexitk:FGMS:sigma');
            tc.verifyError(@() mexitk('FGMS', Inf, tc.V), 'mexitk:FGMS:sigma');
            tc.verifyError(@() mexitk('FGMS', -Inf, tc.V), 'mexitk:FGMS:sigma');
        end

        function fgmsRunsAndPreservesShapeAndClass(tc)
            for f = {@double, @single, @uint8, @int32}
                vin = f{1}(tc.Vu);
                out = mexitk('FGMS', 2, vin);
                tc.verifyClass(out, class(vin));
                tc.verifySize(out, size(vin));
                tc.verifyTrue(all(isfinite(double(out(:)))), sprintf( ...
                    'FGMS (%s): non-finite value in output', class(vin)));
            end
        end

        function fgmsFixtureMatchesFgmrgFixtureExactly(tc)
            % The registry-duplicate claim (FGMS and FGMRG are the SAME
            % opcode in the original binary, not two independently
            % implemented filters) rests on the two captured fixture
            % SETS agreeing with each other, not merely on prose in
            % FgmsOpcode::StatusNote. Asserted here directly against the
            % fixture files themselves (fx.output), independent of
            % mexitk's own implementation, so a future recapture that
            % broke the alias -- or a StatusNote claim that quietly
            % stopped being true -- is caught by this test rather than
            % only by comment review.
            sigmas = {'1', '2', '4'};
            for i = 1:numel(sigmas)
                [fxGmrg, ~] = mexitkFixture(sprintf('fgmrg_%s_double', sigmas{i}));
                [fxGms, ~] = mexitkFixture(sprintf('fgms_sigma%s_double', sigmas{i}));
                tc.verifyEqual(fxGms.output, fxGmrg.output, sprintf( ...
                    'fgms_sigma%s_double and fgmrg_%s_double fixtures are not bit-identical -- the FGMS/FGMRG alias claim no longer holds', ...
                    sigmas{i}, sigmas{i}));
            end
        end
    end
end

function varargout = withOutputs(n, fn)
% Calls fn requesting exactly n outputs, so nargout handling can be tested.
varargout = cell(1, n);
[varargout{1:n}] = fn();
end
