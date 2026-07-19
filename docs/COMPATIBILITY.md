# Compatibility with the original MATITK

This document records, precisely, where `mexitk` reproduces the original `matitk`
binary and where it does not.
It is the honest counterpart to the README's status table.
Nothing here is estimated;
every number was measured by running both implementations over the same input.

## Read this first, if you are comparing against an older result

**Segmentation output produced through `mexitk` will differ slightly from output produced
by the original `matitk` binary on Linux before 2026.**
If you are comparing a result computed today against a historical result,
expect small differences, and do not assume either one is broken.

Concretely:

- **`FOMT` (Otsu thresholding) is identical** for `double` and `single` input.
  No difference at all.
- **`FCA` (anisotropic diffusion smoothing) differs.**
  Root-mean-square difference of 2.6e-3 after one iteration,
  on a volume whose intensities span 0 to 88,
  growing to 5.7e-3 after five iterations;
  about 40% of voxels differ by some non-zero amount.
- **`SWS` (watershed) differs.**
  It finds the *same number of regions* every time,
  but the region containing a given seed voxel is not always identical:
  across 16 tested seed and parameter combinations, 11 matched exactly,
  and the worst case overlapped the original with a Dice coefficient of 0.718.

**Why this happens, and why it is not a defect in mexitk.**
`mexitk` calls the *same ITK filters* the original called, with the same parameters.
The original was built against ITK 2.4 in 2006; `mexitk` is built against ITK 5.4.
ITK's own implementations of anisotropic diffusion and watershed changed over those 19 years.
The difference is upstream ITK's evolution, not a porting error.
Removing it would mean pinning a 19-year-old ITK or forking ITK's filter internals.
Both were considered and rejected:
that would mean rewriting the science, which this project will not do.

**This deviation is accepted deliberately.**
The practical alternative is not "identical results".
It is that segmentation does not run on Apple Silicon at all,
because the original ships no `mexmaca64` and MEX files cannot run under Rosetta.

The exact magnitudes are asserted by the test suite
(`tests/tFcaReference.m`, `tests/tSwsReference.m`)
and broken down per opcode below.

## The reference

| | |
|---|---|
| Binary | `matitk.mexa64`, 9,651,458 bytes |
| MD5 | `c7d1432080e9edc6795a38717f5ab628` |
| Version string | `MATITK v.2.4.04 Aug 18 2006` |
| Built against | ITK 2.4 |
| Captured on | Linux x86_64, MATLAB R2025b |
| `mexitk` built against | ITK 5.4.6 |

The reference input is MATLAB's built-in `load mri` volume (`squeeze(D)`),
a 128x128x27 `uint8` volume with intensities spanning 0 to 88.
It ships with base MATLAB,
so fixtures are reproducible anywhere without redistributing imaging data,
and the original MATITK paper uses the same volume as its own example.

Captured fixtures live in `tests/fixtures/`,
and the capture harness that produced them is in `tools/capture_reference/`.
The fixtures are committed rather than generated
because regenerating them requires the 2006 binary,
which is Intel-Linux-only and has no public source.

### Second capture campaign (2026-07-18)

Epic 2 Phase 1 extended the harness to the 30 opcodes `mexitk` has since
implemented (`s07`-`s11`), a set of cross-check probes (`s12`), and the 10
still-unimplemented opcodes (`s13`), then ran it against the same binary
used for the first campaign, re-verified: `matitk.mexa64`,
`c7d1432080e9edc6795a38717f5ab628`. Captured on the same machine class as
the first campaign — MATLAB R2025b Update 2 on an Intel-Linux machine, no
hostname or path identifying it beyond that. The campaign took 3 runs:
several scripts crash the original's process (see below), so each
`s07`-`s13` script runs in its own `matlab -batch` invocation for crash
isolation, and a script left incomplete by one run was resumed
(`MEXITK_REFCAP_RESUME=1`) in the next rather than re-captured from
scratch. `tools/capture_reference/README.md` documents the full mechanism
(completion sentinels, resume mode, dry-run validation).

256 fixtures were captured: 230 successful calls, 20 recorded rejections
by the original (a rejection *is* the reference for that input, not a
capture failure), and 6 cross-check summary files from `s12`. All 256
passed import verification (loads cleanly, no dry-run markers, every
`success=true` fixture has its full output and hash, every `success=false`
one has a non-empty error message) before being committed alongside the
33 fixtures from the first campaign; `tests/tFixtureHygiene.m` now asserts
this holds — including output-hash self-consistency, recomputed at test
time — for all 289 committed fixtures on every test run.

Headline facts about the original's own behaviour, measured directly, not
assumed (none of these are `mexitk` findings; they describe only what the
2006 binary itself does — no opcode's validated/bounded-deviation status
changes here, and no deviation-table row is added, because that requires
the reference tests this epic's Phase 3 will add):

- **Seeded calls type-check an absent second image against the input
  class.** `SCT`/`SCC`/`SNC`/`SIC` calls without a real `arg4` failed on
  `single`/`uint8`/`int32` input with `Both images (inputArrays) must be
  of the same data type.` — the original checks the default (empty)
  `arg4` against the primary input's class even when no second image is
  conceptually being passed. `double` input was unaffected (an empty
  `double` `[]` happens to match). This was run 1's observed behaviour,
  not something any committed fixture demonstrates on its own: the fix it
  drove (`capture_case`'s class-matched-empty `arg4`) means every other
  seeded capture in the committed set now *succeeds* instead of
  reproducing it. `s12`'s `probe10_arg4_class_mismatch` deliberately
  bypasses that fix (an explicit `arg4 = []`) to keep this claim
  fixture-backed: `sct_arg4_mismatch_uint8.mat`.
- **`FD` rejects `uint8` and `int32` input outright**, both with `This
  method is not supported with this data type! Try converting to double
  first.`, regardless of parameters.
- **`FDG`/`FGA` on `uint8` warn then throw; on `int32` they only warn.**
  Both emit `itkGaussianOperator`'s kernel-width-truncation warning on
  every non-`double`/`single` class at `gaussianVariance=4`, but `uint8`
  additionally throws `Unexpected Standard exception` afterward, while
  `int32` completes (and, on `int32`, `FGA` and `FDG` produce
  bit-identical output — consistent with `mexitk`'s FGA=FDG choice).
- **`FAAB` crashes the original's process on `uint8` input specifically —
  `int32` completes.** A floating point exception, not a catchable
  `itk::ExceptionObject`, on both raw and already-binarized `uint8`
  input; `int32` (raw and binarized) captured successfully in the same
  campaign, isolating the crash to the pixel type rather than the pixel
  value distribution.
- **Seed coordinates are 1-based, matrix-order (no transpose), with an
  exclusive upper bound at each dimension's own size.** A literal
  0-based seed `[0 0 0]` is rejected with the original's own words:
  `Please note that array in matlab starts from 1` — a direct statement
  of 1-based indexing, not an inference from a truncated message (the
  first campaign only recorded `Please note that array in matlab...`
  before a harness bug, since fixed, cut it off; the recaptured fixture
  has the full sentence). Seeds one step off a known-good point in
  either direction behave normally. Combined with the earlier,
  separately measured rejection of seeds sitting exactly at a
  dimension's own extent (`[70 50 27]` on the 27-deep volume, backed by
  `sct_20_60_dimmax_double.mat`; `SIC`'s original second seed `[1 128 1]`
  on the 128-wide volume) — both rejected with `Location of seed outside
  volume` — the valid range for a dimension of size *N* is 1 to *N*-1,
  not 1 to *N*. `[1 128 1]` was replaced everywhere in the harness once
  this was found (`S2 = [2 120 2]` in `s09`/`s12`), so like the `arg4`
  finding above, no committed fixture demonstrated it on its own; `s12`'s
  `probe11_dimmax_second_seed` captures it deliberately:
  `sic_dimmax_double.mat`.
- **The original binary can corrupt its own heap at MATLAB exit**, after
  every case in a script's table has already completed and saved
  (`munmap_chunk(): invalid pointer` / `double free or corruption (out)`,
  observed after `s09` and `s13` respectively finished their last case).
  This is why completion sentinels exist: a nonzero exit code alone does
  not mean a script lost data.

These are recorded here as what the campaign found, not as `mexitk`
compatibility claims — turning any of them into a promotion, a new
deviation-table row, or a documented guard is this epic's Phase 3 (the
reference tests), once mexitk's own behavior at these points is measured
against them.

### Second capture campaign: Phase 3 findings

Phase 3 measured `mexitk`'s own behaviour against every fixture the
campaign above captured, fixed four independent root causes it found along
the way, and re-measured. `tools/classify_fixtures.m` is the tool that
produced this classification and reproduces it on demand; its full output
per fixture, and the resulting per-opcode summary, drive every status
promotion in this document, the opcode registry, and the README.

**The X/Y axis convention.** The original 2006 binary maps X-named
parameters onto MATLAB's dim 2 (ITK axis 1) and Y-named parameters onto
MATLAB's dim 1 (ITK axis 0); Z is unchanged. This was not previously known
or guessed — `mexitk` mapped every such parameter straight through, one
parameter index to one ITK axis, with no swap. Proven directly by fixture
comparison, not inferred from the naming alone:

- **`FF`**: `ff_1_0_0_*` (`XDIRECTION=1`) is bit-identical to
  `flip(vin, 2)`; `ff_0_1_0_*` (`YDIRECTION=1`) is bit-identical to
  `flip(vin, 1)`. `ZDIRECTION` needs no swap (`ff_0_0_1_*` already matched
  `flip(vin, 3)`).
- **`FD`**: `fd_1_0_double` (`SETORDER=1, SETDIRECTION=0`) is bit-identical
  to the swapped mapping's `SETDIRECTION=1`, and `fd_1_1_double`
  (`SETDIRECTION=1`) is bit-identical to the swapped mapping's
  `SETDIRECTION=0`. `SETORDER=0` (`fd_0_0_double`) is exact regardless,
  since a zeroth-order derivative does not depend on direction.
- **`FMEDIAN`**: `fmedian_r3_1_1_double` (XRADIUS=3, YRADIUS=1 -- asymmetric
  between X and Y) deviated under the unswapped mapping and is bit-identical
  under the swap; this fixture alone is the proof. `fmedian_r1_1_3_double`
  (XRADIUS=YRADIUS=1, only ZRADIUS differs) does NOT independently confirm
  the swap: X and Y are equal there, so swapping them is a no-op, and the
  fixture was already exact either way -- the same reason
  `fmedian_r1_1_1_*` (fully symmetric) could not have revealed the bug.
- **`SNC`**: `snc_rx_wide_seedS1_double` / `snc_rz_wide_seedS1_double`
  (asymmetric radius) are the discriminating fixtures; `SNC` is the one
  member of this family that does NOT reach bit-exactness even with the
  correct swap applied — see the "FDM/FDMV" and bounded-deviation
  discussion below and `tests/tReferenceBounded.m`; a swap-invariant
  symmetric-radius fixture (`snc_r0_band_seedS1_double`, radius `[0,0,0]`)
  still deviates substantially, proving the residual is a separate,
  axis-order-independent divergence in `NeighborhoodConnectedImageFilter`
  itself.
- **`FVBIH`**: `fvbih_distinct_hole_double` (radiusX=2, radiusY=1) is the
  discriminating fixture; `fvbih_baseline_hole_double` (radiusX=radiusY=1)
  was already exact either way.
- **`FMEAN`** received the same swap for family consistency (identical
  `XRADIUS`/`YRADIUS`/`ZRADIUS` registry naming to `FMEDIAN`), but every
  captured `FMEAN` fixture happens to be symmetric-radius, so the swap is
  not independently fixture-proven for `FMEAN` the way it is for the other
  four; `FmeanOpcode::StatusNote` says so explicitly.

Seed coordinates are unaffected by any of this: they stay matrix-order,
1-based, no transpose, exactly as already documented above.

**`FDM`/`FDMV` reimplemented pipeline.** The original computes both
outputs in its own import orientation (the same X/Y swap as above, applied
structurally to the whole volume via `itk::PermuteAxesImageFilter` since
neither opcode has an X/Y-named parameter to swap directly), runs
`itk::DanielssonDistanceMapImageFilter` **natively at the input's own
pixel type** — not promoted to `float`, which was `mexitk`'s previous,
disproven assumption — and rescales the raw output to a fixed ceiling
(`65535` for double/single/int32, `255` for uint8; NOT
`NumericTraits<PixelT>::max()`, which would give `realmax('double')` on
double and is disproven by every double fixture reading `{0,...,65535}`).
Verified against fixtures, not assumed:

- The float-promoted design (`mexitk`'s previous implementation)
  reproduced double and single exactly but disagreed with the original on
  roughly 47-61% of voxels for uint8/int32 on `FDM`. Switching to a
  native-pixel-type Danielsson pass made int32 bit-exact
  (`fdm_raw_int32`) and reduced uint8's disagreement to a small residual
  (`fdm_raw_uint8`: 826/442368 voxels, max absolute difference 6,
  RMS 0.218 — see `tests/tReferenceBounded.m`).
- **`FDMV`'s Voronoi labels are sequential IDs, not drawn from the
  input's own pixel values** — disproving the assumption `FDMV`'s own
  `StatusNote` carried into this phase. Verified formula at object
  voxels: `output = (id-1) * typeMax/(N-1)`, where `id` is the 1-based
  sequential number of the object voxel in the permuted volume's own
  scan order (dim2-fastest relative to the original) and `N` is the
  object-voxel count. Confirmed structurally in
  `tests/tPhase2MorphologySmoke.m`
  (`voronoiIdsAreSequentialNotDrawnFromInput`): among 65010 voxels
  sharing one input label value, all 65010 receive distinct `FDMV`
  output values.
- **`FDMV`'s uint8 output does NOT go through that rescale.** It is a
  direct narrowing cast of `(id-1)` into `uint8`, wrapping via standard
  unsigned overflow (`(id-1) mod 256`), matched against
  `fdmv_raw_uint8` to 99.43% of voxels (2516/442368 differ); every
  inspected residual voxel has the fixture value exactly one id higher
  than predicted, consistent with an ITK 2.4-vs-5.4 Voronoi tie-break at
  an equidistant background voxel, not a wrong formula. This is a
  genuinely different code path than double/single/int32's rescale,
  plausible given the original was Perl-generated per pixel type from an
  ITK 2.4 example rather than hand-written once.
- **`FDMV`'s double output has a residual right at double precision's own
  limit** (RMS about 3e-12, max absolute difference about 7e-12, on
  roughly a third of voxels across every double fixture) that persisted
  under an alternative, manually-ordered rescale computation too — see
  `src/opcodes/fdm.cpp` for the two op-orders tried. int32's floor-cast
  and single's float32 precision both absorb the same tiny difference
  invisibly; only double's full precision surfaces it. Not chased
  further, per project policy against tuning past a measured, explained
  floating-point artifact.
- **All-background input is rejected** (`mexitk:fdm:noObject`) for both
  opcodes: the original's own distance field over zero objects is a
  meaningless artifact of its internal initialization (measured: an
  all-zero uint8 volume yields distances of roughly 294 to 443 on this
  project's geometry, all past `uint8`'s 255 max), not a defined answer
  to "distance to the nearest object" when there is no object. The
  `fdm_zero_double`/`fdm_zero_uint8` fixtures (where the original itself
  succeeded, producing that meaningless field) are the fixture-side
  half of this: `mexitk` deliberately refuses an input the original
  accepted, the same direction as deviation 5 and its siblings below.

**`SOT`'s root cause.** Two independent bugs, both fixture-proven, both
fixed:

1. **Polarity was inverted.** The original assigns its mask value to the
   HIGH side of the Otsu threshold (`intensity > threshold`); `mexitk`
   assigned it to the LOW side, `itk::OtsuThresholdImageFilter`'s own
   default. Fixed by explicitly setting `InsideValue`/`OutsideValue`.
2. **The mask value itself was assumed wrong.** The pre-Phase-3 code
   (and this document, in the "SOT inside/outside defaults and polarity"
   section below) assumed the original's mask value was the pixel type's
   own max (`realmax('double')` on double, `255` on uint8) — an assumption
   that predates `SOT` having any reference capture and was never
   verified. Every captured `sot_*` fixture, double included, has unique
   output `{0,255}`, never `{0,realmax}`. The true mask value is a FIXED
   `255` on every pixel type, matching the same convention used
   throughout the original's other segmentation opcodes (`SCT`'s inferred
   `ReplaceValue=255`, `SNC`/`SIC`'s `ReplaceValue` default of 255).
3. **Separately, the histogram range was wrong on uint8**: ITK 5.4's Otsu
   histogram calculator defaults to the full `[0,255]` TYPE range instead
   of the data's own `[min,max]`, shifting the computed threshold
   (measured: 33.867 on the type range vs. the correct 32.3125 over this
   project's reference volume, whose data spans `[0,88]`), misclassifying
   1087 intensity-33 voxels. Fixed via `SetAutoMinimumMaximum(true)`.

All three fixes together make `SOT` bit-exact against every captured
fixture, across all four pixel types (`tests/tReferenceExact.m`), and as
a direct consequence, `SOT`'s partition now agrees with `FOMT`'s N=1
partition EXACTLY (not merely `>0.997` as previously measured pre-fix;
see `tests/tPhase3RegionGrowingSmoke.m`'s `sotMatchesFomtSingleThreshold`)
— the histogram-range fix pulled `SOT`'s chosen threshold onto the same
value `FOMT` was already using.

**`SOT`'s histogram-range bug is NOT also `FOMT`'s bug.** `FOMT`
(`OtsuMultipleThresholdsImageFilter`) shows the identical symptom as
pre-fix `SOT` — `uint8` deviates, double/single exact — and was tested
directly on that hypothesis. Ruled out empirically, not just by reading
ITK's headers: `OtsuMultipleThresholdsImageFilter`'s own histogram
generator already defaults to the image's real min/max (unlike `SOT`'s
base class), and forcing the identical bounds explicitly changed nothing
on any of the three deviating fixtures. See "FOMT: bit-identical for
floating-point input, and for uint8 at N=1" below for the full
investigation and the measured per-N numbers.

**`FGA`==`FDG` alias, confirmed.** The "FGA is implemented as a
deliberate duplicate of FDG" claim below predates any reference capture
for either opcode and was inferred from the registry's identical
parameter shape alone. It is now fixture-confirmed: `s12`'s
`s12_fga_fdg_isequal.mat` cross-check probe shows the original's own
`FGA` and `FDG` outputs are bit-identical to each other at every
capturable point (double and uint8, three `gaussianVariance` values
each), and they share the same uint8 failure mode (a caught exception
after a kernel-width-truncation warning).

**Empty-seed fixtures (`snc_emptyseed_double`,
`scc_2p5_5_100_emptyseed_double`) are not a reproducible reference.** Both
were captured with a genuine, explicit `seedArg=[]` (confirmed against
`tools/capture_reference/s09_regiongrow_capture.m` — not a harness bug),
yet neither fixture's captured output is all-zero, the behaviour every
other empty-seed capture in this project shows (`sct_20_60_emptyseed_double`
IS all-zero, for contrast). Instead, each carries exactly the region that
would have grown from the single seed point `S1=[70 50 14]` used by the
immediately preceding capture in the SAME script:

- `snc_emptyseed_double` has exactly one nonzero voxel, at `S1` itself,
  value 255 — the exact voxel `SNC`'s own seed-convention test pins for a
  real `S1` call.
- `scc_2p5_5_100_emptyseed_double` has exactly 93645 nonzero voxels,
  value 100 — exactly the region size `mexitk('SCC',[2.5 5 100],V,[],S1)`
  itself produces from a real `S1` call (see
  `tPhase3RegionGrowingSmoke.sccLargerMultiplierGrowsOrEqual`'s own
  comment for that number).

This is strong, converging evidence that the ORIGINAL binary's own C++
implementation retains seed state across calls within one MATLAB session
— a session-order-dependent artifact of the 2006 binary itself, not a
property of the `SNC`/`SCC` opcodes. `mexitk` constructs a fresh ITK
filter object with no persisted state on every call, so it cannot
reproduce this even in principle, and should not try to: matching a
stateful bug that depends on unrelated prior calls in the same capture
script would not be a meaningful agreement claim about either opcode.
`mexitk`'s own defined behaviour for an empty seed list — an all-zero
output — is asserted directly in `tests/tReferenceRejections.m`
(`emptySeedFixturesAreNotAReproducibleReference`) instead of compared
against these two fixtures, and both opcodes are still promoted to
validated on the strength of every OTHER captured fixture (see the
Coverage section below).

## Why exact agreement is the bar

The reason to reimplement MATITK rather than switch to MATLAB's Image Processing Toolbox
is that the underlying algorithms stay the same ITK filters.
The Image Processing Toolbox equivalents are *different algorithms*
and would silently change segmentation output.
So the value of `mexitk` rests on demonstrating agreement, not asserting it.

That demonstration produced a more nuanced result than "identical".
One opcode is bit-identical.
Two are the same ITK filters with the same parameters,
but ITK's own implementations changed between 2.4 and 5.x,
so their output differs by a small, measured amount.
This is a categorically different situation from swapping in a different algorithm,
but it is not bit-identity, and it is not described as such anywhere in this project.

## FOMT: bit-identical for floating-point input, and for uint8 at N=1

`FOMT` reproduces the original **exactly**, bit for bit,
for `double` and `single` input
at N = 2 (50 bins), N = 3 (128 bins) and N = 4 (100 bins).
Those cover every threshold count NFT uses.
`uint8` input at N = 1 (128 bins, `fomt_1_128_uint8`) is also exact.

`uint8` input at N = 2, 3, 4 does **not** match exactly:

| N (bins) | voxel disagreement |
|---|---|
| 2 (50) | 0.17% (755 of 442,368 on output 2) |
| 3 (128) | 0.38% (1697 of 442,368 on output 3) |
| 4 (100) | 0.84% (3725 of 442,368 on output 4) |

ITK changed how integral pixel types are binned into the Otsu histogram since 2.4.
The disagreement is asserted at these exact measured values (10% headroom, per-N,
not a single loose ceiling) by `tests/tFomtReference.m`
(`uint8DeviationStaysWithinMeasuredBound`).

**Epic 2 Phase 3 investigated this directly and ruled out SOT's own root
cause.** `SOT` (`OtsuThresholdImageFilter`, a single-threshold sibling class)
had a genuine histogram-range bug: its base class defaults to the pixel
type's TYPE range rather than the image's actual data range unless
`SetAutoMinimumMaximum(true)` is called explicitly (see "SOT inside/outside
defaults and polarity" below). `FOMT`'s `OtsuMultipleThresholdsImageFilter`
looked like a plausible candidate for the identical bug given the matching
symptom (uint8 deviates, double/single exact) and having no reference
capture to check against for the four years since it was written. It is
NOT the same bug: traced directly in ITK's headers,
`OtsuMultipleThresholdsImageFilter` builds its histogram via
`itk::Statistics::ScalarImageToHistogramGenerator`, whose underlying
`SampleToHistogramFilter` defaults `AutoMinimumMaximum` to `true` in its own
constructor — the image's actual min/max, not the pixel type's range,
already the default with no code change needed. Confirmed empirically, not
just by reading the header: forcing the exact same bounds explicitly (via
`itk::MinimumMaximumImageCalculator`, `SetAutoHistogramMinimumMaximum(false)`,
manual `SetHistogramMin`/`SetHistogramMax`) produced bit-identical output to
the unmodified default on all three deviating `uint8` fixtures — the
disagreement did not shrink by a single voxel. The uint8 N&ge;2 deviation is
therefore a genuine ITK 2.4-to-5.x difference in how the multi-threshold
Otsu calculator itself bins integral pixel values, not a histogram-range
bug, and not something a bounds fix can close.

### Quirks reproduced deliberately

- **N thresholds return N outputs, not N+1.**
  Otsu with N thresholds partitions intensity into N+1 classes,
  but the original returns only the lowest N;
  the top class is computed and silently discarded.
  Measured coverage is 0.756, 0.939 and 0.941 of the volume for N = 2, 3, 4,
  the shortfall being exactly the dropped top class.
  This is an off-by-one inherited from the ITK 2.4 example MATITK was generated from.
  It is reproduced because callers depend on it:
  NFT's `segm_scalp.m` and `segm_brain.m` both use `not(mask)`,
  which selects everything outside class j and therefore includes the dropped class.
- **`nargout` must equal N exactly.**
  Requesting any other number of outputs is an error,
  as in the original (`Mismatch number of output arguments.`).
- **Masks are 0/255 in the input's own class**, not logical and not 0/1.

### One hypothesis that was wrong

ITK exposes `SetReturnBinMidpoint`,
which selects whether a threshold is reported as its histogram bin's midpoint or its maximum.
It defaults to midpoint only under `ITKV4_COMPATIBILITY`, and to bin maximum otherwise.
Since the reference is an ITK 2.4 build, midpoint looked like the setting to match.
It is not:
setting it made every previously-exact `double` and `single` case diverge.
The modern default reproduces the original bit-for-bit.
The call is left explicit in `src/opcodes/fomt.cpp` with a comment,
so this is not rediscovered and "fixed" later.

## FCA: bounded deviation

`FCA` does **not** reproduce the original bit-for-bit.
Measured against the reference volume, over an intensity range of 0 to 88:

| case | RMS | max abs |
|---|---|---|
| 1 iteration, double, timeStep 0.0625, conductance 3.0 | 2.610852e-03 | 4.652961e-02 |
| 5 iterations, double | 5.695774e-03 | 1.566523e+00 |
| 1 iteration, single | 2.646971e-03 | 4.717255e-02 |
| 5 iterations, single | 6.421596e-03 | 1.564568e+00 |

About 40% of voxels differ by more than 1e-6,
and the error compounds with iteration count.

**Cause.** ITK's anisotropic diffusion numerics changed between 2.4 and 5.x.
The divergence is already present after a single iteration,
which rules out a simple accumulation of rounding.
The conductance term is derived from a *global* average gradient magnitude,
recomputed every iteration
(`AnisotropicDiffusionImageFilter::InitializeIteration`
calls `CalculateAverageGradientMagnitudeSquared`),
so any small change to that global quantity perturbs every voxel's update slightly
and then compounds.
The exact upstream change was not isolated;
candidate contributors include `m_MIN_NORM` (1.0e-10 in ITK 5.4)
and the `m_ScaleCoefficients` factors introduced after 2.4.
This is recorded as an open question rather than a solved one.

**On the time step.** A prior assumption held that `timeStep = 0.0625` is a 2-D value
exceeding a lower 3-D stability limit of about 0.0417.
That is incorrect.
ITK's own default is `0.5 / 2^ImageDimension`, which is exactly 0.0625 in 3-D,
and the stability check fires only when `timeStep > minSpacing / 2^(dim+1)`,
which is also 0.0625 at unit spacing.
The value sits exactly on the boundary, not past it.
The original proceeds silently at that value, and so does `mexitk`.
ITK only warns; it neither throws nor clamps.

## SWS: bounded deviation

`SWS` does **not** reproduce the original's label image bit-for-bit,
but the evidence that it is the same algorithm, correctly parameterised, is strong.

- **Region count matches the original exactly** at every tested setting:
  9348, 8917, 9439, 9439 and 51 regions
  at (level, threshold) of (0.05, 0.01), (0.1, 0.05), (0.02, 0.001), (0, 0) and (0.5, 0.5).
  Matching five region counts exactly would not happen with a wrong filter or wrong parameters.
- **At level 0.5 the partition is provably identical up to relabeling.**
  The number of distinct (reference, mexitk) label pairs equals the label count,
  which is exactly the condition for a bijection between the two labelings.
- **At fine levels the partitions differ modestly.**
  At level 0.05 there are 10,161 distinct label pairs against 9,348 labels,
  so a minority of regions split differently.

### What this means for callers

Raw watershed label values are arbitrary identifiers,
so comparing them directly overstates the disagreement.
What callers actually do is extract the region containing a seed.
NFT's `segm_brain.m` does exactly this: `bi = c == c(WMp(1), WMp(2), WMp(3))`.

Measured over 4 seeds across 4 parameter settings,
**11 of 16 combinations reproduce the seed region exactly**.
The remaining five differ, with a worst observed Dice coefficient of **0.718**
on a small region at a fine level;
the others were 0.977 and 0.996.
`tests/tSwsReference.m` asserts these aggregates.

### Input is raw intensity, not a gradient

ITK's own examples feed watershed a gradient-magnitude edge map.
The original does not: it passes the input volume straight through.
NFT relies on this, passing an inverted intensity volume (`mb - double(b3)`)
rather than a gradient.
`mexitk` matches the original.
Inserting a gradient stage would silently change every existing caller's segmentation.

## Deliberate deviations

These are the only places `mexitk` intentionally differs.
Each one either accepts strictly more than the original
or refuses to reproduce a defect.

| # | Deviation | Rationale |
|---|---|---|
| 1 | **`SWS` overthresholding raises a MATLAB error instead of killing the process.** The original catches ITK's overthresholding exception and then dies: `matitk('SWS',[1 1], V)` throws, then segfaults, and MATLAB exits with "MATLAB is exiting because of fatal error". | Taking down the user's MATLAB session, losing their workspace, is not behaviour worth preserving. This is the one place `mexitk` is required *not* to match. |
| 2 | **String objects are accepted as well as char arrays.** The original rejects `matitk("FCA", ...)` with `Opcode input field must be of type string.` because MATLAB's `string` class postdates it by a decade. | A strict superset: every call that worked against `matitk` behaves identically. Nothing changes meaning. |
| 3 | **Console output says `mexitk`, not `MATITK`.** The original prints `executing MATITK in double mode`. | Printing another project's name would misattribute this code. Cosmetic; no caller parses it. |
| 4 | **Errors carry `mexitk:*` identifiers.** The original throws untagged errors. | Makes failures catchable by identifier. Diagnostic text is preserved. |
| 5 | **Out-of-range parameter values raise `mexitk:paramRange` instead of casting with undefined behaviour.** A value like `FBT`'s `upperThreshold = 300` on a `uint8` volume, or a negative radius/repetition/order count, would be an out-of-range or negative-to-unsigned cast, which is undefined behaviour in C++. The same guard also covers a finite value beyond a narrower floating type's range, e.g. `upperThreshold = 1e39` on a `single()` volume (`float`'s max is ~3.4e38); `Inf`/`NaN` are exactly representable in `float` and still pass through, matching the original. In-range values, including the original's own truncating behaviour (e.g. `255.9` &rarr; `255` on `uint8`), are unaffected. | The original's own behaviour on these inputs is unknown and unreproducible (no reference capture covers them), and reproducing undefined behaviour on purpose is not a defect worth keeping. Refusing it is a strict subset of accepted inputs, not a change to any in-range result. |
| 6 | **`FDG`/`FGA` reject `gaussianVariance <= 0`** with `mexitk:FDG:gaussianVariance` / `mexitk:FGA:gaussianVariance`. | A non-positive variance silently produces a degenerate, non-Gaussian kernel rather than an error. In-range (positive) variance is unaffected. |
| 7 | **`FSN` rejects `alpha == 0`** with `mexitk:FSN:alpha`. | `alpha = 0` makes `SigmoidImageFilter`'s functor divide by zero, producing `NaN` that then hits an undefined-behaviour cast into an integer pixel type. Nonzero `alpha` is unaffected. |
| 8 | **Out-of-range or non-finite filter *results* export as a defined value on integral pixel types, instead of an undefined-behaviour cast.** Every promoted opcode (`FCA`, `FD`, `FDM` from Phase 1-3; `FAAB`, `FCF`, `FGAD`, `FGMRG`, `FLS`, `FVMI` from Phase 4) exports its `uint8`/`int32` result through `ClampExport` (`src/mexitk_common.h`), which saturates out-of-range finite values into `[lowest, max]` of the target type and maps non-finite values (`NaN`) to `0`. `FGM`'s `int32` path additionally exports through the same helper for the same reason, though `FGM` itself is not a promoted opcode (see its own note below). `ClampExport` replaced an earlier `itk::ClampImageFilter`-based cast-back: that filter's own `Functor::Clamp` falls through to a plain `static_cast` for `NaN`, because `NaN` compares false against both of its bounds checks (`itkClampImageFilter.h:97-107`) — undefined behaviour, reachable in practice via an unstable diffusion `timeStep` or a `0/0` in `FVMI`'s vesselness measure. Deterministically reachable even for the out-of-range (non-`NaN`) case: `FDM` on an all-zero `uint8` volume computes distances measured at roughly 294 to 443 across the volume, all past `uint8`'s 255 max, so the plain cast back was undefined behaviour, not merely lossy. | Refuse to reproduce undefined behaviour; the original's behaviour on these exact inputs was undefined, not reproducible even in principle, so there is nothing to match. In-range results are unaffected: `ClampExport`'s bounds comparison and in-range cast mirror ITK's own `Functor::Clamp` exactly, so clamp-then-truncate equals truncate when the value already fits — this changes no previously-defined output, verified by the full fixture suite staying green across the swap and by an explicit bit-compare on `FGM`'s `uint8`/`int32` paths (0 mismatches on the reference volume). |
| 9 | **`SOT` rejects `numberOfHistogram < 2`** with `mexitk:SOT:numberOfHistogram`, instead of running ITK's Otsu calculator. Measured directly, not assumed: 0 or 1 histogram bins crash the whole MATLAB process (a bus error / SIGSEGV inside `itk::Statistics::Histogram::GetIndex`), not a catchable `itk::ExceptionObject`. `numberOfHistogram >= 2` is unaffected. | Same severity class as deviation 1 (`SWS` overthresholding): taking down the user's MATLAB session is not behaviour worth preserving, and there is no reference capture for a crashing call to match against in the first place. |
| 10 | **Non-finite or wildly out-of-range seed coordinates raise `mexitk:seeds` instead of casting with undefined behaviour.** `SeedPointsToIndices` (`SCT`/`SCC`/`SNC`/`SIC`) validates every coordinate as a finite `double` truncating into `[1, size(axis)]` before casting to an ITK index. `NaN`/`Inf` previously passed central validation's `s < 1.0` check unrejected (an IEEE unordered comparison, false for both) and then hit a raw cast; a huge finite coordinate overflowed `itk::IndexValueType` on that same cast. Both are undefined behaviour in C++, and the overflow case was platform-dependent in a way that stayed hidden on one architecture: ARM64's saturating convert masked it (the garbage result still failed the old bounds check), but x86 wrapped to `INT64_MIN`, where the following `-1` base shift was a second, independent signed-overflow UB. In-range values, including fractional truncation (`70.9` behaves as `70`), are unaffected. | Same rationale as deviation 5: the original's behaviour on these exact inputs is unknown and unreproducible, and reproducing undefined behaviour on purpose is not a defect worth keeping. One identifier (`mexitk:seeds`) covers both the non-finite and out-of-range cases deliberately, rather than splitting non-finite seeds off under `mexitk:paramRange`. |
| 11 | **`FBL` rejects `domainSigma <= 0` and `rangeSigma <= 0`** with `mexitk:FBL:domainSigma` / `mexitk:FBL:rangeSigma`, instead of running `BilateralImageFilter`. Traced directly in ITK's headers, and `domainSigma`'s non-positive case fails through two distinct mechanisms depending on sign: a negative `domainSigma` reaches a raw `(SizeValueType)std::ceil(...)` cast of a negative `double` into an unsigned type in `GenerateInputRequestedRegion` (`itkBilateralImageFilter.hxx:79,145`, undefined behaviour); `domainSigma == 0` instead reaches `GaussianSpatialFunction::Evaluate`, which divides by `2 * m_Sigma[i] * m_Sigma[i]` while building the kernel (`itkGaussianSpatialFunction.hxx:44-55`) — a zero denominator, producing `NaN` that silently propagated through the filter's weighted-average normalization with **no exception**: confirmed live before this guard existed, `mexitk('FBL', [0 5], V)` returned all-`NaN` on `double` and uniformly zero on `uint8`; the call now correctly errors instead. Separately, a non-positive `rangeSigma` collapses the filter's per-voxel accumulation threshold so nothing ever accumulates, making `val /= normFactor` compute `0.0/0.0` (`NaN`), which is then written by a raw `static_cast` straight into the native (non-promoted) integer output buffer *inside* `BilateralImageFilter`'s own `DynamicThreadedGenerateData` — before `mexitk`'s export step runs, so `ClampExport` cannot intervene the way it can for the promoted opcodes. In-range sigma is unaffected. | Same family as deviations 6/7 (`FDG`/`FGA`/`FSN`'s semantic guards): every failure here is inside ITK's own computation (undefined behaviour, or a silent `NaN` written natively before export), not at a narrowing-cast boundary `ClampExport` could catch; refusing the input is the only option that avoids undefined behaviour or a wrong-looking-defined result. |
| 12 | **`FCA`, `FCF`, `FGAD` and `FMMCF` reject a negative `timeStep`** with `mexitk:FCA:timeStep` / `mexitk:FCF:timeStep` / `mexitk:FGAD:timeStep` / `mexitk:FMMCF:timeStep`. A negative `timeStep` runs the diffusion/curvature-flow solver backward in time, which is ill-posed; the original's behaviour on this input is unknown and unreproducible. `timeStep == 0` stays accepted as a defined no-op, and the existing large-`timeStep` case (which merely triggers ITK's own `itkWarningMacro` and proceeds, per the `timeStep` comment in `fca.cpp`) is unchanged — still loud, still proceeds, now with a defined `ClampExport`-based result on integral output instead of an undefined one. **`FCF` and `FMMCF` additionally reject a non-finite (`NaN`/`+-Inf`) `timeStep`**, discovered during Epic 3 Phase 1 review: a plain `timeStep < 0.0` guard does not catch `NaN` (every ordered comparison against `NaN` is false), so it silently reached each filter's own solver. Measured directly, the two failure modes are NOT the same severity: `FCF` (`CurvatureFlowImageFilter`) silently returns an all-`NaN` output on every voxel with no exception, the same class as deviation 11 (`FBL`'s silent-`NaN` guard); `FMMCF` (`MinMaxCurvatureFlowImageFilter`) instead crashes the whole MATLAB process with a `SIGBUS` inside `MinMaxCurvatureFlowFunction::ComputeThreshold`'s `Dispatch<3>` path — the same severity class as deviation 1 (`SWS` overthresholding) and deviation 9 (`SOT` histogram bins). `FCA` and `FGAD` share the identical `timeStep < 0.0`-only guard and were not re-verified for the non-finite case in this pass (out of this review's scope); this is a known, not-yet-closed gap, not an assumption that they are safe. | Same rationale as deviation 5: refuse an input whose original behaviour cannot be reproduced or verified, while leaving every previously-defined value (including `timeStep == 0` and large-but-positive `timeStep`) unaffected. The non-finite half is closer to deviation 1/9's rationale for `FMMCF` specifically: taking down the user's MATLAB session is not behaviour worth preserving regardless of what the original would have done. |
| 13 | **`FDM`/`FDMV` reject an all-background input** (no nonzero voxel anywhere) with `mexitk:fdm:noObject`. Measured directly against the `fdm_zero_double`/`fdm_zero_uint8` fixtures, where the original itself succeeded: an all-zero `uint8` input yields distances of roughly 294 to 443 across this project's reference geometry, every one of them past `uint8`'s 255 max and, on every pixel type, not a meaningful answer to "distance to the nearest object" when there is no object — an artifact of the distance filter's internal initialization, not a defined computation. | Same severity/rationale class as deviation 5: the original's own output for this input is not a value worth reproducing, since "distance to the nearest of zero objects" has no defined answer. Refusing it is a strict subset of accepted inputs; every volume with at least one nonzero voxel is unaffected. |
| 14 | **`FD` accepts `uint8` and `int32` input; the original rejects both outright** with "This method is not supported with this data type! Try converting to double first.", regardless of parameters (measured directly against `fd_0_0_uint8`/`fd_1_0_uint8`/`fd_1_0_int32`, where the original itself failed). `mexitk` promotes `uint8` to `float` for the derivative (`itk::DerivativeImageFilter` requires a signed output pixel type, which `uint8` fails) and runs `int32` natively, returning a defined result for both. No agreement claim is made about the VALUE `mexitk` returns for these two pixel types — the original never produced one to compare against — only that the call succeeds; see `tests/tReferenceRejections.m`. | Accept strictly more, the same direction as deviation 2 (string objects): every call that worked against the original still works and still matches; `uint8`/`int32` input, which the original refused unconditionally, now succeeds instead of erroring. Nothing about the original's own defined behaviour (double/single) changes. |

## Behaviour matched deliberately, including the odd bits

- **The spacing argument (arg 6) is accepted and ignored.**
  Verified on the original: `[1 1 2]` and `[1 1 1]` produce bit-identical output
  for FCA, FOMT and SWS, so spacing is simply unwired there.
  Honouring it would diverge from every existing caller.
  It is still validated, so a malformed value is reported rather than silently swallowed.
- **The seed argument (arg 5) is accepted and ignored by `SWS`.**
  Verified bit-identical across no-seed, `[]`, a real seed, and omitting the argument.
  NFT passes a seed that watershed never consumes,
  then uses it afterwards to index the label image.
- **Too many parameters warns and proceeds** rather than erroring.
- **Opcodes are case-insensitive**; the paper uses `fomt`, NFT uses `FOMT`.
- **2-D input is rejected** with `Input volume A must be a 3D image.`

## Coverage

`mexitk` currently implements **32 of the original's 40 opcodes**. Epic 2
Phases 1-3 extended the capture harness to 30 of them, captured reference
fixtures for every one, and measured `mexitk`'s own agreement against every
fixture (`tools/classify_fixtures.m`; see "Second capture campaign: Phase 3
findings" above for how). Epic 3 Phase 1 added the remaining two,
`FMMCF` and `SFM`, each with its own captured fixture, measured the same
way. The status ladder now splits the 32 into three tiers by that
measurement, not by guesswork:

- **Validated (14):** FBB, FBD, FBE, FBT, FD, FF, FGM, FMEAN, FMEDIAN,
  FVBIH, SCC, SCT, SIC, SOT.
  Bit-identical to the original on every comparable captured fixture
  (`tests/tReferenceExact.m`).
  "Comparable" excludes fixtures where the original itself rejected the
  call, or where a captured fixture is a non-reproducible artifact rather
  than a defined reference (SCC's empty-seed fixture; see above) — those
  are asserted separately in `tests/tReferenceRejections.m` with no
  agreement claim.
- **Bounded deviation (17):** FCA, SWS (their own dedicated sections
  above), FBL, FCF, FDG, FDM, FDMV, FGA, FGAD, FGMRG, FLS, FMMCF, FOMT,
  FSN, FVMI, SFM, SNC.
  Runs the same ITK filter with the same parameters, but does not
  reproduce the original bit-for-bit; the difference is measured and
  bounded (`tests/tReferenceBounded.m`, plus FCA/SWS/FOMT's own dedicated
  suites), not merely asserted to exist. FOMT sits in this tier because
  its uint8 output at N&ge;2 is a real, measured residual; its
  floating-point output and uint8 N=1 are still asserted bit-identical
  by `tests/tFomtReference.m` (see its own section above). A validated
  badge would overstate the uint8 multi-threshold agreement, and the
  status ladder never conflates tiers. FMMCF and SFM (Epic 3 Phase 1)
  each have exactly one captured fixture (double only): FMMCF's residual
  (RMS 1.60, max 43.3, 33% of voxels) is a real numerics drift, the same
  class as FCA/SWS; SFM's residual (RMS 6.1e-15, max 9.0e-14) is at the
  floating-point noise floor, with its 270838 sentinel-valued voxels
  matching the original exactly — see their own `StatusNote`s in
  `src/opcodes/fmmcf.cpp` / `src/opcodes/sfm.cpp`.
- **Smoke-tested (1):** FAAB. Its disagreement with the
  original is large enough (RMS in the hundreds) that pinning a bound
  would not be a useful signal — see "SWS and FAAB: not bounded" below.

**Worst measured deviation per bounded-deviation opcode** (excluding FCA
and SWS, which have their own dedicated measurement tables above). This is
a summary, not a substitute for the per-fixture numbers: every literal
bound actually asserted by a test lives in `tests/tReferenceBounded.m`
(re-measure with `tools/classify_fixtures.m`, never hand-edit either).
Split by pixel-type class where the worst case differs meaningfully
between classes; "exact" in the Notes column means that class has at
least one captured point with NO deviation (asserted in
`tests/tReferenceExact.m` instead), so the opcode's bounded-deviation
status reflects its OTHER captured points, not that class.

| Opcode | Worst RMS | Worst max-abs | Notes |
|---|---|---|---|
| FDG | 0.287 (int32) | 2.0 (int32) | double/single ≤4.1e-3 |
| FGA | 0.287 (int32) | 2.0 (int32) | alias of FDG; same numbers |
| FGAD | 11.7 (uint8) | 55.0 (uint8) | double ≤0.35, single ≤7.6e-3, int32 1.27/5.0 |
| FCF | 7.28 (uint8) | 130.0 (uint8) | double at noise floor; int32 1.72/21.0 |
| FBL | 5.0e-13 (double) | 5.2e-12 (double) | int32/single/uint8 exact |
| FSN | 1.7e-15 (double) | 2.8e-14 (double) | one point; every other captured point exact |
| FVMI | 0.514 (double/single) | 10.05 (double) | int32/uint8 0.494/10.0; no exact points captured |
| FGMRG | 2.7e-7 (double) | 5.4e-6 (double) | single at noise floor too; int32/uint8 exact at sigma=2 |
| FLS | 98.7 (uint8) | 255.0 (uint8) | double/single at noise floor; int32 exact at sigma=2 |
| FDM | 0.218 (uint8) | 6.0 (uint8) | double/single/int32 exact |
| FDMV | 11.4 (uint8) | 255.0 (uint8) | double at noise floor (~3e-12); single/int32 exact |
| FMMCF | 1.60 (double) | 43.3 (double) | only one fixture (double); uint8/int32 unmeasured |
| SFM | 6.1e-15 (double) | 9.0e-14 (double) | floating-point noise floor; only one fixture (double); uint8/int32 unmeasured |
| SNC | 73.3 (double) | 255.0 (double) | radius [1,1,1] and base-threshold fixtures exact |

The remaining 8 opcodes are catalogued in `docs/matitk_opcode_registry.txt`
(the original binary's own parameter dump)
and mapped to modern ITK classes in `docs/itk_opcode_mapping.md`,
but they are **not implemented**.
See the README for the current status of each.

## SWS and FAAB: not bounded

`SWS` (its own dedicated section above) and `FAAB` disagree with the
original by enough that a bound would not mean what a bound is supposed to
mean: a number close to the current, real measurement, tight enough that a
regression trips it. `FAAB`'s measured RMS ranges from about 108 to 145
across its captured fixtures (`faab_*`), with essentially the entire
volume differing in several cases (`ndiff` at or near 442368/442368) —
`AntiAliasBinaryImageFilter`'s own level-set numerics evolved enough
between ITK 2.4 and 5.x that the two runs are not the same computation in
any useful sense on this data. Per project policy, `tests/
tReferenceBounded.m` deliberately excludes `FAAB` rather than assert a
bound that would only ever measure "still roughly this different," not
"still the same algorithm." `FAAB` stays smoke-tested; the measured
numbers above are the honest record, not a target.

## Opcode-to-ITK-class reference

This table covers all 32 implemented opcodes regardless of tier (it
predates the validated/bounded-deviation/smoke-tested split above, and is
kept as a single reference rather than split three ways).

| Opcode | ITK class |
|---|---|
| FAAB | `AntiAliasBinaryImageFilter` |
| FBB | `BinomialBlurImageFilter` |
| FBD | `BinaryDilateImageFilter` |
| FBE | `BinaryErodeImageFilter` |
| FBL | `BilateralImageFilter` |
| FBT | `BinaryThresholdImageFilter` |
| FCF | `CurvatureFlowImageFilter` |
| FD | `DerivativeImageFilter` |
| FDG | `DiscreteGaussianImageFilter` |
| FDM | `DanielssonDistanceMapImageFilter` (distance output) |
| FDMV | `DanielssonDistanceMapImageFilter` (Voronoi output; see below) |
| FF | `FlipImageFilter` |
| FGA | `DiscreteGaussianImageFilter` (see below) |
| FGAD | `GradientAnisotropicDiffusionImageFilter` |
| FGM | `GradientMagnitudeImageFilter` (see "FGM vs FGMRG" below) |
| FGMRG | `GradientMagnitudeRecursiveGaussianImageFilter` (see "FGM vs FGMRG" below) |
| FLS | `LaplacianRecursiveGaussianImageFilter` |
| FMEAN | `MeanImageFilter` |
| FMEDIAN | `MedianImageFilter` |
| FMMCF | `MinMaxCurvatureFlowImageFilter` |
| FSN | `SigmoidImageFilter` |
| FVBIH | `VotingBinaryIterativeHoleFillingImageFilter` |
| FVMI | `HessianRecursiveGaussianImageFilter` + `Hessian3DToVesselnessMeasureImageFilter` |
| SCC | `ConfidenceConnectedImageFilter` |
| SCT | `ConnectedThresholdImageFilter` |
| SFM | `FastMarchingImageFilter` |
| SIC | `IsolatedConnectedImageFilter` |
| SNC | `NeighborhoodConnectedImageFilter` |
| SOT | `OtsuThresholdImageFilter` |

**FGA is implemented as a deliberate duplicate of FDG.** Both opcodes have the
identical registry parameter signature (`gaussianVariance`, `maxKernelWidth`;
see `docs/matitk_opcode_registry.txt`), and no other ITK class matches that
parameter shape, so `mexitk` implements `FGA` as the same
`itk::DiscreteGaussianImageFilter` `FDG` uses. Whether the 2006 binary shipped
two genuinely distinct filters under these names is unconfirmed against
MATITK source, since none was available; it is most likely an artifact of the
original's Perl generator producing one entry per ITK example file. This is
flagged, not silently assumed.

**`FBD` copies non-foreground input through unchanged; `FBE` writes
`NonpositiveMin` only where erosion removed foreground.** These are two
different behaviors, not one shared rule; measured against the reference
volume, not assumed. `itk::BinaryDilateImageFilter` only ever writes the
dilate value to newly-covered background pixels — every other output pixel,
including untouched background, is the original input value unchanged, so
`unique(out)` really is `[0 255]` on a `{0,255}` input. `itk::BinaryErodeImageFilter`
only writes `itk::NumericTraits<PixelType>::NonpositiveMin()` (0 for `uint8`,
`INT_MIN` for `int32`, `-realmax` for `float`/`double`) to pixels that *were*
foreground in the input but got eroded away; original background keeps its
input value unchanged too. Measured on an `int32` run: output values are
exactly `{INT_MIN, 0, 255}`, and `count(INT_MIN) == 58499`, exactly equal to
`nnz(input==255) - nnz(output==255)`, i.e. the count of eroded-away
foreground voxels. `mexitk` leaves `BackgroundValue` at ITK's default for
both filters, matching the original's flat parameter list, which sets only
the dilate/erode value. Despite the differing mechanism, the safe comparison
is the same for both: test `== 255` (or whatever
`ValueOverWhichDilateWillApply`/`ValueOverWhichErodeWillApply` was), never
`== 0`, since a `{0,255}` input can still produce a literal 0 as an
unmodified background value on either filter;
`tests/tPhase2MorphologySmoke.m` follows this convention throughout.

**`FDM`/`FDMV` compute distance in `float` and saturate into an integral
input's own pixel type on export.** `itk::DanielssonDistanceMapImageFilter`
is instantiated with its distance-map output at `float` regardless of input
pixel type (its own Voronoi-map output stays at the input pixel type, since
Voronoi labels are drawn from input values and are always in range).
Distance can exceed an integral `PixelT`'s range even on modest volumes
(measured: an all-zero `uint8` input on the reference volume's 128x128x27
geometry yields distances ranging roughly 294 to 443 across the volume,
every one of them past `uint8`'s 255 max; the saturated output is uniformly
255 only because the whole field exceeds the clamp ceiling), and casting an out-of-range value into an integral
type is undefined behaviour in C++, not merely lossy. `mexitk` saturates via
`ClampExport` before the narrowing export; see deliberate
deviation 8 below. In-range distances are unaffected: clamp-then-truncate
equals truncate when the value already fits, matching the original's
same-pixel-type codegen for in-range results.

**`FDMV`'s accessor identification is provisional**, quoted verbatim from
`FdmvOpcode::StatusNote()` (`src/opcodes/fdm.cpp`) so the two cannot drift
apart silently:

> runs and returns plausible output; no reference capture exists. The "V =
> Voronoi (not Vector) map" accessor identification rests on secondary
> sourcing (a Vincent Chu opcode table) and is unconfirmed against MATITK
> source; itk::DanielssonDistanceMapImageFilter also exposes a distinct
> third accessor, GetVectorDistanceMap(), on the same class. See
> docs/itk_opcode_mapping.md (FDMV, Drift/risk).

The underlying sourcing is in `docs/itk_opcode_mapping.md` (FDMV, Drift/risk;
confidence Medium).

### Seed coordinate convention

`SCT`, `SCC`, `SNC` and `SIC` all take seed points through the existing
`seed(s)Array` argument (`[d1 d2 d3 d1 d2 d3 ...]`, 1-based). Each triplet
maps onto image axes in dimension order with **no transpose**: `(d1,d2,d3)`
becomes ITK index `(d1-1,d2-1,d3-1)`, the same convention `ImportVolume`
already uses for the volume itself (MATLAB's column-major layout lines up
with ITK's fastest-varying-first buffer order with no transpose needed).
This is an interpretation, not a confirmed fact: it is consistent with the
import convention, but MATITK source was not available to verify it
directly. The shared helper is `SeedPointsToIndices` in
`src/mexitk_common.h`.

A fractional coordinate truncates toward zero (`70.9` behaves as `70`),
matching `CastParam`'s truncation philosophy used everywhere else in this
codebase; in-range truncation behaviour is unaffected by anything below.
Out-of-range coordinates, and non-finite coordinates (`NaN`, `Inf`), both
raise `mexitk:seeds` before any value is cast to an index. The two cases
share one identifier deliberately, rather than splitting non-finite seeds
off under a different one: `SeedPointsToIndices` validates every
coordinate in the `double` domain first (finite, and truncates into
`[1, size(axis)]`) and only casts a value already proven to fit. This
replaced an earlier version that only rejected `s < 1.0` in central
validation (`mexFunction`) and then cast unconditionally inside the
helper, which was undefined behaviour for `NaN`/`Inf` (both compare false
against `s < 1.0`, an IEEE unordered comparison, so they passed that check)
and for huge finite coordinates (overflowing `itk::IndexValueType` on the
raw cast) — refusing to reproduce that undefined behaviour rather than
letting a malformed seed silently corrupt an index is the same policy
already applied to parameter casts (deviation 5).

### SCT ReplaceValue is inferred

The registry exposes no `ReplaceValue` parameter for `SCT`
(`docs/matitk_opcode_registry.txt` lists only `LowerThreshold`,
`UpperThreshold`), and ITK's own `ConnectedThresholdImageFilter` default is
`1`, not `255`. `mexitk` hardcodes `255`, inferred from the ITK 2.4
`Examples/Segmentation/ConnectedThresholdImageFilter.cxx` the original was
generated from, which hardcodes exactly that value. This is an inference
from the generator's source example, not a confirmed fact about MATITK
itself.

### SIC two-seed split and isolation-failure flag

`SIC` (`IsolatedConnectedImageFilter`) needs two seed *groups*, but the
calling convention supplies one flat `seedsArray`. `mexitk` splits it: the
first point becomes seed group 1 (the region to keep), the second becomes
seed group 2 (the region to isolate from), matching the two-seed shape of
the ITK 2.4 example the original was generated from. Any further points are
ignored. Fewer than two points is rejected with `mexitk:SIC:seeds` before
reaching ITK (which would otherwise throw `"Seeds1/Seeds2 container is
empty"` from `Update()`).

**Bounds-checking applies only to the two consumed points, not ignored
extras.** `SeedPointsToIndices` is called on a slice containing only the
first two triplets, so a malformed or out-of-bounds third-or-later point is
never validated and never raises an error. This is a deliberate lead
decision: the original never read anything past the second seed point, so
rejecting a call over an out-of-bounds point the original would have simply
ignored would accept *strictly less* than the original did.

`GetThresholdingFailed()` exists on the ITK filter but is deliberately not
surfaced to the caller: the ITK 2.4 example the original was generated from
never checks it, so surfacing it would be behaviour the original never had.
If the two seed regions cannot be isolated (no separating threshold found
by ITK's internal binary search), the practical symptom is that seed
group 1 itself comes back unlabelled; measured directly (a mid-band second
seed, value 40, against a bright first seed, value 68, failed to isolate on
the reference volume this way), not merely inferred.

### SOT inside/outside defaults and polarity

**This section originally documented an unverified assumption that Epic 2
Phase 3's reference captures disproved.** `SOT` had no reference capture
when it was first written; the claims below (ITK's own default values,
inherited unchanged from 2.4) turned out to be wrong on two independent
points once real `sot_*` fixtures existed to check against. See "Second
capture campaign: Phase 3 findings" above for the full story; this section
now states what was actually measured.

`SOT` (`OtsuThresholdImageFilter`) sets `InsideValue`/`OutsideValue`
explicitly: inside = `0`, outside = a FIXED `255` on every pixel type —
NOT the pixel type's own max as ITK's own default and this document
previously assumed (which would give `realmax('double')` &asymp; `1.8e308`
on `double`). Every captured `sot_*` fixture, double included, has unique
output `{0,255}`. `255` matches the fixed mask-value convention used
throughout the original's other segmentation opcodes (`SCT`'s inferred
`ReplaceValue=255`, `SNC`/`SIC`'s `ReplaceValue` default of 255).
Threshold polarity is also the opposite of ITK's own default: `255` is
assigned to the **high side** of the Otsu cut (`intensity > threshold`),
not the low side. Both fixes make `SOT` bit-exact against every captured
fixture, across all four pixel types (`tests/tReferenceExact.m`). Bins are
always set explicitly (`filter->SetNumberOfHistogramBins(...)`), since
ITK's base default (256) disagrees with MATITK's own hint (128), and the
histogram bounds are forced to the image's actual min/max via
`SetAutoMinimumMaximum(true)` — ITK 5.4's own default otherwise uses the
full `uint8` TYPE range `[0,255]` instead of the data range, shifting the
computed threshold (measured: 33.867 on the type range vs. the correct
32.3125 over this project's reference volume, whose data spans `[0,88]`).

**`numberOfHistogram` below 2 crashes MATLAB outright** and is rejected
before reaching ITK; see deliberate deviation 9 above.

**SOT vs FOMT agreement is measured, not assumed, and is now exactly 1.**
`SOT` (`OtsuThresholdImageFilter`) labels the HIGH side of its Otsu cut;
`FOMT` at N=1 (`OtsuMultipleThresholdsImageFilter`) labels the LOW side
(class 0) of its own. Before the histogram-range fix above, the two
classes' internally-computed thresholds differed by up to one bin edge
(measured pre-fix on the reference volume at 128 bins, `uint8`: agreement
0.997542769821, 441281 of 442368 voxels, every one of the 1087
disagreeing voxels at intensity exactly 33). The same fix that made `SOT`
bit-exact against the original ALSO pulled its threshold onto the exact
value `FOMT` already used: agreement is now measured at EXACTLY 1.0
(442368 of 442368 voxels, `sotHigh` the exact complement of `fomtLow`).
`tests/tPhase3RegionGrowingSmoke.m`'s `sotMatchesFomtSingleThreshold`
asserts the exact equality now, not the old bound.

**Pixel-type promotion, opcode by opcode.** Most opcodes in this table run
natively at all four supported classes (`double`, `single`, `uint8`,
`int32`); no promotion. Two groups deviate:

- **Signedness-promoted (one opcode): `FD`.** ITK's `DerivativeImageFilter`
  requires a signed output pixel type (`Concept::Signed<OutputPixelType>`),
  which `uint8` fails and `int32`/`float`/`double` satisfy. So `FD` promotes
  `uint8` input to `float` for the derivative and casts back on the way
  out. `FD` is the only opcode in this project where the float requirement
  is *concept-enforced* (a compile-time check); everywhere else it is
  documented-only or the class's own internals are hardwired to a float
  type regardless of what compiles. The original rejects `uint8`/`int32`
  input outright regardless (deviation 14), so this promotion is only ever
  exercised on an input the original never accepted in the first place —
  no agreement claim is made about its result.
- **Float-promoted with clamp-back export (seven opcodes): `FCA`, `FGAD`,
  `FCF`, `FGMRG`, `FLS`, `FAAB`, `FVMI`.** Integral (`uint8`/`int32`) input
  promotes to `float`; the result exports back through `ClampExport`
  (deviation 8), which saturates rather than performing the undefined-behaviour
  narrowing cast a plain `itk::CastImageFilter` would. None of these seven
  has a concept check that forces a floating-point pixel type: `FCA`/`FGAD`
  share `AnisotropicDiffusionImageFilter`'s documented-only requirement
  ("these filters expect images of real-valued types"); `FCF`/`FAAB` are
  documented-only in the same way (`CurvatureFlowImageFilter`'s "TOutputImage's
  pixel type must be a real number type"; `AntiAliasBinaryImageFilter`'s
  "should be a real valued scalar type"); `FGMRG`/`FLS`/`FVMI`'s classes have
  no float-related concept check at all, but hardwire
  `InternalRealType = float` internally and end their pipelines in a raw
  narrowing cast that `mexitk` replaces with the same clamp policy.
  `double`/`single` input runs natively in every case (no promotion needed).
  Epic 2 Phase 3 captured integral reference fixtures for six of these
  seven (all but `FAAB`, whose disagreement is too large to bound
  meaningfully — see "SWS and FAAB: not bounded" above). `FCF`/`FGAD`/
  `FVMI` on `uint8`/`int32` show a measured, bounded residual against the
  original at every captured point, generally much larger on `uint8` than
  on `int32` (see `tests/tReferenceBounded.m` for exact numbers per
  opcode). `FGMRG` and `FLS` are partial exceptions, NOT covered by that
  "all show a residual" claim: both were captured at only one integral
  point (sigma=2), and at that point `FGMRG`'s `int32` AND `uint8` output
  is bit-identical to the original (see `tests/tReferenceExact.m`), while
  `FLS`'s `int32` output is bit-identical but its `uint8` output has a
  large residual (`uint8`'s clamp-to-0 export of the signed field
  amplifies a small numeric difference into many sign flips near the zero
  crossing — see "FAAB and FLS" below). The promotion target being
  `float` rather than `double` is confirmed correct by these captures for
  all five opcodes named in this paragraph; `FAAB` remains unverified in
  that specific respect, same caveat as before.

## FGM vs FGMRG: same conceptual quantity, different algorithms

`FGM` (`GradientMagnitudeImageFilter`) and `FGMRG`
(`GradientMagnitudeRecursiveGaussianImageFilter`) both compute a gradient
magnitude, but `mexitk` does **not** implement `FGMRG` as a smoothed version
of `FGM`, or either as an approximation of the other: they are genuinely
different algorithms (central differences vs. a recursive Gaussian
derivative), each faithful to its own original ITK class. Their outputs
differ by design; `fgmrgDiffersFromFgm` in
`tests/tPhase4GradientsSmoke.m` asserts this directly rather than assuming
it.

`FGM` is not one of the seven float-promoted opcodes above: its computation
stays fully native for every input type, `uint8`/`int32` included —
`GradientMagnitudeImageFilter` is instantiated directly on the input pixel
type, never on a promoted `float`. Only the *export* differs by type.
`itkGradientMagnitudeImageFilter.hxx` accumulates in
`NumericTraits<InputPixelType>::RealType`, which is `double` for both
`uint8` and `int32` (confirmed directly from the ITK header, not assumed).
For `uint8`, that `double` accumulation was always narrowed back with a
plain, safe cast: the worst-case gradient magnitude on a `uint8` volume is
bounded by roughly 220.9 (measured 76.21 on the reference volume), both
under `uint8`'s 255 max, so no fix was needed there — `FGM`'s `uint8` path
is bit-identical before and after this change. `int32`'s native narrowing
cast had no such bound and could overflow, so `int32` now instantiates
`GradientMagnitudeImageFilter<Image3<int32_t>, Image3<double>>` and exports
through `ClampExport<int32_t, double>` (deviation 8) instead of casting back
natively. Because `ClampExport`'s in-range path performs the identical
`static_cast` ITK's own filter would, this changes no in-range `int32`
result either; verified with an independent bit-compare (0 mismatches
across all 442368 voxels of the reference volume, both `uint8` and `int32`).

## FAAB and FLS: signed output, clamped on integral export

`FAAB` (`AntiAliasBinaryImageFilter`) outputs "a level set image of real,
signed values. ... Values outside the zero level set are negative and
values inside the zero level set are positive"
(`itkAntiAliasBinaryImageFilter.h:82-85`). Measured on the reference volume
(binarized at intensity 33, the Phase 3 Otsu cut): the double-precision
output ranges -3 to 3, with 98.5% of foreground voxels positive and 97.2%
of background voxels negative (the remainder sit near the estimated
zero-crossing surface, expected for a level-set method). On `uint8`, the
signed-to-unsigned clamp-back export (deviation 8) means the entire
outside-negative half of the level set saturates to 0: measured, 72.8% of
`uint8` output voxels are exactly 0, and that `uint8`-zero set agrees with
the double path's non-positive set on 94.97% of voxels. This is a large,
deliberate, and now-documented consequence of the existing clamp policy,
not a new deviation.

`FLS` (`LaplacianRecursiveGaussianImageFilter`) is signed for the same
reason a second derivative is signed: measured on the reference volume at
sigma 2, output ranges -10.22 to 9.50. The `uint8` clamp-back export was
checked against the exact arithmetic
(`uint8(floor(min(max(single_path_output, 0), 255)))`) and matched exactly,
0 mismatches across all 442368 voxels.

**That 0-mismatch figure is an internal self-consistency check against
`mexitk`'s own `single`-precision path, not agreement with the original**
— `FLS` had no reference capture when it was written. Epic 2 Phase 3
captured real `fls_*` fixtures and measured agreement with the original
directly: double/single/int32 have a residual at the floating-point noise
floor (RMS order 1e-8 to 1e-7, int32 itself bit-exact at sigma=2), the
same class of ITK-numerics evolution documented throughout this file, but
`uint8` (`fls_2_uint8`) disagrees on 67150/442368 voxels, RMS about 98.7,
max absolute difference 255 — vastly larger than the floating-point-noise
residual on the other three types. The mechanism: `ClampExport`'s
zero-saturation of the signed field's negative half (deviation 8) is
itself faithful to what a genuinely matching computation would produce,
but it also AMPLIFIES the tiny cross-version numeric difference into a
binary sign flip at every voxel sitting near the zero crossing, since a
value that moved from `+1e-7` to `-1e-7` between ITK versions clamps to
two very different `uint8` outputs (`0` vs. its unclamped positive value)
instead of two nearly-identical ones. See `tests/tReferenceBounded.m` for
the exact assertion.

`FCF` (`CurvatureFlowImageFilter`) is not itself signed the way `FAAB`/
`FLS` are (it smooths intensity, it does not compute a derivative), but
its `uint8` export shows the same qualitative pattern for a related
reason: ITK's own curvature-flow numerics evolved between 2.4 and 5.x
(the same story as `FCA`), and `uint8`'s float-promoted, `ClampExport`-
narrowed path amplifies that small numeric drift far more than double/
single's native, unclamped path does. Measured against `fcf_*` fixtures:
double is at the floating-point noise floor (RMS order 1e-15), single is
small (RMS order 1e-7), but `uint8` (`fcf_10_0p0625_uint8`) disagrees on
164726/442368 voxels, RMS about 7.28, max absolute difference 130; int32
(`fcf_10_0p0625_int32`) disagrees on 161257/442368 voxels, RMS about
1.72, max absolute difference 21. See `tests/tReferenceBounded.m` for the
exact assertions on both.

## FVMI: two filters, one opcode

`FVMI`'s three registry parameters land on two different ITK filters:
`SetSigma` on `HessianRecursiveGaussianImageFilter`, `SetAlpha1`/`SetAlpha2`
on `Hessian3DToVesselnessMeasureImageFilter`. The second stage hardcodes its
input type as `Image<SymmetricSecondRankTensor<double,3>,3>`
(`itkHessian3DToVesselnessMeasureImageFilter.h:76-78,85`), and the first
stage's *default* second template argument is
`Image<SymmetricSecondRankTensor<NumericTraits<PixelType>::RealType,Dim>,Dim>`;
since `NumericTraits<float>::RealType` and `NumericTraits<double>::RealType`
are both `double`, that default already produces exactly the double-tensor
image the second stage requires, whether the first stage's own pixel type
is `float` (the promoted path) or `double` (the native path). No explicit
tensor-image instantiation is needed. The Hessian stage additionally
computes its own recursive passes in `InternalRealType = float` regardless
of the image's own pixel type; that is ITK's own internal design, not
something `mexitk` chooses. Non-vessel voxels are exactly 0 by construction
(`itkHessian3DToVesselnessMeasureImageFilter.hxx:87`); measured on the
reference volume at `[1 0.5 2]`, 249505 of 442368 voxels are exactly 0.

### `SCSS`: will not support

**Decision: `SCSS` will not be implemented.** This is settled; please do not re-open it
without new information.

`SCSS` is not a segmentation filter in the modern sense.
It maps to `itk::bio::CellularAggregate`, which:

- lives in `ITKBioCell`, an opt-in *remote* module that is not part of a default ITK build,
  so supporting it would impose an extra dependency on everyone building mexitk;
- produces **mesh** output rather than an image,
  so it cannot satisfy the MATITK contract of returning image volumes through the same
  calling convention;
- carries global static state, which is hostile to a MEX file that is loaded once and
  called repeatedly inside a long-lived MATLAB session.

There is no modern ITK filter that is behaviourally equivalent.
Shipping something merely *similar* under the name `SCSS` would be worse than not
shipping it: callers would get silently different results under a familiar name,
which is exactly the failure mode this project exists to avoid.
Calling `mexitk('SCSS', ...)` returns an unknown-operation error, which is the honest answer.

### Other opcodes needing resolution before implementation

- **`FGMS`** could not be pinned to any ITK class name with confidence
  and needs verification against the original binary before implementation.
- **`FFFT`**: the VNL FFT backend was removed from ITK and rerouted via pocketfft;
  the real/complex output switch semantics are unconfirmed.
- **`RD`**: `SetStandardDeviations` is silently inert unless `SmoothDisplacementFieldOn()`
  is also called, a real silent-failure trap to avoid inheriting.
