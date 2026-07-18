# mexitk plan

Status as of 2026-07-16. Version 0.1.0.

## Done

- Reference capture from the original `matitk.mexa64` (`MATITK v.2.4.04 Aug 18 2006`,
  md5 `c7d1432080e9edc6795a38717f5ab628`) on Linux x86_64.
  36 fixtures over FCA/FOMT/SWS plus edge cases, committed to `tests/fixtures/`.
  Harness preserved in `tools/capture_reference/`.
- All 40 opcodes mapped to modern ITK 5.x classes (`docs/itk_opcode_mapping.md`).
- Opcode registry architecture; explicit registration; pixel-type dispatch on
  double/single/uint8/int32; zero-copy `mxArray` to `itk::Image` import.
- FCA, FOMT, SWS implemented. 34/34 tests pass on macOS arm64.
- Agreement with the original measured and documented (`docs/COMPATIBILITY.md`).
- README, BUILDING.md, LICENSE (BSD-3-Clause), CITATION.cff, CI workflow.
- **Phase 1: 9 smoke-tested filter opcodes** (FMEDIAN, FMEAN, FBT, FDG, FBB,
  FSN, FF, FD, FGA) added on top of FCA/FOMT/SWS, bringing the total to 12 of
  40. All `Category::kFilter`, `Status::kSmokeTested`, no reference data.
  FD promotes `uint8` to `float` (ITK's `DerivativeImageFilter` requires a
  signed output pixel type); the other 8 run natively at all four supported
  pixel types. FGA is a deliberate duplicate of FDG (identical registry
  parameter signature; see `docs/COMPATIBILITY.md`).
- **Phase 1 hardening**: `CastParam` (`src/mexitk_common.h`) guards every
  narrowing param-to-pixel-type cast against undefined behaviour
  (`mexitk:paramRange`); `FDG`/`FGA` reject non-positive `gaussianVariance`;
  `FSN` rejects `alpha == 0` (both were silent-corruption paths, not
  crashes). Found and fixed along the way: `mexErrMsgIdAndTxt` calls made
  from inside `Opcode::Execute` were being caught by `mexFunction`'s own
  outer `catch (const std::exception&)` and re-wrapped as the generic
  `mexitk:exception`, discarding the intended specific identifier — this
  silently affected FOMT's pre-existing `numberOfThresholds`/`numberOfBins`
  guards too, just never exercised by a test before now. Fixed with a small
  `OpcodeError` type (`src/mexitk_common.h`) that carries its id through that
  catch; see `docs/COMPATIBILITY.md` deviations 5-7.
  `tests/tPhase1FilterSmoke.m` grew from 9 to 28 test methods (stronger
  per-opcode invariants, dtype coverage on all 4 supported classes, and the
  new error paths, including `CastParam`'s float-narrowing guard: a finite
  value beyond `float`'s range is UB to cast and now rejected, while `Inf`/
  `NaN` still pass through since both are exactly representable in `float`).
  81/81 tests pass on macOS arm64 locally against Homebrew ITK, no
  regression in the existing FCA/FOMT/SWS reference suites.
- **Phase 2: 5 more smoke-tested opcodes** (FBD, FBE, FDM, FDMV, FVBIH) added
  on top of the 12 from Phase 1, bringing the total to 17 of 40. All
  `Category::kFilter`, `Status::kSmokeTested`. All five run natively at all
  four supported input pixel types; none needs a promote-and-cast-back
  pattern for their *input*, though FDM's distance output does compute in
  `float` internally (see the hardening bullet below). Modules
  `ITKBinaryMathematicalMorphology`, `ITKDistanceMap` and `ITKLabelVoting`
  added to both `CMakeLists.txt` and `tools/build_itk.sh` in the same commit
  as the sources, learned from a Phase 1 CI failure where the superbuild
  lagged the component list by a commit.
  `FBD` (`BinaryDilateImageFilter`) copies non-foreground input through
  unchanged; `FBE` (`BinaryErodeImageFilter`) writes
  `NumericTraits<PixelType>::NonpositiveMin()` only at pixels that were
  foreground and got eroded away, leaving untouched background at its input
  value. These are two different behaviors, not one shared rule (an earlier
  version of this note said both filters wrote the sentinel to all
  non-foreground output; that was wrong and was corrected after a reviewer
  measured the actual output). All morphology assertions still compare via
  `== 255`, never `== 0`, since either filter can leave an unmodified literal
  0 in the output; see `docs/COMPATIBILITY.md`.
  `FDMV`'s "V = Voronoi, not Vector" accessor reading is provisional (Medium
  confidence, secondary-sourced), carried in `StatusNote()`, README and
  COMPATIBILITY (the COMPATIBILITY.md copy is a literal blockquote of the
  `StatusNote()` string so the two cannot drift apart silently).
  `tests/tPhase2MorphologySmoke.m` (22 test methods, since grown further —
  see the hardening bullet) asserts dilation extensivity, erosion
  anti-extensivity, closing composition, distance-zero-on-object, Voronoi
  label containment, and a constructed hole-fill on real `mri` data; every
  non-guaranteed assertion was empirically verified against a real build before being
  committed (one planning-stage arithmetic slip in a closing-extensivity
  check was caught and corrected during verification, not shipped). 103/103
  tests pass on macOS arm64 locally against Homebrew ITK, no regression in
  any existing suite. CI subsequently confirmed 103/103 on a runner with no
  ITK installed, both platforms.
- **Phase 2 hardening**: `FDM`'s distance output was undefined behaviour on
  integral input (deterministically reachable: an all-zero `uint8` volume
  computes a distance of about 443 everywhere, past `uint8`'s 255 max).
  Fixed by computing the distance channel in `float` and exporting through
  `itk::ClampImageFilter` (saturate) instead of `itk::CastImageFilter`
  (plain narrowing cast); the same saturation swap was applied to FCA's and
  FD's existing promoted-path cast-backs for the same reason. New deviation
  row (#8) in `docs/COMPATIBILITY.md`. Gate: the FCA/FOMT/SWS fixture suites
  and all Phase 1 tests stayed green through the swap, proving in-range
  behaviour didn't move; verified directly too (all-zero `uint8` FDM now
  saturates to 255 instead of UB; real binarized-volume FDM output,
  in-range, is bit-identical before/after by construction of the clamp).
  Two doc corrections from a reviewer who measured actual FBD/FBE output
  rather than trusting the original claim: `FBD` never writes a background
  sentinel at all (untouched background passes through as the original
  input value); `FBE` writes `NonpositiveMin` only at pixels that were
  foreground and got eroded away, not at all non-foreground output as
  originally claimed. Corrected in `docs/COMPATIBILITY.md`, README, the
  test file's comments, and here. `FDMV`'s COMPATIBILITY.md paragraph is now
  a literal blockquote of `FdmvOpcode::StatusNote()`'s exact string instead
  of a paraphrase, so "mirrored verbatim" is actually true.
  `tests/tPhase2MorphologySmoke.m` grew from 22 to 27 test methods: a
  distinct-non-baseline FVBIH params test (catches ignored/hardcoded
  setters), an FBD/FBE value=7 wiring test (catches a hardcoded-255 bug),
  cross-type (double/uint8) coverage for the Voronoi-containment test, an
  exact distance==1 spot check for every 6-adjacent background voxel
  (26954 voxels, not just one), the int32 FBE sentinel-structure pin, and
  an all-zero-volume FDM test. One assumption in the fix-batch brief was
  checked empirically and found false, not shipped as written: an all-zero
  **double** FDM input does NOT produce a uniform distance field (unlike
  the saturated `uint8` case, which only LOOKS uniform because the entire
  non-uniform float range clips to 255) — the double values range from
  about 294 to 443 across this volume's geometry, some deterministic
  gradient from ITK's own handling of a fully empty input that was not
  investigated further. Only the property that does hold (strictly
  positive everywhere) is asserted. 108/108 tests pass on macOS arm64
  locally against Homebrew ITK, no regression in any existing suite.
- **Phase 3: 5 region-growing + single-Otsu opcodes** (SCT, SCC, SIC, SNC,
  SOT) added on top of the 17 from Phase 1/2, bringing the total to 22 of
  40. All `Category::kSegmentation`, `Status::kSmokeTested`, native pixel
  dispatch at all four supported types. New `SeedPointsToIndices` helper
  (`src/mexitk_common.h`) converts the existing 1-based seed(s)Array into
  ITK indices with no axis transpose, the same convention `ImportVolume`
  already uses; out-of-bounds seeds raise `mexitk:seeds`. `ITKRegionGrowing`
  added to both `CMakeLists.txt` and `tools/build_itk.sh` in the sources
  commit (the Phase 2 lesson held: no CI lag this time). Three inferences,
  each unconfirmable against MATITK source and flagged as such: `SCT`
  hardcodes `ReplaceValue=255` (registry exposes none; ITK's own default is
  1; inferred from the 2.4 example); `SIC` splits the one seedsArray into
  two groups (first point, second point) and bounds-checks only those two
  consumed points, not ignored extras (**lead override** of this plan's own
  default — the original never read past the second point, so validating an
  ignored out-of-bounds point would accept strictly less than the original
  did); `SOT` leaves inside/outside at ITK's defaults (inside = pixel-type
  max), so double/single output is `{0,realmax}`, not `{0,255}`.
  Found and fixed a real MATLAB-crashing bug while verifying, not
  anticipated by the plan: `SOT` with 0 or 1 histogram bins crashes the
  whole MATLAB process (a bus error / SIGSEGV inside ITK's Otsu histogram
  calculator, not a catchable exception) — confirmed directly, twice
  independently. Guarded with `mexitk:SOT:numberOfHistogram`
  (`numberOfHistogram >= 2` required), same severity class as the SWS
  overthresholding deviation; new deviation row 9 in
  `docs/COMPATIBILITY.md`. This also changed one planned error-path test:
  negative bins now hit the new guard's identifier instead of the
  originally-expected `mexitk:paramRange`, since the guard checks the raw
  parameter before `CastParam` runs.
  The SOT-vs-FOMT single-threshold cross-check was measured, not assumed:
  agreement is 0.997542769821 (441281/442368 voxels), not exactly 1, so the
  test asserts the measured bound rather than equality; every disagreement
  is at intensity 33, consistent with the two Otsu calculators landing one
  bin edge apart.
  The seed used for the region-growing tests is deliberately not the
  volume's global-max voxel: that voxel sits in a 19638-voxel saturated
  plateau at the image edge, and `SCC`'s confidence interval from it
  explodes to fill 100% of the volume even at the registry's default
  multiplier — a degenerate case. `[70 50 14]` (low local variance) was
  used instead, chosen and verified empirically.
  `tests/tPhase3RegionGrowingSmoke.m` (39 test methods) pins the seed
  convention against axis transposition, a disconnected-same-band-voxel
  connectivity check, threshold/multiplier/radius monotonicity, SIC
  isolation (a mid-band second seed was tried first and empirically failed
  to isolate; a background seed was used instead), and the SOT/FOMT
  cross-check. 147/147 tests pass on macOS arm64 locally against Homebrew
  ITK, no regression in any existing suite.

## Open decisions for the owner

1. **Repo visibility, and the MATLAB CI consequence.**
   `matlab-actions` licenses MATLAB for free only on **public** repos,
   and that licensing lives inside `run-command`/`run-tests`, not `setup-matlab`.
   A private repo needs a MathWorks Batch Licensing Pilot token in `MLM_LICENSE_TOKEN`
   (an application, not instant).
   Until then CI builds but skips tests on private, with a loud warning.
   Going public turns MATLAB CI on for free.
2. **Is FCA's deviation acceptable for NFT's science?**
   FCA is not bit-identical (RMS 2.6e-3 at 1 iteration, compounding with iterations;
   see COMPATIBILITY.md). It feeds Otsu thresholding in NFT's segmentation,
   so the downstream masks can shift slightly.
   The alternative today is that segmentation does not run at all on Apple Silicon.
3. **How broad should the opcode surface get?** 22 of 40 are now implemented;
   only 3 (FCA, FOMT, SWS) have reference data, and reference capture requires
   the Intel-Linux binary. The 19 Phase 1/2/3 opcodes ship smoke-tested only.

## Next

### Near term

- **Linux x86_64 (`glnxa64`): the build WORKS; only runtime loading fails.**
  First CI run on `ubuntu-latest` compiled ITK 5.4.6 from source and built
  `mexitk.mexa64` successfully, so the toolchain and the code are fine on Linux.
  The test step then failed at MEX load:
  `Invalid MEX-file 'mexitk.mexa64': libitkNetlibSlatec-5.4.so.1: cannot open shared
  object file: No such file or directory`.
  CI builds ITK **shared**, and MATLAB does not have ITK's `.so` directory on its
  runtime loader path.
  Two ways out:
  1. Export `LD_LIBRARY_PATH` for the test step. One line, but it papers over the
     real issue and leaves the artifact non-redistributable.
  2. Build ITK with `BUILD_SHARED_LIBS=OFF`. This is already the documented shipping
     recommendation, makes the MEX self-contained, and fixes CI as a side effect.
     Prefer this. Expect to work through symbol-visibility issues when statically
     linking ITK into a MEX that must export only `mexFunction`.
  Note macOS CI passes only because Homebrew's ITK dylibs sit at an absolute path
  that happens to exist on the runner. It is the same fragility, merely masked, and
  option 2 fixes both platforms.
  Ubuntu's `libinsighttoolkit5-dev` is 5.3.0, below our 5.4 floor, so building from
  source is required regardless.
- **Static, module-pruned ITK superbuild** pinned to v5.4.6
  (`BUILD_SHARED_LIBS=OFF`, `ITK_BUILD_DEFAULT_MODULES=OFF`).
  Required for a redistributable MEX: a Homebrew-linked MEX has absolute
  `/opt/homebrew/opt/itk/lib/*.dylib` paths and only works on the build machine.
- **Wire NFT to mexitk** and run its segmentation end to end on Apple Silicon,
  against `../NFT_test` real data. This is the actual acceptance test.
- Zenodo DOI on first release; the placeholder is marked in CITATION.cff.

### Investigations worth doing

- **Isolate the FCA divergence.** It is present after a single iteration, so it is not
  accumulated rounding. The conductance term derives from a global average gradient
  magnitude recomputed each iteration, so a small change there perturbs everything.
  Candidates: `m_MIN_NORM` (1.0e-10 in 5.4) and post-2.4 `m_ScaleCoefficients`.
  Recorded as open, not solved.
- **Capture FCA/SWS reference for `uint8`/`int32`.** No fixtures exist, so integral input
  promotes to float on a guess. Cheap to close: one more capture run.

### Broadening the opcode surface

18 opcodes remain unimplemented; parameters are known exactly
(`docs/matitk_opcode_registry.txt`) and ITK classes are mapped.
Phase 1 (FMEDIAN, FMEAN, FBT, FDG, FBB, FSN, FF, FD, FGA), Phase 2 (FBD,
FBE, FDM, FDMV, FVBIH) and Phase 3 (SCT, SCC, SIC, SNC, SOT) are done.
Each ships with an honest status; no reference data means `smoke-tested` at best.

Known problem cases:
- **SCSS** maps to `itk::bio::CellularAggregate` (opt-in `ITKBioCell` remote module,
  mesh output, global static state). Recommend dropping rather than porting.
- **FGMS** could not be pinned to an ITK class; needs verification against the binary.
- **FFFT** VNL FFT backend was removed; rerouted via pocketfft. Output semantics unconfirmed.
- **RD** `SetStandardDeviations` is inert unless `SmoothDisplacementFieldOn()` is also called.
