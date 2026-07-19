% Epic 2 Phase 1: capture Phase-2-opcode (morphology/distance) fixtures
% mirroring tests/tPhase2MorphologySmoke.m's validParams and derived
% inputs. Derived inputs are built by eval-ing the exact recipe string
% recorded in each fixture's inputRecipe field (single source of truth;
% see README "Derived-input recipe convention"). The FBD-then-FBE closing
% composition is deliberately NOT captured here: it is a two-call
% cross-check, not a per-opcode fixture, so it lives in
% s12_inference_probes.m instead.
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's08_morphology_capture.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vd = double(V);
Vs = single(V);
Vi = int32(V);

classNames = {'double', 'single', 'uint8', 'int32'};
classVals = {Vd, Vs, V, Vi};

binRecipeDouble = 'double(V>30)*255';
binDouble = eval(binRecipeDouble); %#ok<EVLCS>
binRecipeUint8 = 'uint8(double(V>30)*255)';
binUint8 = eval(binRecipeUint8); %#ok<EVLCS>
binRecipeInt32 = 'int32(double(V>30)*255)';
binInt32 = eval(binRecipeInt32); %#ok<EVLCS>
bin7RecipeDouble = 'double(V>30)*7';
bin7Double = eval(bin7RecipeDouble); %#ok<EVLCS>

labRecipeDouble = 'double(V>30)+double(V>60)';
labDouble = eval(labRecipeDouble); %#ok<EVLCS>
labRecipeUint8 = 'uint8(double(V>30)+double(V>60))';
labUint8 = eval(labRecipeUint8); %#ok<EVLCS>

% NOTE: MATLAB's eval() cannot capture a return value from a string that
% contains an internal assignment statement (confirmed general behaviour:
% even y = eval('a=1; a') errors "Incorrect use of '=' operator", not
% something specific to this recipe). The two hole recipes below are
% multi-statement with internal assignments, unlike the single-expression
% recipes above, so they are run as a bare statement (eval([recipe ';']),
% trailing ';' appended only to suppress console echo of the whole
% volume, not altering the recipe's semantics) and their result is read
% back from the recipe's own named result variable, b. A consumer
% re-evaluating fixture.inputRecipe (this epic's Phase 3 -- reference
% tests, not the opcode epic's Phase 3 -- mexitkFixture extension)
% will need the same two-step pattern for these two recipes; a naive
% `vin = eval(fixture.inputRecipe)` fails identically. See README.
holeRecipe = ['b=double(V>30)*255; c=convn(double(b==255),ones(3,3,3),''same''); ' ...
              'h=find(c(:)==27 & b(:)==255); b(h(1))=0; b'];
eval([holeRecipe ';']);
holeDouble = b;
hole50Recipe = ['b=double(V>30)*255; c=convn(double(b==255),ones(3,3,3),''same''); ' ...
                'h=find(c(:)==27 & b(:)==255); hi=h(1:50:end); b(hi)=0; b'];
eval([hole50Recipe ';']);
hole50Double = b;

zeroRecipeUint8 = 'zeros(size(V),''uint8'')';
zeroUint8 = eval(zeroRecipeUint8); %#ok<EVLCS>
zeroRecipeDouble = 'double(zeros(size(V)))';
zeroDouble = eval(zeroRecipeDouble); %#ok<EVLCS>

% FBD
capture_classes(cfg, 'FBD', '1_255', [1 255], classNames, classVals, 1:4);
capture_case(cfg, 'FBD', '1_255_bin_double', [1 255], binDouble, struct('inputRecipe', binRecipeDouble));
capture_case(cfg, 'FBD', '1_7_bin7_double', [1 7], bin7Double, struct('inputRecipe', bin7RecipeDouble));
% Boundary: value=300 is out of uint8 range but valid on double (mexitk's
% guard is per-target-type, not a blanket cap). Mirrors
% fbdRejectsOutOfRangeValueOnIntegralType/fbdAcceptsOutOfRangeValueOnDouble.
capture_classes(cfg, 'FBD', '1_300', [1 300], classNames, classVals, [1 3]);

% FBE
capture_classes(cfg, 'FBE', '1_255', [1 255], classNames, classVals, 1:4);
capture_case(cfg, 'FBE', '1_255_bin_double', [1 255], binDouble, struct('inputRecipe', binRecipeDouble));
capture_case(cfg, 'FBE', '1_7_bin7_double', [1 7], bin7Double, struct('inputRecipe', bin7RecipeDouble));
capture_case(cfg, 'FBE', '1_255_bin_int32', [1 255], binInt32, struct('inputRecipe', binRecipeInt32));

% FVBIH
capture_classes(cfg, 'FVBIH', '1_1_1_0_255_1_1', [1 1 1 0 255 1 1], classNames, classVals, 1:4);
% Boundary: foreground=300 is out of uint8 range but valid on double.
% Mirrors fvbihRejectsOutOfRangeForegroundOnIntegralType/
% fvbihAcceptsOutOfRangeForegroundOnDouble.
capture_classes(cfg, 'FVBIH', '1_1_1_0_300_1_1', [1 1 1 0 300 1 1], classNames, classVals, [1 3]);
capture_case(cfg, 'FVBIH', 'baseline_hole_double', [1 1 1 0 255 1 1], holeDouble, struct('inputRecipe', holeRecipe));
capture_case(cfg, 'FVBIH', 'distinct_hole_double', [2 1 1 0 255 3 2], holeDouble, struct('inputRecipe', holeRecipe));
capture_case(cfg, 'FVBIH', 'baseline_hole50_double', [1 1 1 0 255 1 1], hole50Double, struct('inputRecipe', hole50Recipe));
capture_case(cfg, 'FVBIH', 'distinct_hole50_double', [2 1 1 0 255 3 2], hole50Double, struct('inputRecipe', hole50Recipe));

% FDM
capture_classes(cfg, 'FDM', 'raw', [], classNames, classVals, 1:4);
capture_case(cfg, 'FDM', 'bin_double', [], binDouble, struct('inputRecipe', binRecipeDouble));
capture_case(cfg, 'FDM', 'bin_uint8', [], binUint8, struct('inputRecipe', binRecipeUint8));
capture_case(cfg, 'FDM', 'lab_double', [], labDouble, struct('inputRecipe', labRecipeDouble));
capture_case(cfg, 'FDM', 'lab_uint8', [], labUint8, struct('inputRecipe', labRecipeUint8));
capture_case(cfg, 'FDM', 'zero_uint8', [], zeroUint8, struct('inputRecipe', zeroRecipeUint8));
capture_case(cfg, 'FDM', 'zero_double', [], zeroDouble, struct('inputRecipe', zeroRecipeDouble));

% FDMV
capture_classes(cfg, 'FDMV', 'raw', [], classNames, classVals, 1:4);
capture_case(cfg, 'FDMV', 'bin_double', [], binDouble, struct('inputRecipe', binRecipeDouble));
capture_case(cfg, 'FDMV', 'bin_uint8', [], binUint8, struct('inputRecipe', binRecipeUint8));
capture_case(cfg, 'FDMV', 'lab_double', [], labDouble, struct('inputRecipe', labRecipeDouble));
capture_case(cfg, 'FDMV', 'lab_uint8', [], labUint8, struct('inputRecipe', labRecipeUint8));

local_mark_complete(cfg, 's08');
diary off;
