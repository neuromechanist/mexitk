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
%   The input is MATLAB's built-in `load mri` volume, so the fixture stores only
%   a hash of it rather than a second copy.
%
% SPDX-License-Identifier: BSD-3-Clause
% Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
% Swartz Center for Computational Neuroscience (SCCN),
% Institute for Neural Computation (INC), UC San Diego.

here = fileparts(mfilename('fullpath'));
s = load(fullfile(here, 'fixtures', [name '.mat']));
fx = s.fixture;

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
