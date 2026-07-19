classdef tPhase3RegionGrowingSmoke < matlab.unittest.TestCase
    % Smoke tests for the Phase 3 region-growing + single-Otsu opcodes. No
    % reference fixtures exist for these, so the suite asserts structural
    % invariants (shape, class, parameter validation, connectivity, and
    % monotonicity properties) rather than bit-exactness. Every non-guaranteed
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

    properties (TestParameter)
        seededOp = {'SCT', 'SCC', 'SNC'};                % share the seed-convention machinery
        allOp    = {'SCT', 'SCC', 'SNC', 'SIC', 'SOT'};
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
                case 'SCT'; p = [20 60];             % lower, upper
                case 'SCC'; p = [2.5 5 100];          % multiplier, iters, replace
                case 'SNC'; p = [1 1 1 20 60 255];    % rx ry rz lower upper replace
                case 'SIC'; p = [20 255];             % lower, replace
                case 'SOT'; p = 128;                  % bins
            end
        end

        function sub = regionGrowSeed()
            % [70 50 14], value 68. Deliberately NOT the volume's global-max
            % voxel: the literal brightest voxel [91 21 1] sits in a huge
            % (19638-voxel) saturated plateau at the image's z=1 edge slice,
            % and measured empirically, SCC's confidence interval from that
            % seed explodes to fill 100% of the volume even at the
            % registry's default multiplier (2.5) -- a degenerate,
            % uninteresting case for testing "did the region grow a bounded
            % subset". This seed was chosen instead because its local
            % 3x3x3 neighbourhood has low intensity variance (std ~3.75),
            % giving SCC a bounded, non-trivial region (~21% of the volume
            % at multiplier 2.5). All three subscripts are distinct
            % (asymmetric), so a transposed axis in SeedPointsToIndices or
            % SNC's radius would land on a different voxel.
            sub = [70 50 14];
        end

        function sub = disconnectedSameBandVoxel()
            % [118 60 1], value 64: inside the same [63 73] intensity band
            % as regionGrowSeed's voxel (68) but 50.7 grid units away.
            % Verified empirically that SCT/SNC/SCC's region grown from
            % regionGrowSeed at that band does NOT reach this voxel, i.e.
            % it is genuinely disconnected, not merely out of range.
            sub = [118 60 1];
        end

        function sub = isolatedBackgroundSeed()
            % [1 128 1], value 0: SIC's second seed group. A mid-band
            % candidate (value ~40, still bright brain tissue) was tried
            % first and empirically FAILED to isolate: ITK's internal
            % binary search could not find a separating threshold between
            % it and regionGrowSeed's band, so both seeds came back
            % unlabelled. Pure background is far enough in intensity that
            % isolation succeeds. Verified, not assumed.
            sub = [1 128 1];
        end
    end

    methods (Test)  % parameterized common checks
        function runsAndPreservesShapeAndClass(tc, allOp)
            p = tPhase3RegionGrowingSmoke.validParams(allOp);
            sub1 = tPhase3RegionGrowingSmoke.regionGrowSeed();
            sub2 = tPhase3RegionGrowingSmoke.isolatedBackgroundSeed();
            switch allOp
                case {'SCT', 'SCC', 'SNC'}; seeds = sub1;
                case 'SIC';                 seeds = [sub1, sub2];
                case 'SOT';                 seeds = [];
            end
            for f = {@double, @single, @uint8, @int32}
                vin = f{1}(tc.Vu);
                if isempty(seeds)
                    out = mexitk(allOp, p, vin);
                else
                    out = mexitk(allOp, p, vin, [], seeds);
                end
                tc.verifyClass(out, class(vin));
                tc.verifySize(out, size(vin));
            end
        end

        function rejectsShortParamCount(tc, allOp)
            p = tPhase3RegionGrowingSmoke.validParams(allOp);
            short = p(1:end-1);
            tc.verifyError(@() mexitk(allOp, short, tc.V), 'mexitk:params');
        end
    end

    methods (Test)  % seed-convention pin (the load-bearing test)
        function seedConventionIsNotTransposed(tc, seededOp)
            % An axis transposition (mapping sub(1) -> ITK axis 2, say)
            % would place ReplaceValue at a different MATLAB voxel; the
            % exact-voxel equality below fails in that case. This is the
            % primary defense for SeedPointsToIndices and SNC's radius
            % order.
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            val = tc.V(sub(1), sub(2), sub(3));
            switch seededOp
                case 'SCT'; p = [val - 5, val + 5];              rv = 255;
                case 'SNC'; p = [1 1 1, val - 5, val + 5, 255];  rv = 255;
                case 'SCC'; p = [2.5 5 100];                     rv = 100;
            end
            out = mexitk(seededOp, p, tc.V, [], sub);
            tc.verifyEqual(out(sub(1), sub(2), sub(3)), rv);
        end

        function disconnectedVoxelNotLabeled(tc, seededOp)
            % Catches a "label everything in range" bug that a pure
            % threshold (not an actual region grow) would exhibit: the far
            % voxel is in the same intensity band as the seed but not
            % connected to it, so it must NOT receive ReplaceValue.
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            far = tPhase3RegionGrowingSmoke.disconnectedSameBandVoxel();
            val = tc.V(sub(1), sub(2), sub(3));
            switch seededOp
                case 'SCT'; p = [val - 5, val + 5];              rv = 255;
                case 'SNC'; p = [1 1 1, val - 5, val + 5, 255];  rv = 255;
                case 'SCC'; p = [2.5 5 100];                     rv = 100;
            end
            out = mexitk(seededOp, p, tc.V, [], sub);
            tc.verifyNotEqual(out(far(1), far(2), far(3)), rv);
        end

        function seedAtDimensionMaximumIsAccepted(tc, seededOp)
            % [70 50 27]: z=27 is the EXACT dim-3 maximum of this
            % 128x128x27 volume. A missing/wrong 1->0 base shift in
            % SeedPointsToIndices would deterministically throw
            % mexitk:seeds here (index 27 is one past the valid 0-based
            % range 0..26), so this pins the off-by-one boundary rather
            % than just an interior seed. Params are chosen to guarantee a
            % clean run regardless of the voxel's own intensity (full
            % range for SNC/SCT-equivalent bounds), not to test growth
            % magnitude. Verified directly for all three ops before commit.
            sub = [70 50 27];
            switch seededOp
                case 'SCT'; p = [20 60];
                case 'SNC'; p = [1 1 1 0 255 255];
                case 'SCC'; p = [2.5 5 100];
            end
            out = mexitk(seededOp, p, tc.V, [], sub);
            tc.verifySize(out, size(tc.V));
        end

        function fractionalSeedTruncatesTowardZero(tc)
            % 70.9 must behave as 70, not round to 71: matches CastParam's
            % truncation philosophy used everywhere else in this codebase.
            % Verified directly: mexitk('SCT',...,[70.9 50 14]) produces the
            % bit-identical output to mexitk('SCT',...,[70 50 14]).
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            fractional = [sub(1) + 0.9, sub(2), sub(3)];
            outInt = mexitk('SCT', [20 60], tc.V, [], sub);
            outFrac = mexitk('SCT', [20 60], tc.V, [], fractional);
            tc.verifyEqual(outFrac, outInt);
        end
    end

    methods (Test)  % SCT-specific
        function sctOutputIsTwoValued(tc)
            % Uses the seed's own band (not the generic validParams [20
            % 60], which excludes this seed's value of 68 and would
            % degenerate to an all-zero, only-trivially-two-valued output)
            % so growth genuinely happens and both values are exercised.
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            val = tc.V(sub(1), sub(2), sub(3));
            out = mexitk('SCT', [val - 5, val + 5], tc.V, [], sub);
            tc.verifyEmpty(setdiff(unique(double(out(:))), [0 255]));
            tc.verifyGreaterThan(nnz(out == 0), 0);
            tc.verifyGreaterThan(nnz(out == 255), 0);
        end

        function sctThresholdMonotonicity(tc)
            % Widening [lower,upper] never shrinks the labeled set for a
            % fixed seed. Verified: 36595 -> 88105 voxels.
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            val = tc.V(sub(1), sub(2), sub(3));
            narrow = mexitk('SCT', [val - 5, val + 5], tc.V, [], sub);
            wide   = mexitk('SCT', [val - 15, val + 15], tc.V, [], sub);
            tc.verifyGreaterThanOrEqual(nnz(wide == 255), nnz(narrow == 255));
        end

        function sctEmptySeedsAllBackground(tc)
            % Defined behaviour (itkFloodFilledFunctionConditionalConstIterator
            % reports IsAtEnd immediately with no seed inside), not a crash
            % or error. Verified.
            out = mexitk('SCT', [20 60], tc.V, [], []);
            tc.verifyEqual(nnz(out), 0);
        end
    end

    methods (Test)  % SCC-specific
        function sccSeedLabeledWithReplaceValue(tc)
            % Asserts the ReplaceValue param is actually wired, not
            % hardcoded to some other value: covered structurally by
            % seedConventionIsNotTransposed(seededOp='SCC') above, which
            % checks == 100 (the registry's ReplaceValue hint), not 255.
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            out = mexitk('SCC', [2.5 5 100], tc.V, [], sub);
            tc.verifyEqual(out(sub(1), sub(2), sub(3)), 100);
        end

        function sccLargerMultiplierGrowsOrEqual(tc)
            % Verified: 93645 -> 442368 (saturates to the full volume at
            % multiplier 4 on this data; still a valid >= comparison since
            % it did not start there).
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            small = mexitk('SCC', [2.5 5 100], tc.V, [], sub);
            big   = mexitk('SCC', [4 5 100], tc.V, [], sub);
            tc.verifyGreaterThanOrEqual(nnz(big == 100), nnz(small == 100));
        end

        function sccMultiplierAndIterationsAreNotInterchangeable(tc)
            % Catches a param-order bug where multiplier and iterations got
            % swapped in the C++ wiring (SetMultiplier(p[1]),
            % SetNumberOfIterations(p[0]) instead of the correct
            % SetMultiplier(p[0]), SetNumberOfIterations(p[1])). At
            % [1.0 5 100] (multiplier=1.0, a tight confidence interval),
            % correct wiring grows a small region: measured nnz=3. Under
            % the hypothetical swap, this call would behave like
            % multiplier=5/iterations=1, i.e. equivalent to calling with
            % [5 1 100] under correct wiring, measured nnz=150674 -- five
            % orders of magnitude larger. The bound below is set
            % comfortably above the measured correct-wiring count (3) and
            % comfortably below the swapped-equivalent count (150674).
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            out = mexitk('SCC', [1.0 5 100], tc.V, [], sub);
            tc.verifyLessThan(nnz(out == 100), 1000);
        end

        function sccEmptySeedsAllZero(tc)
            % Defined in ITK 5.4 (itkConfidenceConnectedImageFilter.hxx:
            % "no seeds result in zero image"). Verified.
            out = mexitk('SCC', [2.5 5 100], tc.V, [], []);
            tc.verifyEqual(nnz(out), 0);
        end
    end

    methods (Test)  % SNC-specific
        function sncRadiusZeroVsTwoDiffer(tc)
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            val = tc.V(sub(1), sub(2), sub(3));
            r0 = mexitk('SNC', [0 0 0, val - 5, val + 5, 255], tc.V, [], sub);
            r2 = mexitk('SNC', [2 2 2, val - 5, val + 5, 255], tc.V, [], sub);
            tc.verifyNotEqual(r0, r2);
        end

        function sncRadiusAxisOrderMatters(tc)
            % Verified empirically: at the tight [val-5 val+5] band both
            % asymmetric-radius outputs coincidentally collapse to a
            % single voxel each (indistinguishable), so this uses the
            % wider [val-15 val+15] band instead, which does discriminate
            % (18963 vs 5261 foreground voxels).
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            val = tc.V(sub(1), sub(2), sub(3));
            rx = mexitk('SNC', [3 1 1, val - 15, val + 15, 255], tc.V, [], sub);
            rz = mexitk('SNC', [1 1 3, val - 15, val + 15, 255], tc.V, [], sub);
            tc.verifyNotEqual(rx, rz);
        end

        function sncEmptySeedsAllZero(tc)
            out = mexitk('SNC', [1 1 1 20 60 255], tc.V, [], []);
            tc.verifyEqual(nnz(out), 0);
        end
    end

    methods (Test)  % SIC-specific
        function sicRejectsSinglePoint(tc)
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            tc.verifyError(@() mexitk('SIC', [20 255], tc.V, [], sub), 'mexitk:SIC:seeds');
        end

        function sicTwoBandsIsolate(tc)
            sub1 = tPhase3RegionGrowingSmoke.regionGrowSeed();
            sub2 = tPhase3RegionGrowingSmoke.isolatedBackgroundSeed();
            out = mexitk('SIC', [20 255], tc.V, [], [sub1, sub2]);
            tc.verifyEqual(out(sub1(1), sub1(2), sub1(3)), 255);
            tc.verifyNotEqual(out(sub2(1), sub2(2), sub2(3)), 255);
        end

        function sicOutOfBoundsSeedRejected(tc)
            tc.verifyError(@() mexitk('SIC', [20 255], tc.V, [], [9999 9999 9999, 1 1 1]), ...
                'mexitk:seeds');
        end

        function sicIgnoresOutOfBoundsExtraSeed(tc)
            % Lead override of this plan's own default: SIC bounds-checks
            % ONLY the two consumed seed points, not ignored extras (the
            % original never read past the second point, so rejecting an
            % out-of-bounds ignored point would accept strictly less than
            % the original did). A third, wildly out-of-bounds seed must
            % NOT raise an error.
            sub1 = tPhase3RegionGrowingSmoke.regionGrowSeed();
            sub2 = tPhase3RegionGrowingSmoke.isolatedBackgroundSeed();
            out = mexitk('SIC', [20 255], tc.V, [], [sub1, sub2, 9999 9999 9999]);
            tc.verifySize(out, size(tc.V));
        end
    end

    methods (Test)  % SOT-specific + FOMT cross-check
        function sotIsTwoValuedUint8(tc)
            out = mexitk('SOT', 128, tc.Vu);
            tc.verifyEmpty(setdiff(unique(out(:)), uint8([0 255])));
        end

        function sotOutsideValueIsFixed255OnDouble(tc)
            % Pins the mask-value claim: the original's SOT mask value is a
            % FIXED 255 on every pixel type, not the pixel type's own max
            % (realmax('double') for double). Fixture-proven: every
            % captured sot_* fixture, double included, has unique output
            % {0,255}, never {0,realmax}. See docs/COMPATIBILITY.md.
            out = mexitk('SOT', 128, tc.V);
            u = unique(out(:));
            tc.verifyEqual(numel(u), 2);
            tc.verifyEqual(max(u), 255);
        end

        function sotMatchesFomtSingleThreshold(tc)
            % SOT labels the HIGH side of its Otsu cut (intensity >
            % threshold) with its mask value; FOMT's single-class output
            % (fomt==255) labels the LOW side (class 0). Reference-fixture
            % Phase 3 work found and fixed two SOT bugs (polarity was
            % inverted; the histogram range used the uint8 TYPE bound
            % [0,255] instead of the data range) that, together, also
            % happened to align SOT's chosen threshold with FOMT's: MEASURED
            % on this data (not invented, not tuned) post-fix agreement is
            % EXACTLY 1.0 (442368 of 442368 voxels), i.e. sotHigh is the
            % exact complement of fomtLow, not merely a close approximation
            % as it was pre-fix. See docs/COMPATIBILITY.md.
            sot = mexitk('SOT', 128, tc.Vu);
            fomt = mexitk('FOMT', [1 128], tc.Vu);
            sotHigh = (sot ~= 0);
            fomtLow = (fomt == 255);
            tc.verifyEqual(sotHigh, ~fomtLow);
        end
    end

    methods (Test)  % error paths
        function sncRejectsNegativeRadius(tc)
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            tc.verifyError(@() mexitk('SNC', [-1 1 1 20 60 255], tc.V, [], sub), ...
                'mexitk:paramRange');
        end

        function sccRejectsNegativeIterations(tc)
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            tc.verifyError(@() mexitk('SCC', [2.5 -1 100], tc.V, [], sub), 'mexitk:paramRange');
        end

        function sotRejectsZeroBins(tc)
            % Measured, not assumed, and load-bearing: 0 histogram bins
            % crash the MATLAB PROCESS OUTRIGHT inside ITK's Otsu histogram
            % calculator (a bus error / SIGSEGV, not a catchable
            % itk::ExceptionObject) -- confirmed directly before adding the
            % guard in src/opcodes/sot.cpp. mexitk now rejects
            % numberOfHistogram < 2 up front (mexitk:SOT:numberOfHistogram),
            % the same severity class as the SWS-overthresholding deviation
            % in docs/COMPATIBILITY.md.
            tc.verifyError(@() mexitk('SOT', 0, tc.V), 'mexitk:SOT:numberOfHistogram');
        end

        function sotRejectsOneBin(tc)
            % Also crashes (a separate bus error, confirmed independently
            % from the 0-bins case), also caught by the same guard.
            tc.verifyError(@() mexitk('SOT', 1, tc.V), 'mexitk:SOT:numberOfHistogram');
        end

        function sotRejectsNegativeBins(tc)
            % Deviates from the plan's own expectation of mexitk:paramRange
            % here: the numberOfHistogram < 2 crash-guard (added after
            % finding the 0/1-bin MATLAB crash, not anticipated by the
            % plan) checks the raw parameter BEFORE CastParam runs, so it
            % catches negative values too, under its own more specific
            % identifier. Verified directly, not assumed from the plan text.
            tc.verifyError(@() mexitk('SOT', -1, tc.V), 'mexitk:SOT:numberOfHistogram');
        end

        function sccRejectsOutOfRangeReplaceOnUint8(tc)
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            tc.verifyError(@() mexitk('SCC', [2.5 5 300], tc.Vu, [], sub), 'mexitk:paramRange');
        end

        function sncAcceptsOutOfRangeReplaceOnDouble(tc)
            % 300 is out of uint8 range but valid for double: the guard is
            % per-target-type, not a blanket cap.
            sub = tPhase3RegionGrowingSmoke.regionGrowSeed();
            out = mexitk('SNC', [1 1 1 20 60 300], tc.V, [], sub);
            tc.verifySize(out, size(tc.V));
        end

        function seedRejectsNanCoordinate(tc)
            % SeedPointsToIndices validates in the double domain before any
            % cast (src/mexitk_common.h): central validation in mexFunction
            % (s < 1.0) passes NaN through unrejected, since NaN compares
            % false against every ordered relational operator. Verified
            % directly.
            tc.verifyError(@() mexitk('SCT', [20 60], tc.V, [], [NaN 50 14]), 'mexitk:seeds');
        end

        function seedRejectsInfCoordinate(tc)
            % Same reasoning as the NaN case: s < 1.0 is false for +Inf too.
            tc.verifyError(@() mexitk('SCT', [20 60], tc.V, [], [Inf 50 14]), 'mexitk:seeds');
        end

        function seedRejectsHugeCoordinate(tc)
            % A huge-but-finite coordinate would overflow itk::IndexValueType
            % on a raw cast (undefined behaviour); the helper now bounds-checks
            % the truncated double value before ever casting it. Verified
            % directly.
            tc.verifyError(@() mexitk('SCT', [20 60], tc.V, [], [1e20 50 14]), 'mexitk:seeds');
        end

        function sotRejectsNanBins(tc)
            % The guard is written as !(x >= 2.0), not (x < 2.0), so that
            % NaN -- which compares false against both -- is still caught
            % under this opcode-specific identifier rather than falling
            % through to CastParam's generic mexitk:paramRange. Verified
            % directly.
            tc.verifyError(@() mexitk('SOT', NaN, tc.V), 'mexitk:SOT:numberOfHistogram');
        end
    end
end
