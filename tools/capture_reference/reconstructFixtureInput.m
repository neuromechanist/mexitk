function [vin, vinB] = reconstructFixtureInput(f, name)
%RECONSTRUCTFIXTUREINPUT Reconstruct and verify a fixture's input volume(s).
%
%   VIN = RECONSTRUCTFIXTUREINPUT(F, NAME) reconstructs the input volume for
%   an already-loaded fixture struct F (as produced by the capture harness;
%   see capture_case.m), and verifies it before returning:
%     - class matches F.inputClass;
%     - hash matches F.inputHash, via local_md5 (a hard error if local_md5
%       itself is not resolvable -- an addpath that silently failed must
%       not masquerade as "input verified" when nothing was actually
%       checked).
%   NAME is used only to identify the fixture in error messages (typically
%   the fixture's own filename stem).
%
%   [VIN, VINB] = RECONSTRUCTFIXTUREINPUT(F, NAME) additionally reconstructs
%   the second (arg4/volumeB) input for the two-volume level-set opcodes
%   (SGAC, SLLS, SSDLS; Epic 3 Phase 2), from F.ARG4RECIPE the same way VIN's
%   own INPUTRECIPE is handled below, verified against F.ARG4HASH the same
%   way. VINB is [] when the fixture carries no ARG4RECIPE (every
%   single-volume opcode). There is no ARG4CLASS field to check VINB's class
%   against (unlike INPUTCLASS for VIN): the recipe alone determines it, and
%   hash verification is the only ground truth captured for it.
%
%   This is the single source of truth for fixture input reconstruction:
%   both tests/mexitkFixture.m (loads by name from the committed
%   tests/fixtures/) and tools/classify_fixtures.m (loads from a
%   caller-supplied fixtures directory, so it hands this function an
%   already-loaded struct rather than a name) call this same function,
%   so a recipe or verification fix made here applies to both at once.
%
%   Most fixtures are captured directly against MATLAB's built-in `load mri`
%   volume, so the fixture stores only a hash of it rather than a second copy.
%   Some fixtures (derived binary/label/hole inputs) instead carry an
%   `inputRecipe` field: a MATLAB expression (sometimes a multi-statement
%   sequence assigning intermediates to named variables, always ending by
%   producing a variable named `b`) recorded verbatim from the capture
%   script, `V` referring to the raw `squeeze(mri.D)` volume.
%
% SPDX-License-Identifier: BSD-3-Clause
% Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
% Swartz Center for Computational Neuroscience (SCCN),
% Institute for Neural Computation (INC), UC San Diego.

if isfield(f, 'inputRecipe') && ~isempty(f.inputRecipe)
    vin = reconstructRecipeInput(f.inputRecipe);
else
    mri = load('mri');
    V = squeeze(mri.D);
    switch f.inputClass
        case 'double', vin = double(V);
        case 'single', vin = single(V);
        case 'uint8',  vin = V;
        case 'int32',  vin = int32(V);
        otherwise
            error('reconstructFixtureInput:inputClass', ...
                'Unhandled input class %s', f.inputClass);
    end
end

if ~isa(vin, f.inputClass)
    error('reconstructFixtureInput:inputClass', ...
        '%s: reconstructed input is class %s, fixture recorded inputClass %s', ...
        name, class(vin), f.inputClass);
end

if isfield(f, 'inputHash') && ~isempty(f.inputHash)
    % local_md5 lives alongside this file (tools/capture_reference/); treat
    % it being unresolvable as a hard failure rather than silently skipping
    % verification -- a caller whose addpath quietly failed (a moved/
    % deleted local_md5.m, a broken repo layout) must not masquerade as
    % "input verified" when nothing was actually checked.
    if isempty(which('local_md5'))
        error('reconstructFixtureInput:missingHashTool', ...
            ['%s: cannot verify inputHash because local_md5 is not on the ' ...
             'path (expected at tools/capture_reference/local_md5.m); ' ...
             'refusing to silently skip input verification'], name);
    end
    recomputed = local_md5(vin);
    if ~strcmp(recomputed, f.inputHash)
        error('reconstructFixtureInput:inputHash', ...
            ['%s: reconstructed input hash %s does not match the fixture''s ' ...
             'recorded inputHash %s -- the recipe no longer reproduces the ' ...
             'captured input'], name, recomputed, f.inputHash);
    end
end

vinB = [];
if isfield(f, 'arg4Recipe') && ~isempty(f.arg4Recipe)
    vinB = reconstructRecipeInput(f.arg4Recipe);
    if isfield(f, 'arg4Hash') && ~isempty(f.arg4Hash)
        if isempty(which('local_md5'))
            error('reconstructFixtureInput:missingHashTool', ...
                ['%s: cannot verify arg4Hash because local_md5 is not on the ' ...
                 'path (expected at tools/capture_reference/local_md5.m); ' ...
                 'refusing to silently skip input verification'], name);
        end
        recomputedB = local_md5(vinB);
        if ~strcmp(recomputedB, f.arg4Hash)
            error('reconstructFixtureInput:arg4Hash', ...
                ['%s: reconstructed arg4 hash %s does not match the fixture''s ' ...
                 'recorded arg4Hash %s -- the recipe no longer reproduces the ' ...
                 'captured second volume'], name, recomputedB, f.arg4Hash);
        end
    end
end
end

function vin = reconstructRecipeInput(recipe)
% Evaluate a captured inputRecipe string. Single-expression recipes (no
% internal assignment) return their value directly through `ans`.
% Multi-statement recipes contain their own internal assignments (e.g.
% `b=double(V>30)*255; c=convn(...); ...; b`), which MATLAB's eval cannot
% capture as a function return value directly (`x = eval('a=1; a')` errors
% "Incorrect use of '=' operator", confirmed general eval behaviour, not
% specific to any one recipe) -- so the recipe is run as a bare statement
% list instead (trailing ';' appended only to suppress console echo, not
% altering semantics) and the named result variable `b` is read back,
% mirroring exactly how the capture harness itself reads these recipes
% (see tools/capture_reference/s08_morphology_capture.m).
mri = load('mri');
V = squeeze(mri.D); %#ok<NASGU> referenced by name inside the eval'd recipe
eval([recipe ';']);
if exist('b', 'var')
    vin = b;
else
    vin = ans; %#ok<NOANS>
end
end
