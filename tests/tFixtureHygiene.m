classdef tFixtureHygiene < matlab.unittest.TestCase
    % Hygiene guard for every committed fixture under tests/fixtures/: the
    % deferred check flagged during the Epic 2 Phase 1 capture-harness
    % review (a committed-fixture hygiene test lands alongside the
    % fixtures it guards). Runs once per fixture file, parameterized, so a
    % single bad file fails as itself rather than as an opaque aggregate.
    %
    % Three fixture "shapes" exist in tests/fixtures/, spanning both
    % capture eras:
    %   - A `fixture` struct, single-output (the vast majority): opcode/
    %     params/inputClass/inputSize/inputHash/success/errmsg/consoleText
    %     are universal across every capture era (s02/s04's older captures
    %     and s07-s13/s10b's capture_case-based ones alike); success==true
    %     additionally carries output/outputClass/outputSize/outputHash
    %     (self-consistency checked by recomputing the hash);
    %     success==false carries a non-empty errmsg instead.
    %   - A `fixture` struct, multi-output (s03's FOMT template, N
    %     thresholds -> N label images): the same universal fields, but
    %     success==true carries plural outputs/outputClasses/outputHashes
    %     (matching cell arrays) plus numOutputs instead of a single
    %     output/outputHash pair; each cell's hash is self-consistency
    %     checked individually.
    %   - s12's six cross-check summary files (s12_inference_probes.m,
    %     not locked, so this test owns their contract): each gets a real
    %     per-file type/shape/content check in checkProbeSummaryContent,
    %     including a hash recompute for s12_closing_fbd_fbe's
    %     intermediate/final array+hash pairs -- the same self-consistency
    %     principle applied to ordinary fixture output above.
    %   - s01/s01b/s05/s06's older non-`fixture` captures (locked scripts;
    %     this test does not own their contract) -- checked only for
    %     variable-name presence against a known schema per file.
    %
    % A separate, non-parameterized test (manifestMatchesDirectory) guards
    % the fixture SET itself: tests/fixtures/MANIFEST.txt must list
    % exactly the .mat files present, symmetrically -- a deletion (listed
    % but missing) and a stray addition (present but unlisted) are two
    % independent failures, not one aggregate count check.
    %
    % SPDX-License-Identifier: BSD-3-Clause
    % Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
    % Swartz Center for Computational Neuroscience (SCCN),
    % Institute for Neural Computation (INC), UC San Diego.

    properties (TestParameter)
        fixtureFile = tFixtureHygiene.listFixtureNames();
    end

    methods (TestClassSetup)
        function addLocalMd5ToPath(~)
            here = fileparts(mfilename('fullpath'));
            addpath(fullfile(fileparts(here), 'tools', 'capture_reference'));
        end
    end

    methods (Static)
        function names = listFixtureNames()
            here = fileparts(mfilename('fullpath'));
            d = dir(fullfile(here, 'fixtures', '*.mat'));
            names = {d.name};
        end

        function schemas = namedShapeSchemas()
            % Older, non-epic, non-`fixture` top-level variable names, by
            % filename (s01/s01b/s05/s06's captures, predating
            % capture_case.m). Checked for variable-name presence only:
            % these are locked-script outputs this test does not own the
            % contract for, unlike the s12 probe summaries below.
            schemas = containers.Map();
            schemas('edge_cases.mat') = {'edge'};
            schemas('provenance.mat') = {'provenance'};
            schemas('mri_base_volume.mat') = {'V', 'map'};
            schemas('fca_spacing_comparison.mat') = {'spacingCompare', 'o_default', 'o_sp111', 'o_sp112'};
            schemas('sws_seed_equivalence.mat') = {'seedEquivalence'};
            schemas('fomt_output_count_results.mat') = {'Nlist', 'V', 'Vd', 'nBins', 'results'};
            schemas('fomt_semantics_results.mat') = {'Nlist', 'Vd', 'nBins', 'semantics'};
        end

        function names = probeSummaryNames()
            % s12's cross-check summary files: this test owns their
            % contract (s12_inference_probes.m is not locked), so they get
            % real type/shape/content checks, not just a name-presence
            % check. See checkProbeSummaryContent.
            names = {'s12_fga_fdg_isequal.mat', 's12_fdmv_accessor.mat', ...
                's12_sct_replace_value.mat', 's12_sic_seedsplit.mat', ...
                's12_nargout_probes.mat', 's12_closing_fbd_fbe.mat'};
        end
    end

    methods (Test)
        function fixtureIsHygienic(tc, fixtureFile)
            here = fileparts(mfilename('fullpath'));
            data = load(fullfile(here, 'fixtures', fixtureFile));

            schemas = tFixtureHygiene.namedShapeSchemas();
            if isfield(data, 'fixture')
                tFixtureHygiene.checkFixtureShape(tc, fixtureFile, data.fixture);
            elseif ismember(fixtureFile, tFixtureHygiene.probeSummaryNames())
                tFixtureHygiene.checkProbeSummaryContent(tc, fixtureFile, data);
            elseif isKey(schemas, fixtureFile)
                expectedVars = schemas(fixtureFile);
                present = fieldnames(data);
                tc.verifyTrue(all(ismember(expectedVars, present)), sprintf( ...
                    '%s: expected variables {%s}, found {%s}', fixtureFile, ...
                    strjoin(expectedVars, ','), strjoin(present, ',')));
            else
                tc.verifyFail(sprintf( ...
                    ['%s: unrecognized shape (top-level variables: %s). Add it to ' ...
                     'namedShapeSchemas or probeSummaryNames/checkProbeSummaryContent.'], ...
                    fixtureFile, strjoin(fieldnames(data), ',')));
            end
        end

        function manifestMatchesDirectory(tc)
            % Symmetric guard on the fixture set itself, not any one
            % file's content: MANIFEST.txt (sorted filenames, one per
            % line, generated from the committed set) must list exactly
            % the .mat files present in tests/fixtures/ -- no more, no
            % less. Catches a fixture silently deleted (present in the
            % manifest, missing from the directory) and a fixture added
            % without updating the manifest (present in the directory,
            % missing from the manifest) as two independent failures,
            % not just one aggregate "counts differ" check.
            here = fileparts(mfilename('fullpath'));
            manifestPath = fullfile(here, 'fixtures', 'MANIFEST.txt');
            tc.assertTrue(isfile(manifestPath), 'tests/fixtures/MANIFEST.txt is missing');

            manifestText = fileread(manifestPath);
            manifestNames = strtrim(strsplit(manifestText, {'\n', '\r'}));
            manifestNames = manifestNames(~cellfun(@isempty, manifestNames));

            actualNames = tFixtureHygiene.listFixtureNames();

            missing = setdiff(manifestNames, actualNames);
            stray = setdiff(actualNames, manifestNames);
            tc.verifyEmpty(missing, sprintf( ...
                'Listed in MANIFEST.txt but missing from tests/fixtures/: %s', ...
                strjoin(missing, ', ')));
            tc.verifyEmpty(stray, sprintf( ...
                'Present in tests/fixtures/ but not listed in MANIFEST.txt: %s', ...
                strjoin(stray, ', ')));
        end
    end

    methods (Static, Access = private)
        function checkFixtureShape(tc, name, f)
            universalFields = {'opcode', 'params', 'inputClass', 'inputSize', ...
                'inputHash', 'success', 'errmsg', 'consoleText'};
            missing = universalFields(~isfield(f, universalFields));
            tc.verifyEmpty(missing, sprintf('%s: missing universal fields {%s}', ...
                name, strjoin(missing, ',')));
            if ~isempty(missing)
                return;
            end

            tc.verifyNotEqual(f.errmsg, 'dryrun', sprintf( ...
                '%s: carries a dryrun marker -- never commit a dry-run capture', name));
            tc.verifyClass(f.inputHash, 'char');
            tc.verifyNotEmpty(f.inputHash, sprintf('%s: empty inputHash', name));
            tc.verifyTrue(isnumeric(f.params), sprintf( ...
                '%s: params is %s, not numeric', name, class(f.params)));
            if isfield(f, 'inputRecipe')
                tc.verifyClass(f.inputRecipe, 'char');
                tc.verifyNotEmpty(f.inputRecipe, sprintf('%s: empty inputRecipe', name));
            end
            expectedPrefix = [lower(f.opcode) '_'];
            tc.verifyTrue(startsWith(lower(name), expectedPrefix), sprintf( ...
                '%s: filename does not start with "%s" (opcode %s)', name, expectedPrefix, f.opcode));

            if f.success && isfield(f, 'outputs')
                % Multi-output shape (s03's FOMT template): outputs/
                % outputHashes are matching cell arrays, one entry per
                % nargout return value, instead of a single output/
                % outputHash pair.
                outFields = {'outputs', 'outputClasses', 'outputHashes', 'numOutputs'};
                missingOut = outFields(~isfield(f, outFields));
                tc.verifyEmpty(missingOut, sprintf('%s: success=true (multi-output) missing {%s}', ...
                    name, strjoin(missingOut, ',')));
                if isempty(missingOut)
                    tc.verifyEqual(numel(f.outputs), f.numOutputs, sprintf( ...
                        '%s: numel(outputs)=%d does not match numOutputs=%d', ...
                        name, numel(f.outputs), f.numOutputs));
                    tc.verifyEqual(numel(f.outputHashes), f.numOutputs, sprintf( ...
                        '%s: numel(outputHashes)=%d does not match numOutputs=%d', ...
                        name, numel(f.outputHashes), f.numOutputs));
                    for k = 1:numel(f.outputs)
                        tc.verifyNotEmpty(f.outputs{k}, sprintf( ...
                            '%s: success=true output %d is empty', name, k));
                        % No per-output size field exists on this (locked,
                        % s03) shape, so the shape cross-check compares
                        % against inputSize instead: every FOMT output is a
                        % label image of the same volume, so it must share
                        % the input's spatial size. Catches the same class
                        % of bug the single-output branch's size(output) ==
                        % outputSize check does (flattened md5 is
                        % shape-blind), via the best available reference.
                        tc.verifyEqual(size(f.outputs{k}), f.inputSize, sprintf( ...
                            '%s: size(outputs{%d})=%s does not match inputSize=%s', ...
                            name, k, mat2str(size(f.outputs{k})), mat2str(f.inputSize)));
                        recomputed = local_md5(f.outputs{k});
                        tc.verifyEqual(f.outputHashes{k}, recomputed, sprintf( ...
                            '%s: outputHashes{%d} %s does not match local_md5 recomputed as %s', ...
                            name, k, f.outputHashes{k}, recomputed));
                    end
                end
            elseif f.success
                outFields = {'output', 'outputClass', 'outputSize', 'outputHash'};
                missingOut = outFields(~isfield(f, outFields));
                tc.verifyEmpty(missingOut, sprintf('%s: success=true missing {%s}', ...
                    name, strjoin(missingOut, ',')));
                if isempty(missingOut)
                    tc.verifyNotEmpty(f.output, sprintf('%s: success=true with empty output', name));
                    tc.verifyEqual(size(f.output), f.outputSize, sprintf( ...
                        ['%s: size(output)=%s does not match stored outputSize=%s ' ...
                         '(a reshaped output would still hash-match a flattened md5)'], ...
                        name, mat2str(size(f.output)), mat2str(f.outputSize)));
                    recomputed = local_md5(f.output);
                    tc.verifyEqual(f.outputHash, recomputed, sprintf( ...
                        '%s: outputHash %s does not match local_md5(output) recomputed as %s', ...
                        name, f.outputHash, recomputed));
                end
            else
                tc.verifyClass(f.errmsg, 'char');
                tc.verifyNotEmpty(f.errmsg, sprintf('%s: success=false with empty errmsg', name));
            end
        end

        function checkProbeSummaryContent(tc, name, data)
            % Per-file type/shape/content checks for s12's six cross-check
            % summaries, keyed on filename since each has its own fixed
            % variable set (see s12_inference_probes.m's individual probe
            % functions for what each one computes and why).
            switch name
                case 's12_fga_fdg_isequal.mat'
                    tc.verifyClass(data.results, 'struct');
                    for i = 1:numel(data.results)
                        r = data.results(i);
                        tc.verifyTrue(isnumeric(r.point), sprintf('%s: results(%d).point not numeric', name, i));
                        tc.verifyClass(r.class, 'char');
                        tc.verifyClass(r.isEqual, 'logical');
                    end

                case 's12_fdmv_accessor.mat'
                    tc.verifyClass(data.labSubset, 'logical');
                    tc.verifyClass(data.binSubset, 'logical');
                    outVars = {'fdmLabOutput', 'fdmvLabOutput', 'fdmBinOutput', 'fdmvBinOutput'};
                    for i = 1:numel(outVars)
                        v = data.(outVars{i});
                        tc.verifyTrue(isnumeric(v), sprintf('%s: %s not numeric', name, outVars{i}));
                        tc.verifyNotEmpty(v, sprintf('%s: %s is empty', name, outVars{i}));
                    end

                case 's12_sct_replace_value.mat'
                    tc.verifyTrue(isnumeric(data.replaceValue) && isscalar(data.replaceValue), sprintf( ...
                        '%s: replaceValue is not a numeric scalar', name));
                    tc.verifyTrue(isnumeric(data.outOfBandUnique), sprintf( ...
                        '%s: outOfBandUnique not numeric', name));
                    tc.verifyNotEmpty(data.outOfBandUnique, sprintf('%s: outOfBandUnique is empty', name));

                case 's12_sic_seedsplit.mat'
                    tc.verifyClass(data.eqOrder, 'logical');
                    tc.verifyClass(data.eqThirdGroup, 'logical');
                    tc.verifyTrue(isnumeric(data.s1s2Output), sprintf('%s: s1s2Output not numeric', name));
                    tc.verifyNotEmpty(data.s1s2Output, sprintf('%s: s1s2Output is empty', name));

                case 's12_nargout_probes.mat'
                    tc.verifyClass(data.probes, 'struct');
                    for i = 1:numel(data.probes)
                        p = data.probes(i);
                        tc.verifyClass(p.opcode, 'char');
                        tc.verifyClass(p.errored, 'logical');
                        tc.verifyClass(p.text, 'char');
                        % This exact file was recaptured once already after
                        % being deleted for the errmsg-truncation bug (see
                        % capture_case.m's char-vs-string catch-handler
                        % fix); cheap and permanent to keep checking for
                        % the ellipsis marker here specifically.
                        tc.verifyFalse(contains(p.text, char(8230)), sprintf( ...
                            '%s: probes(%d).text (%s) contains an ellipsis -- truncated message', ...
                            name, i, p.opcode));
                    end

                case 's12_closing_fbd_fbe.mat'
                    tc.verifyTrue(isnumeric(data.intermediate), sprintf('%s: intermediate not numeric', name));
                    tc.verifyNotEmpty(data.intermediate, sprintf('%s: intermediate is empty', name));
                    tc.verifyTrue(isnumeric(data.final), sprintf('%s: final not numeric', name));
                    tc.verifyNotEmpty(data.final, sprintf('%s: final is empty', name));
                    tc.verifyClass(data.binRecipe, 'char');
                    tc.verifyNotEmpty(data.binRecipe, sprintf('%s: empty binRecipe', name));
                    tc.verifyClass(data.intermediateHash, 'char');
                    tc.verifyClass(data.finalHash, 'char');
                    recomputedIntermediate = local_md5(data.intermediate);
                    tc.verifyEqual(data.intermediateHash, recomputedIntermediate, sprintf( ...
                        '%s: intermediateHash %s does not match local_md5(intermediate) recomputed as %s', ...
                        name, data.intermediateHash, recomputedIntermediate));
                    recomputedFinal = local_md5(data.final);
                    tc.verifyEqual(data.finalHash, recomputedFinal, sprintf( ...
                        '%s: finalHash %s does not match local_md5(final) recomputed as %s', ...
                        name, data.finalHash, recomputedFinal));

                otherwise
                    tc.verifyFail(sprintf('%s: no content check defined in checkProbeSummaryContent', name));
            end
        end
    end
end
