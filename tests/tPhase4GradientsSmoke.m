classdef tPhase4GradientsSmoke < matlab.unittest.TestCase
    % Smoke tests for the Phase 4 gradient/feature filter opcodes. No
    % reference fixtures exist for these, so the suite asserts structural
    % invariants (shape, class, smoothing/monotonicity properties, and
    % ITK's own documented semantics) rather than bit-exactness. Every
    % non-guaranteed assertion here was empirically confirmed against a
    % real build before being committed; none is guessed from the ITK
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

    properties (TestParameter)
        op      = {'FAAB', 'FBL', 'FCF', 'FGAD', 'FGM', 'FGMRG', 'FLS', 'FVMI'};
        paramOp = {'FAAB', 'FBL', 'FCF', 'FGAD', 'FGMRG', 'FLS', 'FVMI'};  % FGM excluded: zero params
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
                case 'FAAB';  p = [0.01 50 2];  % registry hints; measured 0.91s, fine
                case 'FBL';   p = [2 10];       % NOT the registry hint [5 5]: measured
                              % [5 5] at 5.6s/call is too slow across 4 pixel
                              % types x several tests; [2 10] measured at
                              % 0.25s/call and still exercises the filter
                              % meaningfully. Hint values are not sacred for
                              % tests (plan explicit).
                case 'FCF';   p = [10 0.0625];  % registry hints
                case 'FGAD';  p = [5 0.0625 3]; % mirrors the FCA test point
                case 'FGM';   p = [];
                case 'FGMRG'; p = 2;
                case 'FLS';   p = 2;
                case 'FVMI';  p = [1 0.5 2];    % sigma 1; 0.5/2.0 canonical Sato alphas
            end
        end
    end

    methods (Test)  % parameterized common checks
        function runsAndPreservesShapeAndClass(tc, op)
            % Measured: all 8 ops x all 4 classes run clean, ~4s total.
            p = tPhase4GradientsSmoke.validParams(op);
            for f = {@double, @single, @uint8, @int32}
                vin = f{1}(tc.Vu);
                out = mexitk(op, p, vin);
                tc.verifyClass(out, class(vin));
                tc.verifySize(out, size(vin));
            end
        end

        function rejectsShortParamCount(tc, paramOp)
            p = tPhase4GradientsSmoke.validParams(paramOp);
            short = p(1:end-1);
            tc.verifyError(@() mexitk(paramOp, short, tc.V), 'mexitk:params');
        end

        function fgmRunsWithEmptyParams(tc)
            % Explicit zero-param check per the architecture, complementing
            % runsAndPreservesShapeAndClass above.
            out = mexitk('FGM', [], tc.V);
            tc.verifyClass(out, 'double');
            tc.verifySize(out, size(tc.V));
        end
    end

    methods (Test)  % FGM
        function fgmChangesInput(tc)
            for f = {@double, @uint8}
                vin = f{1}(tc.Vu);
                out = mexitk('FGM', [], vin);
                tc.verifyNotEqual(out, vin);
            end
        end

        function fgmNonNegativeOnDouble(tc)
            % Mathematically guaranteed for a magnitude; still measured
            % before commit per project protocol. Verified: min = 0.
            out = mexitk('FGM', [], tc.V);
            tc.verifyGreaterThanOrEqual(min(out(:)), 0);
        end

        function fgmFlatRegionHasZeroGradient(tc)
            % V(1:8,1:8,2:6) is a constant all-zero air region on this
            % volume (verified programmatically, not assumed); the
            % gradient magnitude at its interior (away from the block's
            % own edges, where central differences would reach outside
            % the constant region) must be exactly 0. Measured: holds
            % exactly, max value in that interior is 0.
            block = tc.V(1:8, 1:8, 2:6);
            tc.assumeTrue(numel(unique(block)) == 1, ...
                'Expected constant block not constant on this volume; skipping.');
            out = mexitk('FGM', [], tc.V);
            interior = out(2:7, 2:7, 3:5);
            tc.verifyEqual(interior, zeros(size(interior)));
        end

        function fgmIntegralExportMatchesFloorOfDouble(tc)
            % Pins the int32/uint8 double-accumulate-then-ClampExport path
            % with a value-level assertion, so the bit-identity guarantee
            % established during review cannot silently rot. Both integral
            % exports go through the same "compute in double, static_cast
            % back" arithmetic ITK's own native path used, which for
            % nonnegative in-range values is exactly floor() truncation.
            % Verified empirically before writing this assertion: on this
            % volume gradient magnitude tops out at ~76.21 (well under
            % both uint8's 255 and int32's range, so no saturation case is
            % exercised here), and double(outInt)/double(outU8) equal
            % floor(outDbl) with 0 mismatches across all 442368 voxels for
            % both integral types.
            outDbl = mexitk('FGM', [], tc.V);
            outI32 = mexitk('FGM', [], int32(tc.Vu));
            outU8  = mexitk('FGM', [], tc.Vu);

            tc.verifyEqual(double(outI32), floor(outDbl));
            tc.verifyEqual(double(outU8), floor(outDbl));
        end
    end

    methods (Test)  % FGMRG (vs FGM)
        function fgmrgDiffersFromFgm(tc)
            % Different algorithms for the same conceptual quantity
            % (recursive Gaussian derivative vs central difference); see
            % docs/COMPATIBILITY.md "FGM vs FGMRG".
            outFgmrg = mexitk('FGMRG', 2, tc.V);
            outFgm = mexitk('FGM', [], tc.V);
            tc.verifyNotEqual(outFgmrg, outFgm);
        end

        function fgmrgLargerSigmaSmoothsGradientMap(tc)
            % Measured: std(sigma=1)=6.676, std(sigma=4)=1.643.
            out1 = mexitk('FGMRG', 1, tc.V);
            out4 = mexitk('FGMRG', 4, tc.V);
            tc.verifyLessThan(std(out4(:)), std(out1(:)));
        end
    end

    methods (Test)  % FLS
        function flsLargerSigmaSmooths(tc)
            % Measured: std(sigma=1)=7.279, std(sigma=4)=0.405.
            out1 = mexitk('FLS', 1, tc.V);
            out4 = mexitk('FLS', 4, tc.V);
            tc.verifyLessThan(std(out4(:)), std(out1(:)));
        end

        function flsHasBothSignsOnDouble(tc)
            % A Laplacian on real data produces both signs. Measured:
            % min=-10.22, max=9.50 at sigma=2.
            out = mexitk('FLS', 2, tc.V);
            tc.verifyLessThan(min(out(:)), 0);
            tc.verifyGreaterThan(max(out(:)), 0);
        end

        function flsUint8ClampMatchesSinglePath(tc)
            % Strong version, per the plan: uint8 promotes to float, and
            % single input IS float, so the internal pipelines are
            % identical up to the export step. Measured directly: exact
            % match, 0 mismatches out of 442368 voxels -- the float
            % rounding-at-bin-edges concern the plan flagged did not
            % materialize on this data, so the strong (not weakened)
            % assertion is used.
            outSingle = mexitk('FLS', 2, single(tc.Vu));
            outUint8 = mexitk('FLS', 2, tc.Vu);
            expected = uint8(floor(min(max(double(outSingle), 0), 255)));
            tc.verifyEqual(outUint8, expected);
        end
    end

    methods (Test)  % FBL
        function fblSmoothsAndDiffersFromGaussian(tc)
            % domainSigma 2 == FDG variance 4, so the domain kernels are
            % comparable; range weighting must change the result. Measured:
            % std decreases (30.30 -> 30.13, a small but real decrease at
            % these params), and bit-equality with FDG (a different
            % algorithm) is not observed.
            out = mexitk('FBL', [2 10], tc.V);
            tc.verifyLessThan(std(out(:)), std(tc.V(:)));
            tc.verifyNotEqual(out, tc.V);
            outFdg = mexitk('FDG', [4 5], tc.V);
            tc.verifyNotEqual(out, outFdg);
        end

        function fblDomainAndRangeSigmaAreNotInterchangeable(tc)
            % Catches a param-order bug where domainSigma and rangeSigma got
            % swapped in the C++ wiring. Measured: [2 10] gives std=30.1274
            % (< 30.2); the swapped call [10 2] gives std=30.2961 (>=
            % 30.2), a real, measured difference, not an invented bound.
            out = mexitk('FBL', [2 10], tc.V);
            tc.verifyLessThan(std(out(:)), 30.2);
        end
    end

    methods (Test)  % FGAD (vs FCA)
        function fgadDiffersFromFcaAtIdenticalParams(tc)
            % Gradient vs curvature conductance should differ on real data.
            outFgad = mexitk('FGAD', [5 0.0625 3], tc.V);
            outFca = mexitk('FCA', [5 0.0625 3], tc.V);
            tc.verifyNotEqual(outFgad, outFca);
        end

        function fgadSmooths(tc)
            % Measured: std 30.30 -> 29.01.
            out = mexitk('FGAD', [5 0.0625 3], tc.V);
            tc.verifyLessThan(std(out(:)), std(tc.V(:)));
        end

        function fgadIterationsAndConductanceAreNotInterchangeable(tc)
            % Catches a param-order bug where numberOfIterations and
            % conductance got swapped. Measured: [2 0.0625 40] (2 iters,
            % conductance 40) gives std=29.0735 (> 28.5); the
            % swapped-equivalent call (what wiring iterations<->conductance
            % backwards would produce for this same input, i.e.
            % [40 0.0625 2]) gives std=28.0757, comfortably below the bound.
            out = mexitk('FGAD', [2 0.0625 40], tc.V);
            tc.verifyGreaterThan(std(out(:)), 28.5);
        end

        function fgadTimeStepAndConductanceAreNotInterchangeable(tc)
            % Catches a param-order bug where timeStep and conductance got
            % swapped. Measured: [5 0.0625 10] gives std=28.3072 (< 29.5);
            % the swapped-equivalent call ([5 10 0.0625], i.e. timeStep=10
            % conductance=0.0625) is numerically unstable and GROWS past
            % the input's own std (30.3218 > 30.2985), comfortably above
            % the bound.
            out = mexitk('FGAD', [5 0.0625 10], tc.V);
            tc.verifyLessThan(std(out(:)), 29.5);
        end
    end

    methods (Test)  % FCF
        function fcfSmooths(tc)
            % Measured: std 30.30 -> 29.20.
            out = mexitk('FCF', [10 0.0625], tc.V);
            tc.verifyLessThan(std(out(:)), std(tc.V(:)));
        end

        function fcfMoreIterationsSmoothMore(tc)
            % Measured: std(iters=5)=29.52, std(iters=20)=28.82.
            out5 = mexitk('FCF', [5 0.0625], tc.V);
            out20 = mexitk('FCF', [20 0.0625], tc.V);
            tc.verifyLessThan(std(out20(:)), std(out5(:)));
        end
    end

    methods (Test)  % FAAB (measure first, assert only measured properties)
        function faabProducesSignedLevelSetOnDouble(tc)
            % B: 255 * double(Vu > 33), the Phase 3-measured Otsu cut
            % intensity for this volume; any clean binarization works.
            % Measured directly, not assumed from the header: min=-3,
            % max=3 (both signs present); sign orientation matches the
            % header's inside-positive/outside-negative claim on the large
            % majority of voxels but NOT all (98.5% of foreground voxels
            % are positive, 97.2% of background voxels are negative --
            % the remainder sit near the estimated zero-crossing surface,
            % which is expected for a level-set method). Only the
            % measured majority-fraction claim is asserted, not 100%.
            %
            % Residual gap, documented rather than silently ignored: a
            % maximumRMSError<->numberOfIterations param-order swap is a
            % KNOWN undetected case for this test file. The only signal
            % found during review was sign-purity (100% vs the 98.5%
            % measured above for correct wiring), which is too fragile a
            % margin to assert reliably -- it is not backed by a
            % comfortably-separated measured bound the way the other
            % not-interchangeable tests in this file are, so it is not
            % asserted here.
            B = 255 * double(tc.Vu > 33);
            out = mexitk('FAAB', [0.01 50 2], B);
            tc.verifyNotEqual(out, B);
            tc.verifyLessThan(min(out(:)), 0);
            tc.verifyGreaterThan(max(out(:)), 0);
            fgIdx = (B == 255);
            bgIdx = (B == 0);
            tc.verifyGreaterThan(mean(out(fgIdx) > 0), 0.9);
            tc.verifyGreaterThan(mean(out(bgIdx) < 0), 0.9);
        end

        function faabLayersControlsValueRange(tc)
            % Catches a param-order bug where numberOfIterations and
            % numberOfLayers got swapped (both are IdentifierType/unsigned
            % int, so a swap would not be caught by CastParam). Measured on
            % the same binarization: layers=1 gives max=2 (< 5); layers=50
            % gives max=51 (> 20) -- numberOfLayers genuinely controls how
            % far the level-set field extends, a real, measured effect.
            B = 255 * double(tc.Vu > 33);
            out1 = mexitk('FAAB', [0.01 50 1], B);
            tc.verifyLessThan(max(out1(:)), 5);
            out50 = mexitk('FAAB', [0.01 50 50], B);
            tc.verifyGreaterThan(max(out50(:)), 20);
        end

        function faabUint8ClampsOutsideToZero(tc)
            % Same binarization in uint8. Measured: class uint8, min=0,
            % and a substantial fraction (72.8%) of voxels are exactly 0
            % -- the outside-negative half of the level set saturating on
            % export, exactly as documented. The cross-check against the
            % double path's sign pattern is included since the measured
            % correspondence (94.97% agreement) is reasonably clean, with
            % a bound safely under the measured value.
            Bu = uint8(255 * (tc.Vu > 33));
            B = 255 * double(tc.Vu > 33);
            out = mexitk('FAAB', [0.01 50 2], Bu);
            outDouble = mexitk('FAAB', [0.01 50 2], B);
            tc.verifyClass(out, 'uint8');
            tc.verifyEqual(min(out(:)), uint8(0));
            tc.verifyGreaterThan(mean(out(:) == 0), 0.5);
            crossAgree = mean((out(:) == 0) == (outDouble(:) <= 0));
            tc.verifyGreaterThan(crossAgree, 0.9);
        end
    end

    methods (Test)  % FVMI
        function fvmiRunsAndIsNonNegative(tc)
            % Non-vessel voxels are exactly 0 by construction
            % (itkHessian3DToVesselnessMeasureImageFilter.hxx:87);
            % vessel-measure sign must be measured, not assumed. Measured:
            % min=0, max=19.84, 249505 of 442368 voxels exactly 0.
            out = mexitk('FVMI', [1 0.5 2], tc.V);
            tc.verifyGreaterThanOrEqual(min(out(:)), 0);
        end

        function fvmiRespondsToSigma(tc)
            out1 = mexitk('FVMI', [1 0.5 2], tc.V);
            out3 = mexitk('FVMI', [3 0.5 2], tc.V);
            tc.verifyNotEqual(out1, out3);
        end

        function fvmiAlphasAreNotInterchangeable(tc)
            % Catches a param-order bug where alpha1 and alpha2 got
            % swapped. Measured: [1 0.5 2] gives nnz(~=0)=192863 (> 180000);
            % the swapped call [1 2 0.5] gives nnz(~=0)=161784, comfortably
            % below the bound -- the vessel/non-vessel classification
            % genuinely depends on which alpha lands on which Sato term.
            out = mexitk('FVMI', [1 0.5 2], tc.V);
            tc.verifyGreaterThan(nnz(out(:) ~= 0), 180000);
        end
    end

    methods (Test)  % error paths (CastParam / ITK-exception)
        % None of the 8 opcodes has a parameter whose CastParam target
        % depends on the input pixel type (targets are only double,
        % unsigned int, or itk::IdentifierType), unlike Phase 1/3's
        % out-of-range-on-uint8 paramRange tests (FBT 300, SCC replace
        % 300). There is no Phase 4 analogue of that pattern.
        function faabRejectsNegativeIterations(tc)
            tc.verifyError(@() mexitk('FAAB', [0.01 -1 2], tc.V), 'mexitk:paramRange');
        end

        function faabRejectsNegativeLayers(tc)
            tc.verifyError(@() mexitk('FAAB', [0.01 50 -1], tc.V), 'mexitk:paramRange');
        end

        function fcfRejectsNegativeIterations(tc)
            tc.verifyError(@() mexitk('FCF', [-1 0.0625], tc.V), 'mexitk:paramRange');
        end

        function fgadRejectsNegativeIterations(tc)
            tc.verifyError(@() mexitk('FGAD', [-5 0.0625 3], tc.V), 'mexitk:paramRange');
        end

        function fgmrgRejectsNonPositiveSigma(tc)
            % ITK's own catchable exception ("Sigma must be greater than
            % zero.", itkRecursiveGaussianImageFilter.hxx:330-333), not a
            % mexitk guard: this is ITK failing loudly on its own.
            % Verified directly on the real build.
            tc.verifyError(@() mexitk('FGMRG', 0, tc.V), 'mexitk:itkException');
        end

        function fgmrgRejectsNonFiniteSigma(tc)
            % ITK's own `<= 0.0` exception guard does not catch NaN;
            % verified directly before this mexitk-level guard existed, a
            % NaN sigma silently returned an all-NaN output, no exception.
            % The sign constraint above is unchanged; only the non-finite
            % gap is new (param-guard hardening, Epic 3 issue #26).
            tc.verifyError(@() mexitk('FGMRG', NaN, tc.V), 'mexitk:FGMRG:sigma');
            tc.verifyError(@() mexitk('FGMRG', Inf, tc.V), 'mexitk:FGMRG:sigma');
        end

        function flsRejectsNonPositiveSigma(tc)
            % Same ITK exception as FGMRG above (shared RecursiveGaussian
            % base). Verified directly.
            tc.verifyError(@() mexitk('FLS', 0, tc.V), 'mexitk:itkException');
        end

        function flsRejectsNonFiniteSigma(tc)
            % Same rationale as FGMRG's own non-finite guard.
            tc.verifyError(@() mexitk('FLS', NaN, tc.V), 'mexitk:FLS:sigma');
            tc.verifyError(@() mexitk('FLS', Inf, tc.V), 'mexitk:FLS:sigma');
        end

        function fvmiRejectsNonPositiveSigma(tc)
            % Same underlying exception via the Hessian stage's recursive
            % Gaussian passes. Verified directly.
            tc.verifyError(@() mexitk('FVMI', [0 0.5 2], tc.V), 'mexitk:itkException');
        end

        function fvmiRejectsNonFiniteParams(tc)
            % None of SetSigma/SetAlpha1/SetAlpha2 had a prior mexitk-level
            % constraint (unlike FLS/FGMRG's sigma, ITK itself does not
            % reject a NaN or non-positive alpha1/alpha2). Verified
            % directly: a NaN SetSigma silently returned an all-zero
            % output; NaN SetAlpha1/SetAlpha2 each silently propagated into
            % the output. Only non-finite is guarded, no new sign/range
            % constraint (param-guard hardening, Epic 3 issue #26).
            tc.verifyError(@() mexitk('FVMI', [NaN 0.5 2], tc.V), 'mexitk:FVMI:SetSigma');
            tc.verifyError(@() mexitk('FVMI', [Inf 0.5 2], tc.V), 'mexitk:FVMI:SetSigma');
            tc.verifyError(@() mexitk('FVMI', [1 NaN 2], tc.V), 'mexitk:FVMI:SetAlpha1');
            tc.verifyError(@() mexitk('FVMI', [1 0.5 NaN], tc.V), 'mexitk:FVMI:SetAlpha2');
        end

        function fblRejectsNegativeDomainSigma(tc)
            % negative domainSigma reaches a raw (SizeValueType)ceil(...)
            % cast of a negative double inside ITK's own
            % GenerateInputRequestedRegion -- undefined behaviour, not
            % reproducible; rejected before it can happen.
            tc.verifyError(@() mexitk('FBL', [-5 5], tc.V), 'mexitk:FBL:domainSigma');
        end

        function fblRejectsNonFiniteDomainSigma(tc)
            % `<= 0.0` does not catch NaN either; verified directly, a NaN
            % domainSigma reached the same silent all-NaN path as
            % domainSigma == 0 above, no exception (param-guard hardening,
            % Epic 3 issue #26).
            tc.verifyError(@() mexitk('FBL', [NaN 5], tc.V), 'mexitk:FBL:domainSigma');
            tc.verifyError(@() mexitk('FBL', [Inf 5], tc.V), 'mexitk:FBL:domainSigma');
        end

        function fblRejectsZeroDomainSigma(tc)
            % domainSigma == 0 is a distinct failure from the negative
            % case: GaussianSpatialFunction::Evaluate divides by
            % 2*sigma*sigma while building the kernel, so every non-center
            % kernel weight is a division by zero and the center itself is
            % 0.0/0.0 -- both NaN, silently: no exception, all-NaN output
            % on double, uniformly zero on uint8. Verified directly before
            % this guard existed.
            tc.verifyError(@() mexitk('FBL', [0 5], tc.V), 'mexitk:FBL:domainSigma');
        end

        function fblRejectsNonPositiveRangeSigma(tc)
            % rangeSigma <= 0 collapses the accumulation loop's threshold to
            % <= 0, so normFactor never accumulates and val /= normFactor is
            % 0.0/0.0 = NaN, written by a raw native cast INSIDE ITK's own
            % filter (before mexitk's export step -- ClampExport cannot
            % help here, unlike the promoted opcodes). Verified directly.
            tc.verifyError(@() mexitk('FBL', [2 0], tc.V), 'mexitk:FBL:rangeSigma');
        end

        function fblRejectsNonFiniteRangeSigma(tc)
            % Same non-finite gap as domainSigma above, on rangeSigma
            % instead (param-guard hardening, Epic 3 issue #26).
            tc.verifyError(@() mexitk('FBL', [2 NaN], tc.V), 'mexitk:FBL:rangeSigma');
            tc.verifyError(@() mexitk('FBL', [2 Inf], tc.V), 'mexitk:FBL:rangeSigma');
        end

        function fcaRejectsNegativeTimeStep(tc)
            % A negative timeStep runs the diffusion backward in time
            % (ill-posed); the original's behaviour on this input is
            % unknown, so it is rejected rather than reproduced. timeStep
            % == 0 stays accepted as a defined no-op (not tested here, but
            % relied upon by fixture tests elsewhere, which still pass).
            tc.verifyError(@() mexitk('FCA', [5 -1 3], tc.V), 'mexitk:FCA:timeStep');
        end

        function fcaRejectsNonFiniteTimeStep(tc)
            % A plain `< 0.0` guard does not catch NaN or +Inf (NaN compares
            % false against every ordered relational operator; +Inf does
            % not compare < 0.0): verified directly before this guard
            % existed, a NaN timeStep silently produced an all-NaN output
            % on every voxel, and +Inf silently produced a mix of NaN and
            % Inf values, both with no exception. -Inf was already caught
            % by the old `< 0.0` guard.
            tc.verifyError(@() mexitk('FCA', [5 NaN 3], tc.V), 'mexitk:FCA:timeStep');
            tc.verifyError(@() mexitk('FCA', [5 Inf 3], tc.V), 'mexitk:FCA:timeStep');
            tc.verifyError(@() mexitk('FCA', [5 -Inf 3], tc.V), 'mexitk:FCA:timeStep');
        end

        function fcfRejectsNegativeTimeStep(tc)
            tc.verifyError(@() mexitk('FCF', [10 -1], tc.V), 'mexitk:FCF:timeStep');
        end

        function fcfRejectsNonFiniteTimeStep(tc)
            % A plain `< 0.0` guard does not catch NaN (every ordered
            % comparison against NaN is false): verified directly before
            % this guard existed, a NaN or +Inf timeStep silently produced
            % an all-NaN output on every voxel, no exception. -Inf is
            % rejected the same way as any other non-finite value.
            tc.verifyError(@() mexitk('FCF', [10 NaN], tc.V), 'mexitk:FCF:timeStep');
            tc.verifyError(@() mexitk('FCF', [10 Inf], tc.V), 'mexitk:FCF:timeStep');
            tc.verifyError(@() mexitk('FCF', [10 -Inf], tc.V), 'mexitk:FCF:timeStep');
        end

        function fgadRejectsNegativeTimeStep(tc)
            tc.verifyError(@() mexitk('FGAD', [5 -1 3], tc.V), 'mexitk:FGAD:timeStep');
        end

        function fgadRejectsNonFiniteTimeStep(tc)
            % Same rationale as FCA's own non-finite guard (shared
            % AnisotropicDiffusionImageFilter base): verified directly, a
            % NaN or +Inf timeStep silently produced an all-NaN output on
            % every voxel, no exception.
            tc.verifyError(@() mexitk('FGAD', [5 NaN 3], tc.V), 'mexitk:FGAD:timeStep');
            tc.verifyError(@() mexitk('FGAD', [5 Inf 3], tc.V), 'mexitk:FGAD:timeStep');
            tc.verifyError(@() mexitk('FGAD', [5 -Inf 3], tc.V), 'mexitk:FGAD:timeStep');
        end
    end
end
