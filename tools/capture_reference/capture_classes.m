function capture_classes(cfg, opcode, tagPrefix, params, classNames, classVals, useIdx)
% Run capture_case for opcode/params across a subset of {classNames,
% classVals} selected by useIdx, tagging each <tagPrefix>_<className>.
for k = useIdx
    tag = sprintf('%s_%s', tagPrefix, classNames{k});
    capture_case(cfg, opcode, tag, params, classVals{k});
end
end
