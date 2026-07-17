% PRIORITY 3: behavioral edge cases / contract documentation.
% Uses an inner try/catch INSIDE the evalc'd string so that printed console text
% is captured even when matitk() throws a MATLAB error (evalc loses partial output
% if the evaluated statement itself errors without an inner catch).
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's05_edge_cases.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vd = double(V);
fixdir = [cfg.fixturesDir filesep];
edge = struct();

fprintf('\n===== matitk() no args =====\n');
ok = true; %#ok<NASGU>
txt = evalc('try; matitk(); ok = true; catch me2; disp([''CAUGHT ERROR: '' me2.message]); ok = false; end');
fprintf('%s\n', txt);
edge.noargs = struct('success', ok, 'text', txt);

fprintf('\n===== matitk(''?'') help/list opcode =====\n');
ok = true;
txt = evalc('try; matitk(''?''); ok = true; catch me2; disp([''CAUGHT ERROR: '' me2.message]); ok = false; end');
fprintf('%s\n', txt);
edge.helpOpcode = struct('success', ok, 'text', txt);

fprintf('\n===== unknown opcode =====\n');
ok = true;
txt = evalc('try; o = matitk(''ZZZZ'', [1], Vd); ok = true; catch me2; disp([''CAUGHT ERROR: '' me2.message]); ok = false; end');
fprintf('%s\n', txt);
edge.unknownOpcode = struct('success', ok, 'text', txt);

fprintf('\n===== too few params (FCA needs 3, given 2) =====\n');
ok = true;
txt = evalc('try; o = matitk(''FCA'', [1 0.0625], Vd); ok = true; catch me2; disp([''CAUGHT ERROR: '' me2.message]); ok = false; end');
fprintf('%s\n', txt);
edge.tooFewParams = struct('success', ok, 'text', txt);

fprintf('\n===== too many params (FCA needs 3, given 5) =====\n');
ok = true;
txt = evalc('try; o = matitk(''FCA'', [1 0.0625 3.0 99 99], Vd); ok = true; catch me2; disp([''CAUGHT ERROR: '' me2.message]); ok = false; end');
fprintf('%s\n', txt);
edge.tooManyParams = struct('success', ok, 'text', txt);

fprintf('\n===== no input volume (params only) =====\n');
ok = true;
txt = evalc('try; o = matitk(''FCA'', [1 0.0625 3.0]); ok = true; catch me2; disp([''CAUGHT ERROR: '' me2.message]); ok = false; end');
fprintf('%s\n', txt);
edge.noInputVolume = struct('success', ok, 'text', txt);

fprintf('\n===== string object (double-quoted) opcode vs char =====\n');
ok = true;
txt = evalc('try; o = matitk("FCA", [1 0.0625 3.0], Vd); ok = true; catch me2; disp([''CAUGHT ERROR: '' me2.message]); ok = false; end');
fprintf('%s\n', txt);
edge.stringOpcode = struct('success', ok, 'text', txt);

fprintf('\n===== char("FCA") opcode (should work like single-quoted) =====\n');
ok = true;
txt = evalc('try; o = matitk(char("FCA"), [1 0.0625 3.0], Vd); ok = true; catch me2; disp([''CAUGHT ERROR: '' me2.message]); ok = false; end');
fprintf('%s\n', txt);
if ok
    edge.charCastOpcode = struct('success', true, 'text', txt, 'outputHash', local_md5(o));
else
    edge.charCastOpcode = struct('success', false, 'text', txt);
end

fprintf('\n===== opcode case sensitivity: FOMT vs fomt (params [2 50]) =====\n');
out1 = cell(1,2); out2 = cell(1,2);
txt1 = evalc('[out1{1:2}] = matitk(''FOMT'', [2 50], Vd);');
txt2 = evalc('[out2{1:2}] = matitk(''fomt'', [2 50], Vd);');
same = isequal(out1, out2);
fprintf('UPPERCASE text:\n%s\n', txt1);
fprintf('lowercase text:\n%s\n', txt2);
fprintf('isequal(uppercase_outputs, lowercase_outputs) = %d\n', same);
edge.caseSensitivity = struct('success', true, 'upperText', txt1, 'lowerText', txt2, 'outputsEqual', same);

fprintf('\n===== FOMT spacing effect: [1 1 1] vs [1 1 2] (params [2 50]) =====\n');
outA = cell(1,2); outB = cell(1,2);
evalc('[outA{1:2}] = matitk(''FOMT'', [2 50], Vd, [], [], [1 1 1]);');
evalc('[outB{1:2}] = matitk(''FOMT'', [2 50], Vd, [], [], [1 1 2]);');
same = isequal(outA, outB);
fprintf('isequal(FOMT spacing111, spacing112) = %d\n', same);
edge.fomtSpacingEffect = struct('success', true, 'outputsEqual', same);

fprintf('\n===== SWS spacing effect: [1 1 1] vs [1 1 2] (params [0.05 0.01]) =====\n');
oA = []; oB = [];
txtA = evalc('oA = matitk(''SWS'', [0.05 0.01], Vd, [], [], [1 1 1]);');
txtB = evalc('oB = matitk(''SWS'', [0.05 0.01], Vd, [], [], [1 1 2]);');
same = isequal(oA, oB);
fprintf('isequal(SWS spacing111, spacing112) = %d\n', same);
edge.swsSpacingEffect = struct('success', true, 'outputsEqual', same);

fprintf('\n===== 2D input (single slice) on FCA =====\n');
V2d = squeeze(Vd(:,:,14));
fprintf('V2d size=%s\n', mat2str(size(V2d)));
ok = true; o2 = [];
txt = evalc('try; o2 = matitk(''FCA'', [1 0.0625 3.0], V2d); ok = true; catch me2; disp([''CAUGHT ERROR: '' me2.message]); ok = false; end');
fprintf('%s\n', txt);
if ok
    fprintf('output size=%s class=%s\n', mat2str(size(o2)), class(o2));
    edge.fca2DInput = struct('success', true, 'text', txt, 'outputSize', size(o2));
else
    edge.fca2DInput = struct('success', false, 'text', txt);
end

fprintf('\n===== 2D input (single slice) on FOMT =====\n');
ok = true; out2d = cell(1,2);
txt = evalc('try; [out2d{1:2}] = matitk(''FOMT'', [2 50], V2d); ok = true; catch me2; disp([''CAUGHT ERROR: '' me2.message]); ok = false; end');
fprintf('%s\n', txt);
if ok
    fprintf('output1 size=%s class=%s\n', mat2str(size(out2d{1})), class(out2d{1}));
    edge.fomt2DInput = struct('success', true, 'text', txt, 'outputSize', size(out2d{1}));
else
    edge.fomt2DInput = struct('success', false, 'text', txt);
end

fprintf('\n===== 2D input (single slice) on SWS =====\n');
ok = true; o2sws = [];
txt = evalc('try; o2sws = matitk(''SWS'', [0.05 0.01], V2d); ok = true; catch me2; disp([''CAUGHT ERROR: '' me2.message]); ok = false; end');
fprintf('%s\n', txt);
if ok
    fprintf('output size=%s class=%s unique=%s\n', mat2str(size(o2sws)), class(o2sws), mat2str(unique(o2sws(:))'));
    edge.sws2DInput = struct('success', true, 'text', txt, 'outputSize', size(o2sws));
else
    edge.sws2DInput = struct('success', false, 'text', txt);
end

save(sprintf('%sedge_cases.mat', fixdir), 'edge', '-v7');
fprintf('\nSaved edge_cases.mat\n');
diary off;
