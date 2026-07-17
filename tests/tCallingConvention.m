classdef tCallingConvention < matlab.unittest.TestCase
    % Tests for the MATITK calling convention itself, independent of any filter.
    %
    % Every expectation here was checked against the original binary; where
    % mexitk deliberately differs, the test says so and pins the deviation.
    %
    % SPDX-License-Identifier: BSD-3-Clause
    % Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
    % Swartz Center for Computational Neuroscience (SCCN),
    % Institute for Neural Computation (INC), UC San Diego.

    properties
        V
    end

    methods (TestMethodSetup)
        function loadVolume(tc)
            mri = load('mri');
            tc.V = double(squeeze(mri.D));
        end
    end

    methods (Test)

        function opcodeIsCaseInsensitive(tc)
            % The paper uses lowercase ('fomt'), NFT uses uppercase ('FOMT').
            % Confirmed identical on the original.
            [a1, a2] = mexitk('FOMT', [2 50], tc.V);
            [b1, b2] = mexitk('fomt', [2 50], tc.V);
            tc.verifyEqual(b1, a1);
            tc.verifyEqual(b2, a2);
        end

        function acceptsStringObjectAsWellAsChar(tc)
            % Deliberate deviation. The original rejects "FCA" with
            % 'Opcode input field must be of type string.' because MATLAB's
            % string class postdates it. Accepting both is a strict superset, so
            % no call that worked against matitk changes meaning here.
            a = mexitk('FCA', [1 0.0625 3.0], tc.V);
            b = mexitk("FCA", [1 0.0625 3.0], tc.V);
            tc.verifyEqual(b, a);
        end

        function rejectsNonVolumeInput(tc)
            % Matches the original: 'Input volume A must be a 3D image.'
            tc.verifyError(@() mexitk('FCA', [1 0.0625 3.0], tc.V(:, :, 1)), 'mexitk:not3D');
            tc.verifyError(@() mexitk('FCA', [1 0.0625 3.0], [1 2 3]), 'mexitk:not3D');
        end

        function rejectsTooFewParameters(tc)
            tc.verifyError(@() mexitk('FCA', [1 0.0625], tc.V), 'mexitk:params');
            tc.verifyError(@() mexitk('FOMT', [], tc.V), 'mexitk:params');
        end

        function tooManyParametersWarnsButProceeds(tc)
            % The original warns and runs anyway rather than erroring.
            tc.verifyWarning(@() mexitk('FCA', [1 0.0625 3.0 99], tc.V), ...
                'mexitk:tooManyParams');
        end

        function rejectsUnknownOpcode(tc)
            tc.verifyError(@() mexitk('ZZZZ', [1], tc.V), 'mexitk:unknownOpcode');
        end

        function rejectsUnsupportedPixelClass(tc)
            % Supported set is double/single/uint8/int32, as the original.
            tc.verifyError(@() mexitk('FCA', [1 0.0625 3.0], int16(tc.V)), ...
                'mexitk:pixelType');
        end

        function spacingArgumentIsAcceptedAndIgnored(tc)
            % Verified against the original: [1 1 2] and [1 1 1] produce
            % bit-identical output, i.e. spacing is unwired. Honouring it would
            % diverge from every existing caller, so mexitk ignores it too.
            a = mexitk('FCA', [1 0.0625 3.0], tc.V, [], [], [1 1 1]);
            b = mexitk('FCA', [1 0.0625 3.0], tc.V, [], [], [1 1 2]);
            c = mexitk('FCA', [1 0.0625 3.0], tc.V);
            tc.verifyEqual(b, a);
            tc.verifyEqual(c, a);
        end

        function rejectsMalformedSpacing(tc)
            tc.verifyError(@() mexitk('FCA', [1 0.0625 3.0], tc.V, [], [], [1 1]), ...
                'mexitk:spacing');
        end

        function rejectsMalformedSeeds(tc)
            tc.verifyError(@() mexitk('SWS', [0.5 0.5], tc.V, [], [1 2]), 'mexitk:seeds');
            % The original bounds-checks seeds and reports 1-based indexing.
            tc.verifyError(@() mexitk('SWS', [0.5 0.5], tc.V, [], [0 0 0]), 'mexitk:seeds');
        end

        function listingEnumeratesOpcodesWithStatus(tc)
            % mexitk('?') is the discovery path, and it must publish the
            % validation status so a user can tell a bit-exact opcode from a
            % best-effort one without reading the README.
            txt = evalc("mexitk('?')");
            tc.verifySubstring(txt, 'FCA');
            tc.verifySubstring(txt, 'FOMT');
            tc.verifySubstring(txt, 'SWS');
            tc.verifySubstring(txt, 'validated');
            tc.verifySubstring(txt, 'bounded-deviation');
        end

        function noArgumentsReportsUsage(tc)
            tc.verifyError(@() mexitk(), 'mexitk:usage');
        end
    end
end
