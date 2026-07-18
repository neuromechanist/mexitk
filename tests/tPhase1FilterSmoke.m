classdef tPhase1FilterSmoke < matlab.unittest.TestCase
    % Smoke tests for the Phase 1 filter opcodes. No reference fixtures exist
    % for these, so the suite asserts structural invariants (shape, class,
    % parameter validation, and per-filter behaviour) rather than bit-exactness.
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
            p = tPhase1FilterSmoke.validParams(op);
            for f = {@double, @uint8}
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

        function sigmoidStaysWithinOutputRange(tc)
            lo = 10; hi = 240;
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                out = mexitk('FSN', [lo hi 10 170], vin);
                tc.verifyGreaterThanOrEqual(min(double(out(:))), lo);
                tc.verifyLessThanOrEqual(max(double(out(:))), hi);
            end
        end

        function medianZeroRadiusIsIdentity(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                tc.verifyEqual(mexitk('FMEDIAN', [0 0 0], vin), vin);
            end
        end

        function meanZeroRadiusIsIdentity(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                tc.verifyEqual(mexitk('FMEAN', [0 0 0], vin), vin);
            end
        end

        function gaussianSmoothsAndReducesVariance(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                out = mexitk('FDG', [4 5], vin);
                tc.verifyNotEqual(out, vin);
                tc.verifyLessThan(std(double(out(:))), std(double(vin(:))));
            end
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

        function binomialBlurRunsWithOneRepetition(tc)
            out = mexitk('FBB', 1, tc.V);
            tc.verifySize(out, size(tc.V));
            tc.verifyNotEqual(out, tc.V);
        end
    end
end
