# mexitk plan

Status as of 2026-07-18. Version 0.3.0.

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
- **Phase 3 hardening**: `SeedPointsToIndices` had the same class of UB as
  the pre-`CastParam` narrowing casts, found by two reviewers converging
  independently, one with a compiled repro. Central seed validation
  (`s < 1.0` in `mexFunction`) let `NaN`/`+Inf` through (IEEE unordered
  comparisons are false against `<`), which then hit a raw
  `static_cast<itk::IndexValueType>`; a huge finite coordinate overflowed
  that same cast. Both are UB, and the overflow case was platform-dependent
  in a way that had stayed invisible on one architecture: ARM64's
  saturating convert masked it (the garbage index still failed the old
  bounds check), but x86 wrapped to `INT64_MIN`, where the following `-1`
  base shift was a second, independent signed-overflow UB. Fixed by moving
  all validation into the `double` domain, before any cast: a coordinate is
  truncated, then checked finite and in `[1, size(axis)]`, and only then
  cast — one identifier (`mexitk:seeds`) for every seed problem, not split
  by finiteness. New deviation row 10 in `docs/COMPATIBILITY.md`.
  Companion fix: `SOT`'s bins guard changed from `(x < 2.0)` to
  `!(x >= 2.0)` so `NaN` bins are caught under `mexitk:SOT:numberOfHistogram`
  instead of falling through to the generic `mexitk:paramRange`.
  `tests/tPhase3RegionGrowingSmoke.m` grew from 39 to 44 test methods:
  NaN/Inf/huge-coordinate and NaN-bins error paths for the two fixes above,
  a seed pinned at the exact dim-3 maximum (z=27) for SCT/SNC/SCC (an
  off-by-one boundary check, not just an interior seed), fractional-seed
  truncation, and an SCC multiplier/iterations swap-order check (measured:
  correct wiring nnz=3, the swapped-equivalent nnz=150674). Every number
  independently re-verified against a real build before commit, matching
  the review pass's own measurements. 156/156 tests pass on macOS arm64
  locally against Homebrew ITK, no regression in any existing suite.
- **Phase 4: 8 gradient/feature filter opcodes** (FAAB, FBL, FCF, FGAD, FGM,
  FGMRG, FLS, FVMI) added on top of the 22 from Phase 1/2/3, bringing the
  total to 30 of 40 -- the last planned phase of this epic. All
  `Category::kFilter`, `Status::kSmokeTested`. The promotion split was a
  hard-vs-documented-requirement question, verified per opcode against the
  installed headers: `FGM`/`FBL` have no float-related concept check and no
  float wording in their docs, so they stay native at all four pixel
  types; `FCA`/`FGAD`/`FCF`/`FAAB` are documented-only ("expects real-valued
  types" / "must be a real number type" / "should be a real valued scalar
  type"); `FGMRG`/`FLS`/`FVMI` have no concept check either but hardwire
  `InternalRealType = float` internally and end in a raw narrowing cast.
  All six promoted opcodes use the FCA-precedent promote-and-`ClampImageFilter`
  pattern (deviation 8, later replaced by `ClampExport`; see "Phase 4
  hardening" below); none is concept-*enforced* to promote (`FD`, from
  Phase 1, remains the only concept-forced promotion in the whole project).
  `FVMI`'s two-filter pipeline (`HessianRecursiveGaussianImageFilter` feeding
  `Hessian3DToVesselnessMeasureImageFilter`) needed one template-instantiation
  question resolved: verified from headers that the Hessian filter's
  *default* second template argument already produces the double-tensor
  image the vesselness stage hardcodes as its input, for both `float`- and
  `double`-real images, via `NumericTraits<T>::RealType == double` for both;
  no explicit tensor instantiation was needed. `ITKImageGradient`,
  `ITKCurvatureFlow` and `ITKAntiAlias` added to both `CMakeLists.txt` and
  `tools/build_itk.sh` in the sources commit (the Phase 2 lesson held again).
  `FAAB`'s signed level-set output was measured, not assumed: on `uint8`,
  72.8% of output voxels saturate to exactly 0 (the entire outside-negative
  half of the level set), and the sign pattern on `double` matches the
  header's inside-positive/outside-negative claim on 98.5%/97.2% of
  voxels respectively, not 100% (the remainder sit near the zero-crossing
  surface). `FLS`'s `uint8` clamp-back was checked against the exact
  clamp-and-truncate arithmetic and matched perfectly (0 mismatches across
  442368 voxels) -- the plan's own flagged concern about float
  rounding-at-bin-edges making that assertion flaky did not materialize on
  this data, so the strong version shipped. `FGM`/`FGMRG` compute the same
  conceptual quantity via genuinely different algorithms (central
  differences vs. recursive Gaussian derivative) and are documented as such,
  not silently treated as interchangeable. `FBL`'s test parameters
  deliberately use `[2 10]`, not the registry hint `[5 5]`: measured at 5.6
  seconds per call, `[5 5]` was too slow to use across 4 pixel types and
  several tests, while `[2 10]` (0.25s/call) still exercises the filter
  meaningfully; hint values are not sacred for tests. `sigma <= 0` on the
  three recursive-Gaussian-family opcodes (`FGMRG`, `FLS`, `FVMI`) throws
  ITK's own catchable exception (`mexitk:itkException`), verified directly
  on all three rather than assumed from the shared base class; no custom
  guard was added, matching the minimal-deviation policy.
  `tests/tPhase4GradientsSmoke.m` (28 test methods) covers the 4-pixel-type
  run for all 8 opcodes, algorithm-distinctness and monotonicity properties,
  the exact-arithmetic and measured-sign-pattern assertions above, and the
  paramRange/itkException error paths. 196/196 tests pass on macOS arm64
  locally against Homebrew ITK, no regression in any existing suite.
- **Phase 4 hardening**: the largest fix batch of the epic, touching Phase
  1-3 code too under the no-debt policy (fixture suites are the proof).
  `itk::ClampImageFilter`'s cast-back falls through to a raw `static_cast`
  for `NaN` (unordered comparisons skip both bounds checks), undefined
  behaviour reachable via an unstable diffusion `timeStep` or `FVMI`'s
  alpha `0/0` corner. Replaced project-wide with one audited helper,
  `ClampExport<PixelT, RealT>` (`src/mexitk_common.h`): a manual buffer
  loop matching `ClampImageFilter`'s exact in-range/out-of-range bounds
  logic, plus an explicit `isnan` check writing `PixelT{}` (0) instead of
  falling through. Used by all nine promoted opcodes across Phases 1-3
  (`FCA`, `FD`, `FDM`) and 4 (`FAAB`, `FCF`, `FGAD`, `FGMRG`, `FLS`,
  `FVMI`). `FGM`'s `int32` path was reworked to match: computation stays
  native (verified from `itkGradientMagnitudeImageFilter.hxx` that
  accumulation is `NumericTraits<T>::RealType`, `double` for both `uint8`
  and `int32`), but export now goes through `GradientMagnitudeImageFilter
  <InImage, Image3<double>>` + `ClampExport<int32_t, double>` since
  `int32`'s native narrowing cast could overflow (`uint8`'s could not:
  worst case ~220.9 < 255, measured 76.21 on the reference volume, so its
  path is bit-identical before and after). Independently bit-compared
  `FGM`'s `uint8`/`int32` outputs against a hand-derived floor-truncation
  reconstruction: 0 mismatches across all 442368 voxels for either type.
  `FBL` gained `domainSigma`/`rangeSigma` guards after tracing
  `itkBilateralImageFilter.hxx` line by line: negative `domainSigma`
  raw-casts into an unsigned radius (UB); non-positive `rangeSigma`
  collapses `normFactor` to 0, so `val /= normFactor` writes a native
  `0.0/0.0` `NaN` straight into the integer output buffer *inside* ITK's
  own threaded loop, before `mexitk`'s export step runs, so `ClampExport`
  cannot help — this one needed a pre-execution guard instead, joining
  the `FDG`/`FGA`/`FSN` semantic-guard family. `FCA`, `FCF` and `FGAD`
  now reject a negative `timeStep` (backward-time diffusion is ill-posed
  and the original's behaviour there is undefined); `timeStep == 0` stays
  accepted as a defined no-op. `FGAD`/`FCA`'s `numberOfIterations` moved
  from `CastParam<unsigned int>` to `CastParam<itk::IdentifierType>`,
  matching the `FCF`/`FAAB` precedent (`itkFiniteDifferenceImageFilter.h:186`).
  Five new error-path tests cover B and D; five new param-swap-detection
  tests (`fgadIterationsAndConductanceAreNotInterchangeable`,
  `fgadTimeStepAndConductanceAreNotInterchangeable`,
  `faabLayersControlsValueRange`, `fvmiAlphasAreNotInterchangeable`,
  `fblDomainAndRangeSigmaAreNotInterchangeable`) assert specific measured
  thresholds that only hold when parameters land in their documented
  slots, independently re-verified rather than trusted from the review.
  An optional FCF-uint8-large-`timeStep` test was scoped but dropped:
  `mexitk('FCF', [10 100], uint8data)` produces huge-but-finite values on
  the reference volume (`anyNaN=0`), not actual `NaN`, so the test's
  precondition was never met and it was not forced to fit. `FAAB`'s
  known blind spot (an rms<->iterations parameter swap has no reliable
  detection signal on this data beyond a fragile 100% vs 98.5%
  sign-purity difference) is now a documented comment at
  `faabProducesSignedLevelSetOnDouble`, not a silently missing case.
  `tests/tPhase4GradientsSmoke.m` grew from 28 to 38 test methods (10 new:
  5 error-path, 5 param-swap-detection). 206/206 tests passed on macOS
  arm64 locally against Homebrew ITK at that point, no regression in any
  existing suite.
- **Phase 4 final micro-batch**: re-review found `FBL`'s `domainSigma == 0`
  boundary case slipped past the negative-only guard above: it fails
  through a different mechanism (`GaussianSpatialFunction::Evaluate`
  divides by `2*sigma*sigma` while building the kernel, so every kernel
  weight is a division by zero -- `itkGaussianSpatialFunction.hxx:44-55`),
  silently, with no exception: confirmed live, `mexitk('FBL',[0 5],V)`
  returned all-`NaN` on `double`, uniformly zero on `uint8`. Widened the
  guard from `domainSigma < 0` to `domainSigma <= 0`
  (`mexitk:FBL:domainSigma` covers both mechanisms now), documented both
  in the code comment and `docs/COMPATIBILITY.md` deviation 11. Added
  `fgmIntegralExportMatchesFloorOfDouble`, a value-level regression test
  pinning the `int32`/`uint8` double-accumulate-then-`ClampExport` path
  (`double(outInt) == floor(outDbl)`, same for `uint8`) so the bit-identity
  guarantee from the prior fix batch cannot silently rot; verified
  empirically first (0 mismatches across 442368 voxels for both types,
  maxAbsDiff 0) before writing the assertion, per the never-tune-to-pass
  rule. `tests/tPhase4GradientsSmoke.m` grew from 38 to 40 test methods.
  208/208 tests pass on macOS arm64 locally against Homebrew ITK, no
  regression in any existing suite.

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
3. **How broad should the opcode surface get?** 30 of 40 are now implemented;
   only 3 (FCA, FOMT, SWS) have reference data, and reference capture requires
   the Intel-Linux binary. The 27 Phase 1/2/3/4 opcodes ship smoke-tested only.

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

10 opcodes remain unimplemented; parameters are known exactly
(`docs/matitk_opcode_registry.txt`) and ITK classes are mapped.
Phase 1 (FMEDIAN, FMEAN, FBT, FDG, FBB, FSN, FF, FD, FGA), Phase 2 (FBD,
FBE, FDM, FDMV, FVBIH), Phase 3 (SCT, SCC, SIC, SNC, SOT) and Phase 4
(FAAB, FBL, FCF, FGAD, FGM, FGMRG, FLS, FVMI) are done.
Each ships with an honest status; no reference data means `smoke-tested` at best.

Known problem cases:
- **SCSS** maps to `itk::bio::CellularAggregate` (opt-in `ITKBioCell` remote module,
  mesh output, global static state). Recommend dropping rather than porting.
- **FGMS** could not be pinned to an ITK class; needs verification against the binary.
- **FFFT** VNL FFT backend was removed; rerouted via pocketfft. Output semantics unconfirmed.
- **RD** `SetStandardDeviations` is inert unless `SmoothDisplacementFieldOn()` is also called.
