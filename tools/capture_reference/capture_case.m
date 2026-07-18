function fixture = capture_case(cfg, opcode, tag, params, input, opts)
% Capture one matitk call into a -v7 fixture. Fault-isolated: any matitk
% error is caught (inner try/catch inside evalc, s05 pattern) and
% recorded, never aborting the campaign. opts (optional struct) fields:
%   seedArg     - arg5 seeds; presence => 5-arg call; may be [] or 'OMIT'
%   arg4        - arg4 second image; presence => passed as arg4 (default [])
%   inputRecipe - char recipe recorded for derived inputs (see README)
%   arg4Recipe  - char recipe recorded for a derived arg4 (see README)
if nargin < 6
    opts = struct();
end
hasSeed = isfield(opts, 'seedArg');
hasArg4 = isfield(opts, 'arg4');

outfile = fullfile(cfg.fixturesDir, sprintf('%s_%s.mat', lower(opcode), tag));

% RESUME MODE: skip this case entirely (no hashing, no matitk call) when
% it was already captured by an earlier, interrupted run. Loads and
% returns the existing fixture so callers that use the return value
% (e.g. s12's cross-check probes) keep working across a resumed campaign.
if local_isresume() && isfile(outfile)
    fprintf('  [resume] %s: already captured, skipping\n', tag);
    loaded = load(outfile, 'fixture');
    fixture = loaded.fixture;
    return;
end

fixture = struct();
fixture.opcode = opcode;
fixture.params = params;
fixture.inputClass = class(input);
fixture.inputSize = size(input);
fixture.inputHash = local_md5(input);
if isfield(opts, 'inputRecipe') && ~isempty(opts.inputRecipe)
    fixture.inputRecipe = opts.inputRecipe;
end
if hasSeed
    fixture.seedArg = opts.seedArg;
end
if hasArg4
    fixture.arg4Hash = local_md5(opts.arg4);
    if isfield(opts, 'arg4Recipe') && ~isempty(opts.arg4Recipe)
        fixture.arg4Recipe = opts.arg4Recipe;
    end
end

if local_isdryrun()
    fixture.success = false;
    fixture.errmsg = 'dryrun';
    fixture.consoleText = '';
    fprintf('  [dryrun] %s: inputClass=%s inputHash=%s\n', tag, class(input), fixture.inputHash);
    save(outfile, 'fixture', '-v7');
    return;
end

arg4 = []; %#ok<NASGU>
if hasArg4
    arg4 = opts.arg4; %#ok<NASGU>
elseif hasSeed
    % The original type-checks arg4 against the input class even when
    % arg4 is conceptually absent: a bare double [] mismatches uint8/
    % single/int32 input with "Both images (inputArrays) must be of the
    % same data type." (measured directly against the real binary on
    % seeded calls). Pass an empty of the INPUT's class instead whenever
    % a seed is present but no real second image is; a no-op for double
    % input (cast([], 'double') is still []).
    arg4 = cast([], class(input)); %#ok<NASGU>
end
seedArg = [];
if hasSeed
    seedArg = opts.seedArg;
end
ok = true;
o = [];

if hasSeed && ischar(seedArg) && strcmp(seedArg, 'OMIT')
    cmd = 'try; o = matitk(opcode, params, input); ok=true; catch me2; disp(["CAUGHT ERROR: " me2.message]); ok=false; end';
elseif hasSeed
    cmd = 'try; o = matitk(opcode, params, input, arg4, seedArg); ok=true; catch me2; disp(["CAUGHT ERROR: " me2.message]); ok=false; end';
elseif hasArg4
    cmd = 'try; o = matitk(opcode, params, input, arg4); ok=true; catch me2; disp(["CAUGHT ERROR: " me2.message]); ok=false; end';
else
    cmd = 'try; o = matitk(opcode, params, input); ok=true; catch me2; disp(["CAUGHT ERROR: " me2.message]); ok=false; end';
end

fprintf('\n===== %s %s (params=%s, class=%s) =====\n', opcode, tag, mat2str(params), class(input));
captured = evalc(cmd);
fprintf('%s', captured);
fixture.consoleText = captured;
if ok
    fixture.success = true;
    fixture.errmsg = '';
    fixture = local_summarize(fixture, o);
    fprintf('  -> outClass=%s size=%s hash=%s min=%g max=%g mean=%g\n', ...
        fixture.outputClass, mat2str(fixture.outputSize), fixture.outputHash, ...
        fixture.outputMin, fixture.outputMax, fixture.outputMean);
else
    fixture.success = false; %#ok<UNRCH>
    fixture.errmsg = captured;   % console text holds the CAUGHT ERROR line
    fixture.output = [];
    fprintf('  FAILED (captured above)\n');
end
save(outfile, 'fixture', '-v7');
end
