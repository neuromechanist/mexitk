% Smoke test: confirm matitk is callable, capture version string.
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, '00_smoke_test.log'));
diary on;

fprintf('=== which matitk ===\n');
which matitk

fprintf('=== matitk with no args ===\n');
try
    matitk()
catch ME
    fprintf('ERROR: %s\n', ME.message);
end

fprintf('=== small test call: FCA on tiny volume ===\n');
V = double(rand(4,4,4)*255);
try
    o = matitk('FCA',[1 0.0625 3.0], V);
    fprintf('OK, output class=%s size=%s\n', class(o), mat2str(size(o)));
catch ME
    fprintf('ERROR: %s\n', ME.message);
end

diary off;
