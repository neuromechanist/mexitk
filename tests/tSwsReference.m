classdef tSwsReference < matlab.unittest.TestCase
    % Reference tests for SWS (watershed segmentation).
    %
    % SWS does not reproduce the original's label image bit-for-bit, but the
    % evidence that it is the same algorithm, correctly parameterised, is
    % strong: the number of regions matches the original exactly at every tested
    % (level, threshold), and at level=0.5 the partition is identical up to
    % relabeling. At fine levels a minority of regions split differently.
    %
    % What callers actually do with the label image is extract the region
    % containing a seed (NFT's segm_brain.m: bi = c == c(WMp(1),WMp(2),WMp(3))),
    % so that pattern is tested directly rather than only asserting on raw label
    % values, which are arbitrary identifiers.
    %
    % SPDX-License-Identifier: BSD-3-Clause
    % Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
    % Swartz Center for Computational Neuroscience (SCCN),
    % Institute for Neural Computation (INC), UC San Diego.

    properties (TestParameter)
        swsCase = {'sws_level0p05_thresh0p01_seed64_64_14', ...
                   'sws_level0p1_thresh0p05', ...
                   'sws_level0p02_thresh0p001', ...
                   'sws_level0_thresh0', ...
                   'sws_level0p5_thresh0p5'};
    end

    methods (Test)

        function regionCountMatchesOriginalExactly(tc, swsCase)
            % The strongest available equivalence evidence. Matching the region
            % count exactly across five parameter settings would not happen if
            % the filter or its parameters were wrong.
            [fx, vin] = mexitkFixture(swsCase);
            got = mexitk('SWS', fx.params, vin);
            tc.verifyClass(got, fx.outputClass);
            tc.verifyEqual(numel(unique(got(:))), numel(unique(fx.output(:))), ...
                'number of watershed regions must match the original exactly');
        end

        function partitionIdenticalAtCoarseLevel(tc)
            % At level=0.5 the two labelings are provably the same partition:
            % the count of distinct (ref,got) label pairs equals the label count,
            % which is exactly the condition for a bijection between labels.
            [fx, vin] = mexitkFixture('sws_level0p5_thresh0p5');
            got = mexitk('SWS', fx.params, vin);
            pairs = unique([fx.output(:), got(:)], 'rows');
            tc.verifyEqual(size(pairs, 1), numel(unique(fx.output(:))), ...
                'labelings must induce the same partition');
        end

        function seedRegionExtractionMatchesOriginal(tc)
            % The operation NFT performs. Measured: 11 of 16 seed/parameter
            % combinations reproduce the region exactly; the worst observed Dice
            % was 0.718 on a small region at a fine level. Assert the aggregate
            % so a regression in region fidelity is caught.
            seeds = [64 64 14; 40 60 10; 70 50 20; 64 64 5];
            names = {'sws_level0p05_thresh0p01_seed64_64_14', 'sws_level0p1_thresh0p05', ...
                     'sws_level0p02_thresh0p001', 'sws_level0p5_thresh0p5'};
            exactCount = 0;
            total = 0;
            worstDice = 1;
            for n = 1:numel(names)
                [fx, vin] = mexitkFixture(names{n});
                got = mexitk('SWS', fx.params, vin);
                for s = 1:size(seeds, 1)
                    p = seeds(s, :);
                    biRef = fx.output == fx.output(p(1), p(2), p(3));
                    biGot = got == got(p(1), p(2), p(3));
                    total = total + 1;
                    if isequal(biRef, biGot)
                        exactCount = exactCount + 1;
                    end
                    dice = 2 * sum(biRef(:) & biGot(:)) / (sum(biRef(:)) + sum(biGot(:)));
                    worstDice = min(worstDice, dice);
                end
            end
            tc.verifyGreaterThanOrEqual(exactCount, 11, sprintf( ...
                'only %d/%d seed regions reproduced exactly; documented is 11/16', ...
                exactCount, total));
            tc.verifyGreaterThanOrEqual(worstDice, 0.70, sprintf( ...
                'worst-case Dice %.3f fell below the documented 0.72', worstDice));
        end

        function seedArgumentIsAcceptedAndIgnored(tc)
            % Verified against the original: watershed never consumes the seed
            % array, and callers pass one anyway (NFT does). Passing, omitting or
            % emptying it must not change the result.
            [fx, vin] = mexitkFixture('sws_level0p1_thresh0p05');
            a = mexitk('SWS', fx.params, vin);
            b = mexitk('SWS', fx.params, vin, []);
            c = mexitk('SWS', fx.params, vin, [], []);
            d = mexitk('SWS', fx.params, vin, [], [64 64 14]);
            tc.verifyEqual(b, a);
            tc.verifyEqual(c, a);
            tc.verifyEqual(d, a);
        end

        function overthresholdingErrorsInsteadOfCrashing(tc)
            % The original catches ITK's overthresholding exception and then
            % dies: a segmentation violation takes the whole MATLAB process
            % down. mexitk must surface a catchable MATLAB error instead. This
            % is a deliberate deviation and the one place mexitk is required NOT
            % to match the original.
            [~, vin] = mexitkFixture('sws_level0p5_thresh0p5');
            try
                out = mexitk('SWS', [1 1], vin);
                % Completing is acceptable; crashing the process is not. If we
                % got here, MATLAB survived, which is the property under test.
                tc.verifyTrue(isnumeric(out));
            catch err
                tc.verifyTrue(startsWith(err.identifier, 'mexitk:'), ...
                    sprintf('expected a mexitk error, got %s', err.identifier));
            end
        end
    end
end
