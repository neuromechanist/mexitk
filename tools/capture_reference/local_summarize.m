function fixture = local_summarize(fixture, o)
% Attach the success-path output fields (README/plan Section 3) to fixture.
fixture.output = o;
fixture.outputClass = class(o);
fixture.outputSize = size(o);
fixture.outputHash = local_md5(o);
od = double(o(:));
fixture.outputMin = min(od);
fixture.outputMax = max(od);
fixture.outputMean = mean(od);
u = unique(o(:))';
if numel(u) <= 256
    fixture.outputUnique = u;
    fixture.numLabels = numel(u);
end
end
