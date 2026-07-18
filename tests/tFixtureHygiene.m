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
    %   - A small set of named summary/probe files with their own fixed
    %     variable names (s12's six cross-check summaries, plus s01/s01b/
    %     s06's older non-fixture captures) -- checked against a known
    %     variable-name schema per file, since a `fixture` struct schema
    %     does not apply to them.
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
            % Known non-`fixture` top-level variable names, by filename.
            schemas = containers.Map();
            schemas('edge_cases.mat') = {'edge'};
            schemas('provenance.mat') = {'provenance'};
            schemas('mri_base_volume.mat') = {'V', 'map'};
            schemas('fca_spacing_comparison.mat') = {'spacingCompare', 'o_default', 'o_sp111', 'o_sp112'};
            schemas('sws_seed_equivalence.mat') = {'seedEquivalence'};
            schemas('fomt_output_count_results.mat') = {'Nlist', 'V', 'Vd', 'nBins', 'results'};
            schemas('fomt_semantics_results.mat') = {'Nlist', 'Vd', 'nBins', 'semantics'};
            schemas('s12_fga_fdg_isequal.mat') = {'results'};
            schemas('s12_fdmv_accessor.mat') = {'labSubset', 'binSubset', 'fdmLabOutput', 'fdmvLabOutput', 'fdmBinOutput', 'fdmvBinOutput'};
            schemas('s12_sct_replace_value.mat') = {'replaceValue', 'outOfBandUnique'};
            schemas('s12_sic_seedsplit.mat') = {'eqOrder', 'eqThirdGroup', 's1s2Output'};
            schemas('s12_nargout_probes.mat') = {'probes'};
            schemas('s12_closing_fbd_fbe.mat') = {'intermediate', 'final', 'intermediateHash', 'finalHash', 'binRecipe'};
        end
    end

    methods (Test)
        function fixtureIsHygienic(tc, fixtureFile)
            here = fileparts(mfilename('fullpath'));
            data = load(fullfile(here, 'fixtures', fixtureFile));

            schemas = tFixtureHygiene.namedShapeSchemas();
            if isfield(data, 'fixture')
                tFixtureHygiene.checkFixtureShape(tc, fixtureFile, data.fixture);
            elseif isKey(schemas, fixtureFile)
                expectedVars = schemas(fixtureFile);
                present = fieldnames(data);
                tc.verifyTrue(all(ismember(expectedVars, present)), sprintf( ...
                    '%s: expected variables {%s}, found {%s}', fixtureFile, ...
                    strjoin(expectedVars, ','), strjoin(present, ',')));
            else
                tc.verifyFail(sprintf( ...
                    '%s: unrecognized shape (top-level variables: %s). Add it to namedShapeSchemas.', ...
                    fixtureFile, strjoin(fieldnames(data), ',')));
            end
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
    end
end
