function got = mexitkFixtureCall(opcode, fx, vin)
%MEXITKFIXTURECALL Invoke mexitk for a loaded fixture, applying the seedArg convention.
%
%   GOT = MEXITKFIXTURECALL(OPCODE, FX, VIN) calls mexitk(OPCODE, FX.PARAMS,
%   VIN), passing FX.SEEDARG as the 5th argument (with a class-matched empty
%   4th argument) when the fixture carries one -- see mexitkFixture.m for
%   the seedArg convention. OPCODE is taken as its own argument rather than
%   always read from FX.OPCODE so callers that key off a separately tracked
%   but expected-equal opcode (tReferenceBounded's own Cases table) can
%   share this helper too.
%
%   Shared by tReferenceExact.m, tReferenceBounded.m, and
%   tReferenceRejections.m so the calling convention has one definition.
%
% SPDX-License-Identifier: BSD-3-Clause
% Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
% Swartz Center for Computational Neuroscience (SCCN),
% Institute for Neural Computation (INC), UC San Diego.

if isfield(fx, 'seedArg')
    got = mexitk(opcode, fx.params, vin, cast([], class(vin)), fx.seedArg);
else
    got = mexitk(opcode, fx.params, vin);
end
end
