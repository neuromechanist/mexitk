classdef tReferenceRejections < matlab.unittest.TestCase
    % Reference tests for fixtures where mexitk and the original disagree
    % on whether to run at all, plus two fixtures whose "disagreement" is
    % not a real one (see emptySeed* below).
    %
    % Four genuinely different situations live here, all deliberate, all
    % documented in docs/COMPATIBILITY.md:
    %   - mexitk refuses an input the original accepted, because the
    %     original's own behaviour on that input is undefined behaviour in
    %     C++ and unreproducible even in principle (deviation 5 and
    %     friends). Asserted: mexitk:paramRange / mexitk:fdm:noObject.
    %   - mexitk accepts an input the original rejected, and returns a
    %     defined result. This is "accept strictly more", the other
    %     direction deviations are allowed to go. No agreement claim is
    %     made about the VALUE mexitk returns for these -- only that it
    %     runs and produces a result of the right shape/class.
    %   - Both reject the same input, for possibly different specific
    %     reasons (both still land outside the valid domain).
    %   - mexitk refuses an ENTIRE OPCODE the original ran successfully,
    %     because the original's own output for that opcode is not an
    %     image (SCSS: the original returned without error, but its own
    %     output is a [10 1] vector of ones, not anything mexitk's
    %     image-in/image-out calling convention could return under this
    %     name without misleading a caller -- see src/opcodes/scss.cpp).
    %     This is not a per-input param-range rejection like the first
    %     category above (the fixture's own params are unremarkable;
    %     every SCSS call rejects, not just this one), so it gets its own
    %     assertion against mexitk:SCSS:unsupported rather than
    %     mexitk:paramRange.
    %
    % SPDX-License-Identifier: BSD-3-Clause
    % Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
    % Swartz Center for Computational Neuroscience (SCCN),
    % Institute for Neural Computation (INC), UC San Diego.

    properties (TestParameter)
        % opcode is redundant with fx.opcode but keeping it explicit here
        % makes each row self-describing without a fixture load.
        paramRangeRejection = {'fbd_1_300_uint8', 'fbt_0_1_20_1e39_single', ...
            'fbt_0_1_20_300_uint8', 'fvbih_1_1_1_0_300_1_1_uint8'};

        acceptsMoreFixture = {'fd_0_0_uint8', 'fd_1_0_int32', 'fd_1_0_uint8', ...
            'fdg_4_5_uint8', 'fdg_id_10_5_uint8', 'fdg_id_1_5_uint8', 'fdg_id_4_5_uint8', ...
            'fga_4_5_uint8', 'fga_id_10_5_uint8', 'fga_id_1_5_uint8', 'fga_id_4_5_uint8', ...
            'scc_2p5_5_100_dimmax_double', 'sct_20_60_dimmax_double', ...
            'sct_arg4_mismatch_uint8', 'sic_20_255_extraignored_double', ...
            'sic_dimmax_double', 'snc_dimmax_double'};

        mutualRejectionFixture = {'sct_base0_double', 'sic_split_s1only', ...
            'rtps_tps_volB_seedS1_double', 'rtps_odd3_reject_double'};
    end

    methods (Test)  % mexitk refuses an input the original accepted
        function paramGuardRejectsOutOfRangeValue(tc, paramRangeRejection)
            [fx, vin] = mexitkFixture(paramRangeRejection);
            tc.assertTrue(fx.success, sprintf( ...
                ['%s: original itself rejected this input (fixture bookkeeping error, ' ...
                 'this belongs in mutualRejectionFixture instead)'], paramRangeRejection));
            tc.verifyError(@() mexitk(fx.opcode, fx.params, vin), 'mexitk:paramRange');
        end

        function fdmRejectsAllZeroInput(tc)
            for name = {'fdm_zero_double', 'fdm_zero_uint8'}
                [fx, vin] = mexitkFixture(name{1});
                tc.assertTrue(fx.success, sprintf( ...
                    '%s: original itself rejected this input', name{1}));
                tc.verifyError(@() mexitk('FDM', fx.params, vin), 'mexitk:fdm:noObject');
            end
            % No fdmv_zero_* fixture was captured (FDM and FDMV share the
            % same all-zero-input guard in src/opcodes/fdm.cpp), so these
            % legs are direct calls rather than a fixture comparison.
            % Both double and uint8 are exercised, completing the guard's
            % test matrix to match FDM's own double+uint8 coverage above.
            tc.verifyError(@() mexitk('FDMV', [], zeros(4, 4, 4)), 'mexitk:fdm:noObject');
            tc.verifyError(@() mexitk('FDMV', [], zeros(4, 4, 4, 'uint8')), 'mexitk:fdm:noObject');
        end
    end

    methods (Test)  % mexitk accepts an input the original rejected
        function mexitkAcceptsWhereOriginalRejected(tc, acceptsMoreFixture)
            [fx, vin] = mexitkFixture(acceptsMoreFixture);
            tc.assertFalse(fx.success, sprintf( ...
                ['%s: original itself succeeded on this input (fixture bookkeeping ' ...
                 'error, this belongs in tReferenceExact/tReferenceBounded instead)'], ...
                acceptsMoreFixture));

            out = mexitkFixtureCall(fx.opcode, fx, vin);
            % No agreement claim: the original never produced a value for
            % this input, so there is nothing to compare against. Only
            % structural well-formedness is asserted.
            tc.verifyClass(out, class(vin));
            tc.verifySize(out, size(vin));
        end
    end

    methods (Test)  % mexitk refuses the whole opcode, not just this input
        function scssRefusesDespiteOriginalSuccess(tc)
            [fx, vin] = mexitkFixture('scss_scss_20_60_10_seedS1_double');
            tc.assertTrue(fx.success, sprintf( ...
                ['%s: original itself rejected this input (fixture bookkeeping ' ...
                 'error -- SCSS''s refusal belongs in this test regardless, but ' ...
                 'the assertTrue above would then be documenting the wrong fact)'], ...
                'scss_scss_20_60_10_seedS1_double'));
            % The original's own output confirms it is not an image: a
            % [10 1] column, one entry per AdvanceTimeStep() iteration
            % (numberOfIterations=10 in fx.params), not a volume shaped
            % like the input. mexitk never attempts to reproduce this
            % value; it always throws mexitk:SCSS:unsupported instead.
            tc.verifyEqual(size(fx.output), [10 1]);
            tc.verifyEqual(fx.output, ones(10, 1));
            tc.verifyError(@() mexitk('SCSS', fx.params, vin, [], fx.seedArg), ...
                'mexitk:SCSS:unsupported');
        end
    end

    methods (Test)  % both reject, for their own reasons
        function bothRejectTheSameInput(tc, mutualRejectionFixture)
            % vinB is fetched and threaded through unconditionally: it is
            % [] for sct_base0_double/sic_split_s1only (single-volume
            % opcodes, no arg4Recipe), where mexitkFixtureCall's own
            % isempty(vinB) fallback keeps their prior behaviour unchanged,
            % but rtps_tps_volB_seedS1_double was captured WITH a genuine
            % volumeB (arg4Recipe) -- dropping it here would exercise a
            % different call shape than the one the original actually
            % rejected (RequireVolumeB would fire first, under
            % mexitk:RTPS:volumeB, not the landmarks rejection this fixture
            % is actually evidence for).
            [fx, vin, vinB] = mexitkFixture(mutualRejectionFixture);
            tc.assertFalse(fx.success, sprintf( ...
                '%s: original itself succeeded on this input', mutualRejectionFixture));

            fn = @() mexitkFixtureCall(fx.opcode, fx, vin, vinB);
            tc.verifyError(fn, sprintf('mexitk:%s', ...
                localExpectedIdSuffix(mutualRejectionFixture)));
        end
    end

    methods (Test)  % empty-seed fixtures: a non-reproducible artifact, not agreement
        function emptySeedFixturesAreNotAReproducibleReference(tc)
            % snc_emptyseed_double and scc_2p5_5_100_emptyseed_double were
            % captured with an explicit seedArg=[] (a genuine zero-seed
            % call, confirmed against tools/capture_reference/
            % s09_regiongrow_capture.m -- not a harness bug), yet each
            % fixture's captured output is NOT all-zero: it carries
            % exactly the region that WOULD have grown from the single
            % seed point S1=[70 50 14] used by the immediately preceding
            % capture in the same script (SNC: exactly one nonzero voxel,
            % at S1 itself, value 255; SCC: exactly 93645 nonzero voxels,
            % value 100, matching mexitk('SCC',[2.5 5 100],V,[],S1)'s own
            % measured growth from S1 at that multiplier -- see
            % tPhase3RegionGrowingSmoke.sccLargerMultiplierGrowsOrEqual's
            % own comment for that 93645 figure). This is strong,
            % converging evidence that the ORIGINAL binary's own C++
            % implementation retains seed state across calls within one
            % MATLAB session -- a session-order-dependent artifact of the
            % 2006 binary itself, not a property of the SNC/SCC opcodes.
            % mexitk constructs a fresh ITK filter per call with no
            % persisted state, so it cannot reproduce this even in
            % principle, and should not try to: reproducing a stateful
            % bug tied to unrelated prior calls in the SAME capture script
            % would not be a meaningful "agreement" claim about the
            % opcode. mexitk's own defined behaviour for an empty seed
            % list -- an all-zero output -- is asserted directly here
            % instead of compared against these two fixtures. See
            % docs/COMPATIBILITY.md.
            [~, vinSnc] = mexitkFixture('snc_emptyseed_double');
            outSnc = mexitk('SNC', [1 1 1 20 60 255], vinSnc, [], []);
            tc.verifyEqual(nnz(outSnc), 0);

            [~, vinScc] = mexitkFixture('scc_2p5_5_100_emptyseed_double');
            outScc = mexitk('SCC', [2.5 5 100], vinScc, [], []);
            tc.verifyEqual(nnz(outScc), 0);
        end
    end
end

function suffix = localExpectedIdSuffix(name)
switch name
    case 'sct_base0_double'
        suffix = 'seeds';
    case 'sic_split_s1only'
        suffix = 'SIC:seeds';
    case 'rtps_tps_volB_seedS1_double'
        suffix = 'RTPS:landmarks';
    case 'rtps_odd3_reject_double'
        suffix = 'RTPS:landmarks';
    otherwise
        error('tReferenceRejections:unknownFixture', ...
            'No expected error id mapping for %s', name);
end
end
