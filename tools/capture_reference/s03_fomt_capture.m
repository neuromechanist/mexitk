% PRIORITY 2: capture FOMT (OtsuMultipleThresholds) fixtures across param sets and types.
% params = [numberOfThresholds numberOfBins]; nargout MUST equal numberOfThresholds (see s01/s01b).
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's03_fomt_capture.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vd = double(V);
Vs = single(V);
Vu = uint8(V);
fixdir = [cfg.fixturesDir filesep];

paramSets = {[2 50], [4 100], [3 128]};
inputs = struct('tag', {'double','single','uint8'}, 'data', {Vd, Vs, Vu});

for pi = 1:numel(paramSets)
    p = paramSets{pi};
    N = p(1);
    for ii = 1:numel(inputs)
        inp = inputs(ii);
        tag = sprintf('fomt_N%d_bins%d_%s', p(1), p(2), inp.tag);
        fprintf('\n===== CASE: %s (params=%s) =====\n', tag, mat2str(p));
        fixture = struct();
        fixture.opcode = 'FOMT';
        fixture.params = p;
        fixture.inputClass = inp.tag;
        fixture.inputSize = size(inp.data);
        fixture.inputHash = local_md5(inp.data);
        try
            out = cell(1,N);
            captured = evalc('[out{1:N}] = matitk(''FOMT'', p, inp.data);');
            fprintf('%s', captured);
            fixture.success = true;
            fixture.errmsg = '';
            fixture.consoleText = captured;
            fixture.numOutputs = N;
            outClasses = cell(1,N); outHashes = cell(1,N); outUnique = cell(1,N); outFrac = zeros(1,N);
            for j = 1:N
                oj = out{j};
                outClasses{j} = class(oj);
                outHashes{j} = local_md5(oj);
                outUnique{j} = unique(oj(:))';
                outFrac(j) = nnz(oj)/numel(oj);
                fprintf('  out%d: class=%s unique=%s fraction_nonzero=%.4f hash=%s\n', ...
                    j, outClasses{j}, mat2str(outUnique{j}), outFrac(j), outHashes{j});
            end
            fixture.outputs = {out{:}};
            fixture.outputClasses = outClasses;
            fixture.outputHashes = outHashes;
            fixture.outputUnique = outUnique;
            fixture.outputFractionNonzero = outFrac;
        catch ME
            fixture.success = false;
            fixture.errmsg = ME.message;
            fixture.consoleText = '';
            fprintf('  FAILED: %s\n', ME.message);
        end
        save(sprintf('%s%s.mat', fixdir, tag), 'fixture', '-v7');
    end
end

diary off;
