function classify_fixtures(fixturesDir, matlabDir)
%CLASSIFY_FIXTURES Re-run every committed fixture and print a verdict.
%
%   CLASSIFY_FIXTURES(FIXTURESDIR, MATLABDIR) reconstructs the input for
%   every per-opcode fixture under FIXTURESDIR, calls the local mexitk build
%   under MATLABDIR with the fixture's own parameters/seeds, and prints one
%   verdict line per fixture plus a per-opcode summary. Both arguments are
%   optional; they default to tests/fixtures and matlab, relative to this
%   file's own repo root, so nothing here names a path specific to any one
%   machine.
%
%   Verdicts:
%     EXACT               - the original succeeded; mexitk's output matches
%                            the captured output in both class and value
%                            (isequal, bit-exact, including for
%                            multi-output fixtures).
%     DEVIATES            - the original succeeded; mexitk's output differs.
%                            RMS and max-abs difference are printed.
%     EXPECTED-REJECTION  - the original rejected the call, and mexitk
%                            rejects it too (both refuse the same input).
%     MEXITK-ACCEPTS-MORE - the original rejected the call, but mexitk
%                            accepts it and returns a defined result (a
%                            deliberate "accept strictly more" deviation;
%                            see docs/COMPATIBILITY.md).
%     MEXITK-REJECTS      - the original succeeded, but mexitk refuses the
%                            call (a deliberate "refuse to reproduce a
%                            defect/UB" deviation; see
%                            docs/COMPATIBILITY.md).
%
%   Fixture files without a top-level `fixture` struct (the older named-shape
%   captures and the s12 cross-check probe summaries; see tests/
%   tFixtureHygiene.m) are not per-opcode calls and are skipped, listed
%   separately at the end.
%
%   This is the tool that produced the Epic 2 Phase 3 classification driving
%   the status promotions in the opcode registry, docs/COMPATIBILITY.md, and
%   README; re-run it after any change that could move agreement with the
%   original (an ITK upgrade, a parameter-mapping fix) rather than editing
%   those numbers by hand.
%
%       matlab -batch "addpath('matlab'); tools_classify_fixtures"
%       matlab -batch "classify_fixtures('tests/fixtures', 'matlab')"
%
% SPDX-License-Identifier: BSD-3-Clause
% Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
% Swartz Center for Computational Neuroscience (SCCN),
% Institute for Neural Computation (INC), UC San Diego.

rootDir = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1 || isempty(fixturesDir)
    fixturesDir = fullfile(rootDir, 'tests', 'fixtures');
end
if nargin < 2 || isempty(matlabDir)
    matlabDir = fullfile(rootDir, 'matlab');
end

addpath(matlabDir);
% reconstructFixtureInput (input reconstruction + class/hash verification,
% shared with tests/mexitkFixture.m) and local_md5.
addpath(fullfile(rootDir, 'tools', 'capture_reference'));
if isempty(which('mexitk'))
    error('classify_fixtures:notBuilt', ...
        'mexitk MEX not found on the path. Build it first; expected in %s', matlabDir);
end

d = dir(fullfile(fixturesDir, '*.mat'));
names = sort({d.name});

verdicts = struct('name', {}, 'opcode', {}, 'verdict', {}, 'detail', {});
skipped = {};

for i = 1:numel(names)
    fname = names{i};
    tag = fname(1:end-4);
    data = load(fullfile(fixturesDir, fname));
    if ~isfield(data, 'fixture')
        skipped{end+1} = fname; %#ok<AGROW>
        continue;
    end
    f = data.fixture;
    [verdict, detail] = classifyOne(f, tag);
    verdicts(end+1) = struct('name', tag, 'opcode', f.opcode, ...
        'verdict', verdict, 'detail', detail); %#ok<AGROW>
    fprintf('%-45s %-11s %-20s %s\n', tag, f.opcode, verdict, detail);
end

fprintf('\n==== per-opcode summary ====\n');
opcodes = unique({verdicts.opcode});
opcodes = sort(opcodes);
tallyVerdicts = {'EXACT', 'DEVIATES', 'EXPECTED-REJECTION', 'MEXITK-ACCEPTS-MORE', 'MEXITK-REJECTS'};
for i = 1:numel(opcodes)
    op = opcodes{i};
    mask = strcmp({verdicts.opcode}, op);
    counts = zeros(1, numel(tallyVerdicts));
    for k = 1:numel(tallyVerdicts)
        counts(k) = nnz(mask & strcmp({verdicts.verdict}, tallyVerdicts{k}));
    end
    fprintf('%-10s total=%-4d exact=%-3d deviates=%-3d expected-rejection=%-3d accepts-more=%-3d mexitk-rejects=%-3d\n', ...
        op, nnz(mask), counts(1), counts(2), counts(3), counts(4), counts(5));
end

fprintf('\n==== skipped (no top-level fixture struct) ====\n');
for i = 1:numel(skipped)
    fprintf('  %s\n', skipped{i});
end
fprintf('\ntotal fixtures: %d, classified: %d, skipped: %d\n', ...
    numel(names), numel(verdicts), numel(skipped));
end

function [verdict, detail] = classifyOne(f, tag)
try
    [vin, vinB] = reconstructFixtureInput(f, tag);
catch err
    verdict = 'RECONSTRUCT-ERROR';
    detail = err.message;
    return;
end

% arg4 (volumeB) is the reconstructed second volume for the two-volume
% level-set opcodes (SGAC, SLLS, SSDLS; Epic 3 Phase 2, via arg4Recipe),
% falling back to the class-matched-empty placeholder every other opcode
% still uses -- see mexitkFixtureCall.m for the same convention.
if isempty(vinB)
    arg4 = cast([], class(vin));
else
    arg4 = vinB;
end

args = {f.opcode, f.params, vin};
if isfield(f, 'seedArg')
    args = [args, {arg4}, {f.seedArg}];
end

isMultiOutput = isfield(f, 'outputs') && f.success;
if isMultiOutput
    n = f.numOutputs;
else
    n = 1;
end

try
    if isMultiOutput
        outs = cell(1, n);
        [outs{1:n}] = mexitk(args{:});
    else
        out = mexitk(args{:});
    end
    mexitkSucceeded = true;
catch mexErr
    mexitkSucceeded = false;
end

if f.success
    if ~mexitkSucceeded
        verdict = 'MEXITK-REJECTS';
        detail = sprintf('%s: %s', mexErr.identifier, mexErr.message);
        return;
    end
    % isequal alone is not sufficient for an EXACT verdict: it compares
    % values only, so a value-equal but wrong-class result (e.g. mexitk
    % returning double where the original returned uint8) would otherwise
    % pass silently. tests/tReferenceExact.m already checks class
    % separately (tc.verifyClass); match that strictness here.
    if isMultiOutput
        allEqual = true;
        worstRms = 0;
        worstMax = 0;
        classDetail = '';
        for k = 1:n
            sameClass = strcmp(class(outs{k}), f.outputClasses{k});
            sameValue = isequal(outs{k}, f.outputs{k});
            if sameClass && sameValue
                continue;
            end
            allEqual = false;
            if ~sameClass
                classDetail = [classDetail, sprintf('output %d class %s!=%s; ', ...
                    k, class(outs{k}), f.outputClasses{k})]; %#ok<AGROW>
            end
            if ~sameValue
                dk = double(outs{k}(:)) - double(f.outputs{k}(:));
                worstRms = max(worstRms, sqrt(mean(dk .^ 2)));
                worstMax = max(worstMax, max(abs(dk)));
            end
        end
        if allEqual
            verdict = 'EXACT';
            detail = sprintf('%d outputs', n);
        else
            verdict = 'DEVIATES';
            detail = sprintf('%sworst rms=%.6g maxabs=%.6g (over %d outputs)', ...
                classDetail, worstRms, worstMax, n);
        end
    else
        sameClass = strcmp(class(out), f.outputClass);
        sameValue = isequal(out, f.output);
        if sameClass && sameValue
            verdict = 'EXACT';
            detail = '';
        else
            verdict = 'DEVIATES';
            if sameValue
                detail = '';
            else
                d = double(out(:)) - double(f.output(:));
                detail = sprintf('rms=%.6g maxabs=%.6g ndiff=%d/%d', ...
                    sqrt(mean(d .^ 2)), max(abs(d)), nnz(d), numel(d));
            end
            if ~sameClass
                detail = sprintf('class %s!=%s; %s', class(out), f.outputClass, detail);
            end
        end
    end
else
    if mexitkSucceeded
        verdict = 'MEXITK-ACCEPTS-MORE';
        detail = 'original rejected this input; mexitk runs and returns a defined result';
    else
        verdict = 'EXPECTED-REJECTION';
        detail = sprintf('%s: %s', mexErr.identifier, mexErr.message);
    end
end
end
