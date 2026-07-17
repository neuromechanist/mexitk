% PRIORITY 1: resolve FOMT output-count semantics.
% For numberOfThresholds = N, probe nargout = 1..N+2 and record success/failure,
% output classes/sizes/unique-values, and whether outputs partition the volume.
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's01_fomt_output_count.log'));
diary on;
format compact;

load mri;             % D: 128x128x1x27 uint8, map
V = squeeze(D);       % 128x128x27 uint8
Vd = double(V);

fprintf('Input volume: class=%s size=%s min=%g max=%g\n', class(V), mat2str(size(V)), double(min(V(:))), double(max(V(:))));

nBins = 128;
Nlist = [2 3 4];

results = struct('N', {}, 'nargoutReq', {}, 'success', {}, 'errmsg', {}, ...
                  'outClasses', {}, 'outSizes', {}, 'outUnique', {}, 'sumIsOnes', {});
ri = 0;

for N = Nlist
    fprintf('\n========== N (numberOfThresholds) = %d ==========\n', N);
    maxTry = N + 2;
    for k = 1:maxTry
        ri = ri + 1;
        results(ri).N = N;
        results(ri).nargoutReq = k;
        fprintf('--- N=%d, requesting nargout=%d ---\n', N, k);
        try
            out = cell(1,k);
            [out{1:k}] = matitk('FOMT',[N nBins], Vd);
            results(ri).success = true;
            results(ri).errmsg = '';
            classes = cell(1,k);
            sizes = cell(1,k);
            uniques = cell(1,k);
            for j = 1:k
                oj = out{j};
                classes{j} = class(oj);
                sizes{j} = size(oj);
                u = unique(oj(:))';
                uniques{j} = u;
                fprintf('  out%d: class=%s size=%s unique_vals=%s (n_unique=%d)\n', ...
                    j, class(oj), mat2str(size(oj)), mat2str(u), numel(u));
            end
            results(ri).outClasses = classes;
            results(ri).outSizes = sizes;
            results(ri).outUnique = uniques;
            % Partition check: if all outputs are same-size binary masks, do they sum to all-ones?
            if k >= 1
                allSameSize = true;
                for j = 2:k
                    if ~isequal(sizes{j}, sizes{1})
                        allSameSize = false;
                    end
                end
                if allSameSize
                    S = zeros(sizes{1});
                    allBinary = true;
                    for j = 1:k
                        oj = double(out{j});
                        uj = unique(oj(:));
                        if ~all(ismember(uj, [0 1]))
                            allBinary = false;
                        end
                        S = S + oj;
                    end
                    results(ri).sumIsOnes = allBinary && all(S(:) == 1);
                    fprintf('  allOutputsBinary=%d, sumEqualsOnesEverywhere=%d (sum unique vals=%s)\n', ...
                        allBinary, results(ri).sumIsOnes, mat2str(unique(S(:))'));
                    % Also check monotonic/cumulative relationship for k>=2
                    if k >= 2
                        for j = 1:k
                            oj = double(out{j});
                            fprintf('    out%d nnz=%d (fraction=%.4f)\n', j, nnz(oj), nnz(oj)/numel(oj));
                        end
                    end
                else
                    results(ri).sumIsOnes = false;
                    fprintf('  outputs have differing sizes, skip sum/partition check\n');
                end
            end
        catch ME
            results(ri).success = false;
            results(ri).errmsg = ME.message;
            results(ri).outClasses = {};
            results(ri).outSizes = {};
            results(ri).outUnique = {};
            results(ri).sumIsOnes = false;
            fprintf('  FAILED: %s\n', ME.message);
        end
    end
end

save(fullfile(cfg.fixturesDir, 'fomt_output_count_results.mat'), 'results', 'V', 'Vd', 'nBins', 'Nlist', '-v7');
fprintf('\nSaved results to fomt_output_count_results.mat\n');

diary off;
