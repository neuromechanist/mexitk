function failed = run_mexitk_tests(rootDir)
%RUN_MEXITK_TESTS Run the mexitk test suite.
%
%   FAILED = run_mexitk_tests(ROOTDIR) runs every test under ROOTDIR/tests and
%   returns the number of failures, so CI can use it as an exit code:
%
%       matlab -batch "exit(run_mexitk_tests('.'))"
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

if isempty(which('mexitk'))
    error('run_mexitk_tests:notBuilt', ...
        ['mexitk MEX not found on the path. Build it first; see BUILDING.md. ' ...
         'Expected in %s'], fullfile(rootDir, 'matlab'));
end

suite = matlab.unittest.TestSuite.fromFolder(fullfile(rootDir, 'tests'));
runner = matlab.unittest.TestRunner.withTextOutput( ...
    'OutputDetail', matlab.unittest.Verbosity.Concise);
results = runner.run(suite);

failed = nnz([results.Failed]);

fprintf('\n==== mexitk test summary ====\n');
fprintf('  passed  : %d\n', nnz([results.Passed]));
fprintf('  failed  : %d\n', failed);
fprintf('  skipped : %d\n', nnz([results.Incomplete]));
fprintf('  duration: %.1f s\n', sum([results.Duration]));
end
