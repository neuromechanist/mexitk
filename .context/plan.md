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
3. **How broad should the opcode surface get**, given only 3 have reference data,
   and reference capture requires the Intel-Linux binary?

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

37 opcodes remain unimplemented; parameters are known exactly
(`docs/matitk_opcode_registry.txt`) and ITK classes are mapped.
Suggested order: high-confidence, single-output filters first
(FMEDIAN, FMEAN, FBT, FBD, FBE, FGA/FDG, SCT, SIC).
Each ships with an honest status; no reference data means `smoke-tested` at best.

Known problem cases:
- **SCSS** maps to `itk::bio::CellularAggregate` (opt-in `ITKBioCell` remote module,
  mesh output, global static state). Recommend dropping rather than porting.
- **FGMS** could not be pinned to an ITK class; needs verification against the binary.
- **FFFT** VNL FFT backend was removed; rerouted via pocketfft. Output semantics unconfirmed.
- **FGA** is likely a duplicate of FDG, an artifact of the original's Perl generator.
- **RD** `SetStandardDeviations` is inert unless `SmoothDisplacementFieldOn()` is also called.
