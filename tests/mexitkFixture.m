function [fx, vin] = mexitkFixture(name)
% mexitkFixture  Load a reference fixture captured from the original matitk.
%
%   [FX, VIN] = mexitkFixture(NAME) returns the fixture struct FX and the input
%   volume VIN cast to the class the capture used.
%
%   Fixtures were captured by running the original MATITK v.2.4.04 (Aug 18 2006)
%   mexa64 binary (md5 c7d1432080e9edc6795a38717f5ab628) on Linux x86_64. They
%   cannot be regenerated without that binary, which is why they are committed
%   rather than built. See tools/capture_reference/ for the capture harness.
%
%   Most fixtures are captured directly against MATLAB's built-in `load mri`
%   volume, so the fixture stores only a hash of it rather than a second copy.
%   Some fixtures (derived binary/label/hole inputs) instead carry an
%   `inputRecipe` field: a MATLAB expression (sometimes a multi-statement
%   sequence assigning intermediates to named variables, always ending by
%   producing a variable named `b`) recorded verbatim from the capture
%   script, `V` referring to the raw `squeeze(mri.D)` volume. VIN is
%   reconstructed by evaluating that recipe, and the reconstruction is
%   verified against the fixture's own inputHash, so a recipe that no
%   longer reproduces the captured input fails loudly here rather than
%   silently comparing against the wrong data downstream.
%
%   Seeded fixtures carry a `seedArg` field ([d1 d2 d3 d1 d2 d3 ...], the same
%   convention as mexitk's own seed argument). Callers pass it through as
%   mexitk's 5th argument, with the 4th (unused second image) argument as
%   cast([], class(VIN)) to match the class-matched-empty convention the
%   capture harness itself uses (see docs/COMPATIBILITY.md, "Seeded calls
%   type-check an absent second image against the input class").
%
%   Fixtures where the original rejected the call (fx.success == false) carry
%   no output; fx.errmsg holds the original's error text for rejection tests.
%
% SPDX-License-Identifier: BSD-3-Clause
% Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
% Swartz Center for Computational Neuroscience (SCCN),
% Institute for Neural Computation (INC), UC San Diego.

here = fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(here), 'tools', 'capture_reference'));  % local_md5

s = load(fullfile(here, 'fixtures', [name '.mat']));
fx = s.fixture;

if isfield(fx, 'inputRecipe') && ~isempty(fx.inputRecipe)
    vin = reconstructRecipeInput(fx.inputRecipe);
else
    mri = load('mri');
    V = squeeze(mri.D);
    switch fx.inputClass
        case 'double', vin = double(V);
        case 'single', vin = single(V);
        case 'uint8',  vin = V;
        case 'int32',  vin = int32(V);
        otherwise
            error('mexitkFixture:inputClass', 'Unhandled input class %s', fx.inputClass);
    end
end

if ~isa(vin, fx.inputClass)
    error('mexitkFixture:inputClass', ...
        '%s: reconstructed input is class %s, fixture recorded inputClass %s', ...
        name, class(vin), fx.inputClass);
end

if isfield(fx, 'inputHash') && ~isempty(fx.inputHash) && ~isempty(which('local_md5'))
    recomputed = local_md5(vin);
    if ~strcmp(recomputed, fx.inputHash)
        error('mexitkFixture:inputHash', ...
            ['%s: reconstructed input hash %s does not match the fixture''s ' ...
             'recorded inputHash %s -- the recipe no longer reproduces the ' ...
             'captured input'], name, recomputed, fx.inputHash);
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
