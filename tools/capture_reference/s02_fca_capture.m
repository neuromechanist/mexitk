% PRIORITY 2: capture FCA (CurvatureAnisotropicDiffusion) fixtures.
% params = [numberOfIterations timeStep conductance]
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's02_fca_capture.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vd = double(V);
Vs = single(V);
fixdir = [cfg.fixturesDir filesep];

cases = {};
cases{end+1} = struct('tag','fca_iter5_ts0p0625_cond3_double','params',[5 0.0625 3.0],'input',Vd,'spacing',[]);
cases{end+1} = struct('tag','fca_iter1_ts0p0625_cond3_double','params',[1 0.0625 3.0],'input',Vd,'spacing',[]);
cases{end+1} = struct('tag','fca_iter5_ts0p0625_cond3_single','params',[5 0.0625 3.0],'input',Vs,'spacing',[]);
cases{end+1} = struct('tag','fca_iter1_ts0p0625_cond3_single','params',[1 0.0625 3.0],'input',Vs,'spacing',[]);
cases{end+1} = struct('tag','fca_iter1_ts0p0417_cond3_double_stable','params',[1 0.0417 3.0],'input',Vd,'spacing',[]);
cases{end+1} = struct('tag','fca_iter1_ts0p0625_cond3_double_spacing112','params',[1 0.0625 3.0],'input',Vd,'spacing',[1 1 2]);
cases{end+1} = struct('tag','fca_iter1_ts0p0625_cond3_double_spacing111','params',[1 0.0625 3.0],'input',Vd,'spacing',[1 1 1]);

for ci = 1:numel(cases)
    c = cases{ci};
    fprintf('\n===== CASE: %s =====\n', c.tag);
    fprintf('params=%s inputClass=%s spacing=%s\n', mat2str(c.params), class(c.input), mat2str(c.spacing));
    fixture = struct();
    fixture.opcode = 'FCA';
    fixture.params = c.params;
    fixture.inputClass = class(c.input);
    fixture.inputSize = size(c.input);
    fixture.inputHash = local_md5(c.input);
    fixture.spacing = c.spacing;
    try
        if isempty(c.spacing)
            captured = evalc('o = matitk(''FCA'', c.params, c.input);');
        else
            captured = evalc('o = matitk(''FCA'', c.params, c.input, [], [], c.spacing);');
        end
        fprintf('%s', captured);
        fixture.success = true;
        fixture.errmsg = '';
        fixture.consoleText = captured;
        fixture.output = o;
        fixture.outputClass = class(o);
        fixture.outputSize = size(o);
        fixture.outputHash = local_md5(o);
        fixture.outputMin = double(min(o(:)));
        fixture.outputMax = double(max(o(:)));
        fixture.outputMean = mean(double(o(:)));
        fprintf('  -> outputClass=%s size=%s min=%g max=%g mean=%g hash=%s\n', ...
            fixture.outputClass, mat2str(fixture.outputSize), fixture.outputMin, fixture.outputMax, fixture.outputMean, fixture.outputHash);
    catch ME
        fixture.success = false;
        fixture.errmsg = ME.message;
        fixture.consoleText = '';
        fixture.output = [];
        fprintf('  FAILED: %s\n', ME.message);
    end
    save(sprintf('%sfca_%s.mat', fixdir, c.tag), 'fixture', '-v7');
end

% Direct isequal comparison: spacing [1 1 1] vs [1 1 2] vs default(no spacing arg) on same params
fprintf('\n===== Spacing effect comparison (FCA, [1 0.0625 3.0], double) =====\n');
o_default = matitk('FCA',[1 0.0625 3.0], Vd);
o_sp111   = matitk('FCA',[1 0.0625 3.0], Vd, [], [], [1 1 1]);
o_sp112   = matitk('FCA',[1 0.0625 3.0], Vd, [], [], [1 1 2]);
fprintf('isequal(default, spacing111) = %d\n', isequal(o_default, o_sp111));
fprintf('isequal(default, spacing112) = %d\n', isequal(o_default, o_sp112));
fprintf('isequal(spacing111, spacing112) = %d\n', isequal(o_sp111, o_sp112));
if ~isequal(o_default, o_sp112)
    d = double(o_default) - double(o_sp112);
    fprintf('max abs diff (default vs spacing112) = %g\n', max(abs(d(:))));
end
spacingCompare = struct('isequal_default_sp111', isequal(o_default,o_sp111), ...
                         'isequal_default_sp112', isequal(o_default,o_sp112), ...
                         'isequal_sp111_sp112', isequal(o_sp111,o_sp112));
save(sprintf('%sfca_spacing_comparison.mat', fixdir), 'spacingCompare', 'o_default','o_sp111','o_sp112', '-v7');

diary off;
