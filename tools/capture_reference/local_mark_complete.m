function local_mark_complete(cfg, scriptId)
% Write a zero-byte completion marker cfg.outDir/COMPLETE_<scriptId> as
% the last act before a script's diary off. A script that exits nonzero
% (or is killed) but left its marker behind completed every case in its
% table -- the failure happened at MATLAB shutdown, not mid-script. See
% README "Completion sentinels".
fid = fopen(fullfile(cfg.outDir, sprintf('COMPLETE_%s', scriptId)), 'w');
if fid == -1
    error('local_mark_complete:cannotWrite', ...
        'Could not create completion marker for %s in %s.', scriptId, cfg.outDir);
end
fclose(fid);
end
