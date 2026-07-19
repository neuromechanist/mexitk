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
%   Input reconstruction and verification (class + inputHash) are delegated
%   to tools/capture_reference/reconstructFixtureInput.m, the single source
%   of truth also used by tools/classify_fixtures.m, so a recipe or
%   verification fix made there applies to both callers at once. See that
%   function's own docstring for the inputRecipe/inputHash details.
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
addpath(fullfile(fileparts(here), 'tools', 'capture_reference'));  % reconstructFixtureInput, local_md5

s = load(fullfile(here, 'fixtures', [name '.mat']));
fx = s.fixture;

vin = reconstructFixtureInput(fx, name);
end
