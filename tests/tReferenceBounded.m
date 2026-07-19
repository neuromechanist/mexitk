classdef tReferenceBounded < matlab.unittest.TestCase
    % Reference tests pinning MEASURED, bounded disagreement with the
    % original matitk binary -- opcodes where mexitk runs the same ITK
    % filter with the same parameters, but the output is not bit-identical
    % because ITK's own numerics evolved between 2.4 (the original's build)
    % and 5.x, or because the original itself used a lower-precision
    % internal representation for one pixel type.
    %
    % Every (RMS, max-abs) pair below is read off an actual comparison run
    % (tools/classify_fixtures.m against the post-Phase-3 tree), never
    % estimated or tuned to make the suite green. Per project policy: if a
    % bound is ever hit, the correct response is to investigate why
    % agreement with the original moved and update docs/COMPATIBILITY.md,
    % never to raise the number. FCA and SWS have their own dedicated
    % suites (tFcaReference.m, tSwsReference.m) and are not repeated here.
    % SWS and FAAB are deliberately excluded even though fixtures exist for
    % FAAB: their measured disagreement (RMS in the hundreds) is not a
    % useful bound to pin, only a fact to document -- see
    % docs/COMPATIBILITY.md, "SWS and FAAB: not bounded".
    %
    % SPDX-License-Identifier: BSD-3-Clause
    % Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
    % Swartz Center for Computational Neuroscience (SCCN),
    % Institute for Neural Computation (INC), UC San Diego.

    properties (TestParameter)
        % One parameterization per row of Cases below, keyed by fixture
        % name (each name is unique and a valid MATLAB identifier, so it
        % doubles as the test-instance name in output). Parameterized
        % rather than a single method looping over Cases: a loop means one
        % bad fixture aborts every case after it in the same test run,
        % where TestParameter runs each case as its own independent test.
        boundedCase = tReferenceBounded.caseParams();
    end

    properties (Constant)
        % opcode, fixture name, measured RMS, measured max-abs.
        Cases = { ...
            ... FDG / FGA: DiscreteGaussianImageFilter numerics moved
            ... between 2.4 and 5.x, same as FCA's own diffusion filter.
            ... FGA is implemented as a deliberate duplicate of FDG (see
            ... docs/COMPATIBILITY.md); their measured numbers are
            ... identical at matching parameters, confirming the alias.
            'FDG', 'fdg_1_5_double',     5.51639e-15, 5.68434e-14; ...
            'FDG', 'fdg_4_5_double',     4.12776e-03, 3.01644e-02; ...
            'FDG', 'fdg_10_5_double',    1.21742e-03, 7.90703e-03; ...
            'FDG', 'fdg_4_5_single',     4.12776e-03, 3.01628e-02; ...
            'FDG', 'fdg_4_5_int32',      2.86817e-01, 2.0;         ...
            'FDG', 'fdg_id_1_5_double',  5.51639e-15, 5.68434e-14; ...
            'FDG', 'fdg_id_4_5_double',  4.12776e-03, 3.01644e-02; ...
            'FDG', 'fdg_id_10_5_double', 1.21742e-03, 7.90703e-03; ...
            'FGA', 'fga_4_5_double',     4.12776e-03, 3.01644e-02; ...
            'FGA', 'fga_4_5_single',     4.12776e-03, 3.01628e-02; ...
            'FGA', 'fga_4_5_int32',      2.86817e-01, 2.0;         ...
            'FGA', 'fga_id_1_5_double',  5.51639e-15, 5.68434e-14; ...
            'FGA', 'fga_id_4_5_double',  4.12776e-03, 3.01644e-02; ...
            'FGA', 'fga_id_10_5_double', 1.21742e-03, 7.90703e-03; ...
            ...
            ... FGAD: GradientAnisotropicDiffusionImageFilter, same
            ... upstream-numerics story as FCA.
            'FGAD', 'fgad_2_0p0625_40_double',  4.74279e-05, 6.82498e-04; ...
            'FGAD', 'fgad_40_0p0625_2_double',  1.33617e-02, 6.05228e-01; ...
            'FGAD', 'fgad_5_0p0625_10_double',  8.20297e-04, 9.49829e-03; ...
            'FGAD', 'fgad_5_0p0625_3_double',   5.39286e-03, 7.36632e-02; ...
            'FGAD', 'fgad_5_0p0625_3_int32',    1.26501,     5.0;         ...
            'FGAD', 'fgad_5_0p0625_3_single',   6.57574e-03, 8.95309e-02; ...
            'FGAD', 'fgad_5_0p0625_3_uint8',    11.7184,     55.0;        ...
            'FGAD', 'fgad_5_10_0p0625_double',  3.49656e-01, 1.75066e+01; ...
            ...
            ... FCF: CurvatureFlowImageFilter, same story.
            'FCF', 'fcf_5_0p0625_double',   8.76748e-16, 4.26326e-14; ...
            'FCF', 'fcf_10_0p0625_double',  1.23338e-15, 9.94760e-14; ...
            'FCF', 'fcf_20_0p0625_double',  1.68409e-15, 1.70530e-13; ...
            'FCF', 'fcf_10_0p0625_single',  7.45584e-07, 5.34058e-05; ...
            'FCF', 'fcf_10_0p0625_int32',   1.721,       21.0;        ...
            'FCF', 'fcf_10_0p0625_uint8',   7.27783,     130.0;       ...
            ...
            ... FBL: BilateralImageFilter. double's own residual is at
            ... the floating-point noise floor (1e-13-1e-12); int32/
            ... single/uint8 are bit-exact (see tReferenceExact.m).
            'FBL', 'fbl_2_10_double',  9.54532e-14, 1.09424e-12; ...
            'FBL', 'fbl_10_2_double',  5.03596e-13, 5.17275e-12; ...
            'FBL', 'fbl_5_5_double',   4.50544e-13, 3.92220e-12; ...
            ...
            ... FSN: SigmoidImageFilter. One fixture at the floating-point
            ... noise floor; the other five captured fixtures are
            ... bit-exact (see tReferenceExact.m).
            'FSN', 'fsn_10_240_10_44_double', 1.73979e-15, 2.84217e-14; ...
            ...
            ... FVMI: two-filter Hessian-vesselness pipeline; both stages'
            ... internal numerics moved between 2.4 and 5.x.
            'FVMI', 'fvmi_1_0p5_2_double',  0.513911, 9.76872;  ...
            'FVMI', 'fvmi_1_2_0p5_double',  0.497462, 10.0506;  ...
            'FVMI', 'fvmi_3_0p5_2_double',  0.0827188, 1.18877; ...
            'FVMI', 'fvmi_1_0p5_2_single',  0.513911, 9.76872;  ...
            'FVMI', 'fvmi_1_0p5_2_int32',   0.493737, 10.0;     ...
            'FVMI', 'fvmi_1_0p5_2_uint8',   0.493737, 10.0;     ...
            ...
            ... FGMRG: GradientMagnitudeRecursiveGaussianImageFilter;
            ... recursive-Gaussian numerics moved between 2.4 and 5.x.
            ... int32/uint8 at sigma=2 are bit-exact (see
            ... tReferenceExact.m); every other captured combination has a
            ... floating-point-scale residual.
            'FGMRG', 'fgmrg_1_double', 2.73366e-07, 5.43344e-06; ...
            'FGMRG', 'fgmrg_2_double', 1.32290e-07, 1.85020e-06; ...
            'FGMRG', 'fgmrg_4_double', 7.13001e-08, 9.00417e-07; ...
            'FGMRG', 'fgmrg_2_single', 1.16793e-07, 1.90735e-06; ...
            ...
            ... FGMS: registry duplicate of FGMRG (Epic 4 Phase 2) -- the
            ... original's own FGMS output is bit-identical to its own
            ... FGMRG output at every captured sigma, so mexitk implements
            ... it as the same filter call and measures the identical
            ... residual against these fixtures as FGMRG measures against
            ... its own, at the same sigma. See src/opcodes/fgmrg.cpp's
            ... FgmsOpcode::StatusNote for the bit-identity proof.
            'FGMS', 'fgms_sigma1_double', 2.73366e-07, 5.43344e-06; ...
            'FGMS', 'fgms_sigma2_double', 1.32290e-07, 1.85020e-06; ...
            'FGMS', 'fgms_sigma4_double', 7.13001e-08, 9.00417e-07; ...
            ...
            ... FLS: LaplacianRecursiveGaussianImageFilter, same story;
            ... uint8's clamp-back export (deviation 8) makes its own
            ... residual much larger since the underlying signed field
            ... saturates on export. int32 at sigma=2 is bit-exact (see
            ... tReferenceExact.m).
            'FLS', 'fls_1_double', 2.10075e-07, 3.81470e-06; ...
            'FLS', 'fls_2_double', 4.50375e-08, 9.53674e-07; ...
            'FLS', 'fls_4_double', 7.90163e-09, 2.38419e-07; ...
            'FLS', 'fls_2_single', 4.50375e-08, 9.53674e-07; ...
            'FLS', 'fls_2_uint8',  98.6939,     255.0;       ...
            ...
            ... FDM: reimplemented pipeline (Epic 2 Phase 3). double/
            ... single/int32 are bit-exact (see tReferenceExact.m); uint8
            ... alone has a small residual, likely reflecting a
            ... lower-precision internal distance representation in the
            ... original's own uint8 instantiation (see
            ... src/opcodes/fdm.cpp).
            'FDM', 'fdm_raw_uint8',   0.217891, 6.0; ...
            'FDM', 'fdm_bin_uint8',   0.205432, 6.0; ...
            'FDM', 'fdm_lab_uint8',   0.205432, 6.0; ...
            ...
            ... FDMV: reimplemented pipeline. single/int32 are bit-exact
            ... (see tReferenceExact.m). double has a floating-point
            ... op-order residual right at double precision's own limit
            ... (persists under an alternative op ordering too -- see
            ... src/opcodes/fdm.cpp). uint8 uses a direct-cast wraparound
            ... formula, not a rescale, with its own small residual
            ... consistent with ITK 2.4-vs-5.4 Voronoi tie-break
            ... divergence at equidistant background voxels.
            'FDMV', 'fdmv_raw_double',     3.34842e-12, 7.27596e-12; ...
            'FDMV', 'fdmv_bin_double',     3.14089e-12, 7.27596e-12; ...
            'FDMV', 'fdmv_lab_double',     3.14089e-12, 7.27596e-12; ...
            'FDMV', 'fdmv_acc_bin_double', 3.14089e-12, 7.27596e-12; ...
            'FDMV', 'fdmv_acc_lab_double', 3.14089e-12, 7.27596e-12; ...
            'FDMV', 'fdmv_raw_uint8',      11.4355,     255.0;       ...
            'FDMV', 'fdmv_bin_uint8',      8.62219,     255.0;       ...
            'FDMV', 'fdmv_lab_uint8',      8.62219,     255.0;       ...
            ...
            ... SNC: axis-convention fix (Epic 2 Phase 3) makes radius
            ... [1,1,1] and the base threshold fixtures bit-exact (see
            ... tReferenceExact.m), but NeighborhoodConnectedImageFilter
            ... itself diverges from the original for other radii,
            ... independent of axis order: snc_r0_band (radius [0,0,0],
            ... symmetric, so the axis swap is a total no-op there) still
            ... deviates substantially, proving a separate upstream-
            ... algorithm difference, the same class of issue as FCA/SWS.
            'SNC', 'snc_r0_band_seedS1_double', 73.321,  255.0; ...
            'SNC', 'snc_r2_band_seedS1_double', 1.75694, 255.0; ...
            'SNC', 'snc_rx_wide_seedS1_double', 47.1001, 255.0; ...
            'SNC', 'snc_rz_wide_seedS1_double', 62.2875, 255.0; ...
            ...
            ... FMMCF: MinMaxCurvatureFlowImageFilter (Epic 3 Phase 1). Real
            ... upstream numerics drift, not floating-point noise: verified
            ... directly that numberOfIterations=0 is an exact no-op and
            ... that the deviation compounds with iteration count, the same
            ... shape as FCF's own (much smaller) double residual -- see
            ... src/opcodes/fmmcf.cpp.
            'FMMCF', 'fmmcf_10_0p0625_1_double', 1.59658, 43.2502; ...
            ...
            ... SFM: FastMarchingImageFilter (Epic 3 Phase 1). Floating-point
            ... noise floor, the same order of magnitude as FCF's own double
            ... residual: the 270838 sentinel-valued voxels (61.22% of the
            ... volume, ITK's LargeValue = NumericTraits<double>::max()/2, a
            ... constant assigned during Initialize rather than computed)
            ... match EXACTLY; every differing voxel is a genuinely computed
            ... arrival time differing only at double precision's own limit
            ... -- see src/opcodes/sfm.cpp.
            'SFM', 'sfm_stop100_seedS1_double', 6.10523e-15, 9.01501e-14; ...
            ...
            ... SLLS: LaplacianSegmentationLevelSetImageFilter (Epic 3
            ... Phase 2, two-volume opcode). 280/442368 voxels (0.063%)
            ... land on the wrong side of the binary threshold; every one
            ... of those voxels' raw, pre-threshold level-set value is
            ... within 0.077 of the zero crossing (median 0.00087) -- the
            ... floating-point noise floor of a 50-iteration finite-
            ... difference solver flipping a boundary voxel's sign, not an
            ... algorithmic difference. RMS/max-abs are measured on the
            ... exported {0,255} categorical output, so max-abs is 255 (a
            ... full category flip) even though the underlying level-set
            ... values differ by fractions of a percent -- see
            ... src/opcodes/slls.cpp.
            'SLLS', 'slls_slls_volB_seedS1_double', 6.41545, 255.0; ...
            ...
            ... SSDLS: ShapeDetectionLevelSetImageFilter (Epic 3 Phase 2,
            ... two-volume opcode). Raw, un-thresholded narrow-band output
            ... (unlike SGAC/SLLS): floating-point noise floor of a
            ... 50-iteration finite-difference solver, the same category as
            ... SFM's own bounded deviation -- see src/opcodes/ssdls.cpp.
            'SSDLS', 'ssdls_ssdls_volB_seedS1_double', 6.69151e-08, 5.25301e-06; ...
            ...
            ... RD: HistogramMatching + DemonsRegistrationFilter + Warp
            ... (Epic 4 Phase 1, the first RegistrationCategory opcode).
            ... Far above the floating-point noise floor: a real numerics
            ... difference in the iterative Demons solver, the same
            ... category as FCA/FMMCF, not rounding. numberOfIterations=0
            ... is confirmed an exact identity no-op (rules out a basic
            ... wiring error); fixed/moving role assignment (volumeA
            ... fixed, volumeB moving) was confirmed by a swap test
            ... against this fixture (the swapped wiring measures RMS
            ... 21.7/ndiff 189263) -- see src/opcodes/rd.cpp.
            'RD', 'rd_demons_volB_double', 4.63626, 88.0; ...
            ...
            ... RTPS: ThinPlateSplineKernelTransform + Resample (Epic 4
            ... Phase 1, s14 reference-host capture round, two rounds, 8
            ... successful captures: 5 at the floating-point noise floor,
            ... 3 with a real, modest, measured residual). The 5 noise-
            ... floor captures split into two magnitude bands, not one
            ... uniform ceiling: 3 at RMS ~1e-12 (rtps_pairs4_translate_
            ... double 2.63e-12, rtps_coplanar3_distinct_double 8.15e-13,
            ... rtps_pairs3_distinct_double 5.26e-12) and 2 at RMS ~2e-10
            ... (rtps_nc5_identity_double 2.12e-10, rtps_nc5_translate_
            ... double 2.00e-10). The 3 with a real residual
            ... (rtps_pairs4_identity_double, rtps_pair1_minimal_double,
            ... rtps_pairs2_distinct_double) come from round 2
            ... (rtps_coplanar3_distinct_double, rtps_pairs2_distinct_double,
            ... rtps_pairs3_distinct_double), which isolated exactly why:
            ... the threshold is 3+ DISTINCT landmark pairs, not
            ... coplanarity (3 distinct coplanar pairs reproduce exactly)
            ... and not raw pair count (rtps_pairs4_identity_double's 4
            ... pairs collapse to only 2 distinct ones and shows the same
            ... residual class as genuinely having only 2 --
            ... rtps_pairs2_distinct_double). Not a monotonic shrink either:
            ... 2 distinct pairs (RMS 4.16) is WORSE than 1 (RMS 3.65),
            ... then reproduction jumps straight to the noise floor at 3 --
            ... a threshold, not a gradual improvement. Consistent with
            ... ITK's SVD-based pseudo-inverse resolving an underdetermined
            ... system slightly differently between 2.4 and 5.4, the same
            ... upstream-numerics-evolution category as FCA/SNC/SWS -- see
            ... src/opcodes/rtps.cpp's StatusNote for the full evidence,
            ... including how the convention itself was determined
            ... (interleaved landmarks, volumeB fixed/volumeA moving) and
            ... why Phase 1's original split-half/volumeA-fixed inference
            ... was wrong.
            'RTPS', 'rtps_nc5_identity_double',        2.12194811e-10, 7.809859426e-09; ...
            'RTPS', 'rtps_nc5_translate_double',       1.998278382e-10, 7.471129493e-09; ...
            'RTPS', 'rtps_pairs4_translate_double',    2.634815908e-12, 7.443602765e-11; ...
            'RTPS', 'rtps_coplanar3_distinct_double',  8.146892322e-13, 1.563194019e-11; ...
            ... rtps_pairs3_distinct_double's RMS below is the MAXIMUM
            ... measured across both CI platforms (Linux x86_64
            ... 6.78818e-12, macOS arm64 5.26459e-12), not a single-
            ... platform measurement: at this magnitude (both values are
            ... ~1e-13 relative to the 0-88 intensity range, i.e. genuine
            ... double-precision noise), ThinPlateSplineKernelTransform's
            ... vnl_svd solve runs through each platform's own LAPACK/BLAS,
            ... and the two measurements disagree by about 29% of each
            ... other -- Linux's own value exceeded the bound this project
            ... had asserted from the macOS measurement alone by about 8%,
            ... failing CI (caught on PR #30). This is completing an
            ... under-measured bound, not raising one to hide a real
            ... disagreement (forbidden by project policy): the quantity
            ... being bounded is which-platform's-LAPACK noise, not
            ... agreement with the original, and only ONE platform's noise
            ... had been measured before. The magnitude-gated bound margin
            ... below (see deviationMatchesDocumentedBound's own rmsFactor
            ... comment, and docs/COMPATIBILITY.md's "Bound margins for
            ... noise-floor entries") now ALSO gives 1.5x headroom here on
            ... its own, since this RMS is well under the 1e-5 gate
            ... threshold -- from the macOS-only value alone that policy
            ... would already have absorbed the Linux measurement. The
            ... cross-platform maximum is kept as the stored value anyway,
            ... deliberately: it is the more accurate number, belt and
            ... suspenders on top of the wider margin, not a substitute
            ... for it. max-abs gets the identical magnitude gate now too
            ... (it was previously unaffected only because that gate did
            ... not exist yet), and Linux's own max-abs was never reported
            ... to exceed even the prior bound.
            'RTPS', 'rtps_pairs3_distinct_double',     6.78818e-12, 1.091677859e-10; ...
            'RTPS', 'rtps_pairs4_identity_double',     2.226571164, 88.0; ...
            'RTPS', 'rtps_pair1_minimal_double',       3.647131445, 88.0; ...
            'RTPS', 'rtps_pairs2_distinct_double',     4.159985105, 88.0};
    end

    methods (Static)
        function s = caseParams()
            % Converts the Cases table above into the struct TestParameter
            % needs: one field per row, field name == fixture name, field
            % value == a struct carrying that row's own (opcode, name,
            % rmsMeasured, maxMeasured).
            rows = tReferenceBounded.Cases;
            s = struct();
            for i = 1:size(rows, 1)
                name = rows{i, 2};
                s.(name) = struct('opcode', rows{i, 1}, 'name', name, ...
                    'rmsMeasured', rows{i, 3}, 'maxMeasured', rows{i, 4});
            end
        end
    end

    methods (Test)
        function deviationMatchesDocumentedBound(tc, boundedCase)
            opcode = boundedCase.opcode;
            name = boundedCase.name;
            rmsMeasured = boundedCase.rmsMeasured;
            maxMeasured = boundedCase.maxMeasured;

            [fx, vin, vinB] = mexitkFixture(name);
            tc.assertTrue(fx.success, sprintf( ...
                '%s: fixture recorded success=false', name));

            got = mexitkFixtureCall(opcode, fx, vin, vinB);

            e = abs(double(got(:)) - double(fx.output(:)));
            rms = sqrt(mean(e .^ 2));
            mx = max(e);

            % RMS headroom is magnitude-gated, a policy ruling from the
            % PR #30 review, not an ad hoc per-fixture choice: below 1e-5
            % (relative ~1e-7 on this project's 0-88 reference data), a
            % residual is presumptively floating-point/library noise
            % rather than a real algorithmic difference -- RTPS's
            % ThinPlateSplineKernelTransform and several other filters
            % here solve through vnl_svd or similar LAPACK/BLAS-backed
            % routines, whose exact last-bit result is platform-dependent.
            % A margin tighter than the observed platform variation would
            % assert false precision and test the linear-algebra library
            % rather than agreement with the original -- caught directly
            % on PR #30's Linux CI run: rtps_pairs3_distinct_double
            % measured RMS 6.78818e-12 there against a macOS-only-derived
            % bound of 5.264588848e-12 (a ~29% spread), which the prior
            % flat 10% margin did not absorb. Above 1e-5 the residual is a
            % real, if sometimes small, algorithmic difference (FGAD's
            % uint8 residual, FDM's uint8 residual, RD, the three
            % non-noise-floor RTPS cases, etc.), where a tight 10% margin
            % is meaningful regression detection and stays exactly as
            % before -- loosening it there would be exactly the "raise a
            % bound to hide disagreement" move this project forbids. See
            % docs/COMPATIBILITY.md's "Bound margins for noise-floor
            % entries" for the full policy and the measured spread that
            % motivated it. This widens ASSERTION MARGINS only: no
            % measured value in the Cases table above changed because of
            % this gate, and every case at or above 1e-5 keeps exactly the
            % same 10% factor it always had.
            if rmsMeasured < 1e-5
                rmsFactor = 1.5;
            else
                rmsFactor = 1.1;
            end
            rmsCeiling = max(rmsMeasured * rmsFactor, rmsMeasured + 1e-12);
            % max-abs gets the SAME magnitude gate as RMS above, for the
            % same reason: a max-abs measurement below 1e-5 comes from the
            % identical platform-dependent vnl_svd/LAPACK noise floor as
            % its own fixture's RMS, so a flat 10% margin there is exposed
            % to the same class of latent cross-platform brittleness, even
            % though no max-abs entry has actually failed CI yet -- gating
            % it now, on the same measured-magnitude signal, is closing
            % the gap before it produces its own surprise red run rather
            % than waiting for one. The +1e-9 additive floor (already
            % larger than RMS's own +1e-12, since max-abs values run
            % larger for the same fixture) stays in every case.
            if maxMeasured < 1e-5
                maxFactor = 1.5;
            else
                maxFactor = 1.1;
            end
            maxCeiling = max(maxMeasured * maxFactor, maxMeasured + 1e-9);
            tc.verifyLessThan(rms, rmsCeiling, sprintf( ...
                '%s (%s): RMS deviation %.6g exceeds documented %.6g', ...
                name, opcode, rms, rmsMeasured));
            tc.verifyLessThan(mx, maxCeiling, sprintf( ...
                '%s (%s): max deviation %.6g exceeds documented %.6g', ...
                name, opcode, mx, maxMeasured));

            % Guard the other direction too, but only for measurements
            % well above the floating-point noise floor: a value
            % already near double precision's own limit (< 1e-8) can
            % legitimately shift by a platform-dependent factor of 2-3
            % without indicating any real change in agreement.
            if rmsMeasured > 1e-8
                tc.verifyGreaterThan(rms, rmsMeasured * 0.1, sprintf( ...
                    ['%s (%s): now agrees with matitk far better than ' ...
                     'documented (RMS %.6g vs %.6g); re-baseline and ' ...
                     'update docs/COMPATIBILITY.md'], name, opcode, rms, rmsMeasured));
            end
        end
    end
end
