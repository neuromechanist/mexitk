% PRIORITY 1 follow-up: characterize exactly what each FOMT output IS.
% Outputs are binary {0,255} masks (established by s01). Now determine:
%  - do outputs partition the volume (each voxel true in exactly one output)?
%  - is each output purely a function of voxel intensity (i.e. an intensity band)?
%  - what are the intensity boundaries of each output (reconstruct thresholds)?
%  - does output j correspond to increasing intensity bands in order j=1..N?
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's01b_fomt_semantics.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vd = double(V);
nBins = 128;

Nlist = [2 3 4];
semantics = struct('N', {}, 'isPartition', {}, 'countHistogram', {}, ...
                    'perOutputIntensityRange', {}, 'isPureIntensityFn', {}, 'coverageFraction', {});
si = 0;

for N = Nlist
    fprintf('\n========== N = %d ==========\n', N);
    out = cell(1,N);
    [out{1:N}] = matitk('FOMT',[N nBins], Vd);

    % Stack as logical masks (255 -> true)
    masks = false([size(Vd) N]);
    for j = 1:N
        masks(:,:,:,j) = (out{j} == 255);
    end

    % 1) Partition check: how many masks true per voxel?
    countPerVoxel = sum(masks, 4);
    ch = accumarray(countPerVoxel(:)+1, 1, [N+2 1])';  % index 1 = count 0
    fprintf('Count-of-true-masks histogram (index=count+1): %s\n', mat2str(ch));
    for c = 0:N
        fprintf('  voxels with exactly %d masks true: %d\n', c, ch(c+1));
    end
    isPartition = all(countPerVoxel(:) == 1);
    fprintf('isPartition (every voxel true in exactly 1 mask) = %d\n', isPartition);
    coverageFraction = sum(countPerVoxel(:) >= 1) / numel(countPerVoxel);
    fprintf('coverageFraction (>=1 mask true) = %.6f\n', coverageFraction);

    % 2) Is each mask a pure function of intensity? For each unique intensity value,
    %    check that all voxels with that intensity have the same mask-membership vector.
    uvals = unique(Vd(:));
    isPureFn = true(1,N);
    for j = 1:N
        mj = masks(:,:,:,j);
        for uv = uvals'
            sel = (Vd == uv);
            vals = mj(sel);
            if ~all(vals == vals(1))
                isPureFn(j) = false;
                fprintf('  out%d NOT pure intensity fn: intensity %g has mixed mask values\n', j, uv);
                break;
            end
        end
    end
    fprintf('isPureIntensityFn per output: %s\n', mat2str(isPureFn));

    % 3) Reconstruct intensity range covered by each output (min/max intensity where mask true)
    ranges = cell(1,N);
    for j = 1:N
        mj = masks(:,:,:,j);
        vv = Vd(mj);
        if isempty(vv)
            ranges{j} = [NaN NaN];
            fprintf('  out%d: EMPTY (no voxels true)\n', j);
        else
            ranges{j} = [min(vv) max(vv)];
            fprintf('  out%d: intensity range [%g, %g], n_true=%d, fraction=%.4f\n', ...
                j, min(vv), max(vv), numel(vv), numel(vv)/numel(Vd));
        end
    end

    % 4) For each unique intensity value in ascending order, report which output is true there
    fprintf('  Intensity -> active output map (ascending intensity):\n');
    for uv = uvals'
        sel = find(Vd == uv, 1);
        [ix,iy,iz] = ind2sub(size(Vd), sel);
        activeOut = find(squeeze(masks(ix,iy,iz,:)))';
        fprintf('    intensity=%3g -> active_output(s)=%s\n', uv, mat2str(activeOut));
    end

    si = si + 1;
    semantics(si).N = N;
    semantics(si).isPartition = isPartition;
    semantics(si).countHistogram = ch;
    semantics(si).perOutputIntensityRange = ranges;
    semantics(si).isPureIntensityFn = isPureFn;
    semantics(si).coverageFraction = coverageFraction;
end

save(fullfile(cfg.fixturesDir, 'fomt_semantics_results.mat'), 'semantics', 'Vd', 'nBins', 'Nlist', '-v7');
fprintf('\nSaved semantics results.\n');
diary off;
