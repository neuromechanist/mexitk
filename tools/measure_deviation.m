function measure_deviation(rootDir)
%MEASURE_DEVIATION Re-measure mexitk's deviation from the matitk reference.
%
%   Prints the measured baselines in the exact form the test files expect, so
%   that after an ITK upgrade the numbers in tests/tFcaReference.m and
%   tests/tSwsReference.m can be refreshed from observation rather than guessed.
%
%   Refreshing a baseline is a deliberate act: a changed number means mexitk's
%   agreement with the 2006 binary moved, which belongs in docs/COMPATIBILITY.md
%   and in the commit message. Do not paste new numbers in just to make the
%   suite green.
%
%       matlab -batch "addpath('matlab'); measure_deviation('.')"
%
% SPDX-License-Identifier: BSD-3-Clause
% Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
% Swartz Center for Computational Neuroscience (SCCN),
% Institute for Neural Computation (INC), UC San Diego.

if nargin < 1 || isempty(rootDir)
    rootDir = fileparts(fileparts(mfilename('fullpath')));
end
addpath(fullfile(rootDir, 'matlab'));
addpath(fullfile(rootDir, 'tests'));

fprintf('\n%% tests/tFcaReference.m -> Cases\n');
fcaCases = {'fca_fca_iter1_ts0p0625_cond3_double', 'fca_fca_iter5_ts0p0625_cond3_double', ...
            'fca_fca_iter1_ts0p0625_cond3_single', 'fca_fca_iter5_ts0p0625_cond3_single'};
for i = 1:numel(fcaCases)
    [fx, vin] = mexitkFixture(fcaCases{i});
    got = mexitk('FCA', fx.params, vin);
    e = abs(double(got(:)) - double(fx.output(:)));
    fprintf("    '%s', %.6e, %.6e; ...\n", fcaCases{i}, sqrt(mean(e .^ 2)), max(e));
end

fprintf('\n%% FOMT bit-exactness (expect EXACT for double/single)\n');
fomtCases = {'fomt_N2_bins50_double', 'fomt_N2_bins50_single', 'fomt_N2_bins50_uint8', ...
             'fomt_N3_bins128_double', 'fomt_N3_bins128_single', 'fomt_N3_bins128_uint8', ...
             'fomt_N4_bins100_double', 'fomt_N4_bins100_single', 'fomt_N4_bins100_uint8'};
for i = 1:numel(fomtCases)
    [fx, vin] = mexitkFixture(fomtCases{i});
    N = fx.params(1);
    outs = cell(1, N);
    [outs{1:N}] = mexitk('FOMT', fx.params, vin);
    worst = 0;
    for k = 1:N
        worst = max(worst, mean(double(outs{k}(:)) ~= double(fx.outputs{k}(:))));
    end
    if worst == 0
        fprintf('    %-26s EXACT\n', fomtCases{i});
    else
        fprintf('    %-26s worst voxel disagreement %.4f%%\n', fomtCases{i}, 100 * worst);
    end
end

fprintf('\n%% tests/tSwsReference.m -> seedRegionExtractionMatchesOriginal\n');
seeds = [64 64 14; 40 60 10; 70 50 20; 64 64 5];
swsCases = {'sws_level0p05_thresh0p01_seed64_64_14', 'sws_level0p1_thresh0p05', ...
            'sws_level0p02_thresh0p001', 'sws_level0p5_thresh0p5'};
exact = 0; total = 0; worstDice = 1;
for n = 1:numel(swsCases)
    [fx, vin] = mexitkFixture(swsCases{n});
    got = mexitk('SWS', fx.params, vin);
    fprintf('    %-42s regions ref=%d got=%d\n', swsCases{n}, ...
        numel(unique(fx.output(:))), numel(unique(got(:))));
    for s = 1:size(seeds, 1)
        p = seeds(s, :);
        br = fx.output == fx.output(p(1), p(2), p(3));
        bg = got == got(p(1), p(2), p(3));
        total = total + 1;
        if isequal(br, bg)
            exact = exact + 1;
        end
        worstDice = min(worstDice, 2 * sum(br(:) & bg(:)) / (sum(br(:)) + sum(bg(:))));
    end
end
fprintf('    exact seed regions = %d/%d, worst Dice = %.6f\n', exact, total, worstDice);
end
