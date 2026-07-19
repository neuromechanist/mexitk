% Epic 2 Phase 1: capture Phase-4-opcode (gradients/diffusion/features)
% fixtures mirroring tests/tPhase4GradientsSmoke.m's validParams and
% probe points. This is the heaviest script (largest continuous-output
% count): FBL [5 5] is captured once, known slow (~5-6 s/call on mexitk;
% runtime against the original is unknown, logged via diary). FGAD
% [5 10 0.0625] is the deliberately swapped-param instability probe: the
% original may emit large or non-finite values, which is captured as-is
% (ClampExport is a mexitk concern, not the original's).
cfg = refcap_config();
addpath(cfg.matitkDir);
diary(fullfile(cfg.logsDir, 's10_gradients_capture.log'));
diary on;
format compact;

load mri;
V = squeeze(D);
Vd = double(V);
Vs = single(V);
Vi = int32(V);

classNames = {'double', 'single', 'uint8', 'int32'};
classVals = {Vd, Vs, V, Vi};

bin33RecipeDouble = '255*double(V>33)';
bin33Double = eval(bin33RecipeDouble); %#ok<EVLCS>
bin33RecipeSingle = 'single(255*double(V>33))';
bin33Single = eval(bin33RecipeSingle); %#ok<EVLCS>
bin33RecipeUint8 = 'uint8(255*(V>33))';
bin33Uint8 = eval(bin33RecipeUint8); %#ok<EVLCS>
bin33RecipeInt32 = 'int32(255*double(V>33))';
bin33Int32 = eval(bin33RecipeInt32); %#ok<EVLCS>
bin33Vals = {bin33Double, bin33Single, bin33Uint8, bin33Int32};
bin33Recipes = {bin33RecipeDouble, bin33RecipeSingle, bin33RecipeUint8, bin33RecipeInt32};

% FAAB
% double+single only here, for BOTH raw and bin33 inputs. Measured
% against the real binary across two campaign runs: FAAB on uint8 input
% crashes the original with a floating point exception regardless of
% whether the input is raw (run 1) or already binarized at bin33 (run
% 2) -- the crash is about the pixel type, not the pixel value
% distribution. int32 is presumed to hit the same crash by extension
% (not yet directly confirmed) and is treated the same way. Every
% integral-class FAAB case (raw and bin33, uint8 and int32) is isolated
% instead in s10b_faab_crash_probe.m.
capture_classes(cfg, 'FAAB', '0p01_50_2_raw', [0.01 50 2], classNames, classVals, [1 2]);
capture_classes_recipe(cfg, 'FAAB', '0p01_50_2_bin33', [0.01 50 2], classNames, bin33Vals, bin33Recipes, [1 2]);
capture_case(cfg, 'FAAB', '0p01_50_1_bin33_double', [0.01 50 1], bin33Double, struct('inputRecipe', bin33RecipeDouble));
capture_case(cfg, 'FAAB', '0p01_50_50_bin33_double', [0.01 50 50], bin33Double, struct('inputRecipe', bin33RecipeDouble));

% FBL
capture_classes(cfg, 'FBL', '2_10', [2 10], classNames, classVals, 1:4);
capture_case(cfg, 'FBL', '10_2_double', [10 2], Vd);
capture_case(cfg, 'FBL', '5_5_double', [5 5], Vd);  % SLOW (~5-6 s/call); capture once

% FCF
capture_classes(cfg, 'FCF', '10_0p0625', [10 0.0625], classNames, classVals, 1:4);
capture_case(cfg, 'FCF', '5_0p0625_double', [5 0.0625], Vd);
capture_case(cfg, 'FCF', '20_0p0625_double', [20 0.0625], Vd);

% FGAD
capture_classes(cfg, 'FGAD', '5_0p0625_3', [5 0.0625 3], classNames, classVals, 1:4);
capture_case(cfg, 'FGAD', '2_0p0625_40_double', [2 0.0625 40], Vd);
capture_case(cfg, 'FGAD', '40_0p0625_2_double', [40 0.0625 2], Vd);
capture_case(cfg, 'FGAD', '5_0p0625_10_double', [5 0.0625 10], Vd);
capture_case(cfg, 'FGAD', '5_10_0p0625_double', [5 10 0.0625], Vd);  % swapped-param instability probe

% FGM
capture_classes(cfg, 'FGM', 'raw', [], classNames, classVals, 1:4);

% FGMRG, FLS, FVMI: sigma<=0 is deliberately NOT captured here. mexitk
% adds no custom guard for it on these three (RecursiveGaussian-family)
% opcodes; it throws ITK's own catchable exception, which was present in
% ITK 2.4 (the original's own ITK version) as well as today, so there is
% no undefined-behaviour or divergent-guard question to resolve by
% capturing it. Skipped here for crash/runtime budget reasons, not an
% oversight.

% FGMRG
capture_classes(cfg, 'FGMRG', '2', 2, classNames, classVals, 1:4);
capture_case(cfg, 'FGMRG', '1_double', 1, Vd);
capture_case(cfg, 'FGMRG', '4_double', 4, Vd);

% FLS
capture_classes(cfg, 'FLS', '2', 2, classNames, classVals, 1:4);
capture_case(cfg, 'FLS', '1_double', 1, Vd);
capture_case(cfg, 'FLS', '4_double', 4, Vd);

% FVMI
capture_classes(cfg, 'FVMI', '1_0p5_2', [1 0.5 2], classNames, classVals, 1:4);
capture_case(cfg, 'FVMI', '3_0p5_2_double', [3 0.5 2], Vd);
capture_case(cfg, 'FVMI', '1_2_0p5_double', [1 2 0.5], Vd);

local_mark_complete(cfg, 's10');
diary off;

function capture_classes_recipe(cfg, opcode, tagPrefix, params, classNames, classVals, classRecipes, useIdx)
% Same as capture_classes, but each class's input carries its own
% inputRecipe (derived-input provenance; see README).
for k = useIdx
    tag = sprintf('%s_%s', tagPrefix, classNames{k});
    capture_case(cfg, opcode, tag, params, classVals{k}, struct('inputRecipe', classRecipes{k}));
end
end
