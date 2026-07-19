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
| 12 | **Every opcode with a raw floating-point parameter now rejects non-finite (`NaN`/`+-Inf`) input**, each with its own specific `mexitk:<OPCODE>:<param>` identifier **except `FOMT`'s two**, which route through the shared `CastParam<int>` validation and so surface as the generic `mexitk:paramRange` for every non-finite value, never `FOMT`'s own `mexitk:FOMT:numberOfThresholds`/`numberOfBins` ids (those stay reserved for in-range-but-semantically-invalid values, e.g. `numberOfThresholds = 0`) — closing a project-wide gap discovered during Epic 3 (Phase 1 review found it in `FMMCF`; a systematic survey of every remaining opcode, tracked as issue #26, found the identical defect class in ten more). The root cause is the same everywhere: a guard written as `<= 0.0` / `== 0.0` / `< 0.0` is silently false for `NaN` (every ordered comparison against `NaN` is false) and does not reject `+Inf` either, so a value that was supposed to be rejected instead reached the filter. Each parameter's guard was verified empirically (an isolated run per parameter, not inferred from reading the code) before being fixed, and the fix never tightens beyond the non-finite case: an existing sign/range constraint (`<= 0.0`, `== 0.0`) keeps its own exact semantics, gaining only the missing `!std::isfinite(...)` check; a parameter with no prior constraint gets that check alone, nothing more. **Twenty parameter instances across fourteen opcodes are covered** (counting convention, so the number is checkable: `FDG`'s and `FGA`'s `gaussianVariance` guards count as two instances, since each carries its own identifier despite sharing one C++ guard function; `FOMT`'s `numberOfThresholds` and `numberOfBins` likewise count as two, despite sharing `mexitk:paramRange` as their non-finite identifier): `FCA`/`FCF`/`FGAD`/`FMMCF` `timeStep` (Epic 3 Phase 1; `-Inf` was already caught by the pre-existing `< 0.0` guard on all four, so only `NaN`/`+Inf` were the actual gap); `FBL` `domainSigma`/`rangeSigma`; `FDG`/`FGA` `gaussianVariance` (one shared guard function fixes both opcodes); `FSN` `alpha` (kept its `== 0` constraint) and `beta` (had none); `FLS` and `FGMRG` `sigma` (each already had ITK's own `<= 0.0` exception for the sign case, which — unlike the `timeStep` family's `< 0.0` guards above — DOES already cover `-Inf` too, since `-Inf <= 0.0` is a well-ordered true comparison, unlike `NaN`; only `NaN`/`+Inf` were the actual pre-PR gap, but the new mexitk-level guard now intercepts `-Inf` first as well, since it runs before either filter ever dispatches, so `-Inf` surfaces as `mexitk:FLS:sigma`/`mexitk:FGMRG:sigma` instead of the pre-PR `mexitk:itkException` — a deliberate, disclosed identifier change for an input that was already rejected, not a new rejection); `FVMI` `SetSigma`/`SetAlpha1`/`SetAlpha2` (no prior constraint on any of the three); `SCC` `multiplier` (no prior constraint); `SWS` `level`/`threshold` (no prior constraint; the "0.0-1.0" registry hint is documentation only, not an enforced range, and stays that way); `FOMT` `numberOfThresholds`/`numberOfBins` (a different repair, below). Observed severity, measured per opcode and per parameter rather than assumed uniform: most silently return an all-`NaN` output with no exception (`FCF`; `FCA`'s own `NaN` case; `FGAD`; `FBL`'s `domainSigma`/`rangeSigma`; `FDG`/`FGA`; `FLS`; `FGMRG`; `FSN`'s `alpha` and `beta` on `double` input; `FVMI`'s `SetAlpha1`/`SetAlpha2`), the same class as deviation 11 (`FBL`'s own pre-existing silent-`NaN` guard); `FSN`'s `alpha` on `uint8` input is a distinct manifestation of the same underlying gap, not another all-`NaN` case: a silent all-zero output via the undefined-behaviour native cast deviation 7 already documents for `alpha == 0`, since `FSN` has no promote-and-`ClampExport` path to intervene; some parameters instead silently return a degenerate all-zero or empty-looking result (`FVMI`'s `SetSigma`, `SCC`'s `multiplier`, `SWS`'s `level`/`threshold` for five of six non-finite combinations — the sixth, `SWS` `threshold=+Inf`, was already caught, by luck rather than design, by an internal ITK consistency check inside `WatershedSegmentTreeGenerator`); `FCA`'s own `+Inf timeStep` case is a mixed `NaN`/`Inf` output, not uniformly one or the other; `FMMCF` is the outlier and the most severe of all of them, crashing the whole MATLAB process with a `SIGBUS` inside `MinMaxCurvatureFlowFunction::ComputeThreshold`'s `Dispatch<3>` path for both `NaN` and `+Inf` `timeStep` — the same severity class as deviation 1 (`SWS` overthresholding) and deviation 9 (`SOT` histogram bins), not the milder silent-corruption class every other opcode here shares. `FOMT`'s `numberOfThresholds`/`numberOfBins` are a genuinely different repair, not just another instance of the pattern above: both previously reached a raw `static_cast<int>` of a `double` with **no validation at all**, in three separate places (`OutputCount()`, `Execute()`, and `RunFomt()` itself) — actual standard-mandated undefined behaviour for a non-finite or out-of-`int`-range value, not merely an ITK-internal silent-`NaN` propagation. This was masked, not fixed, by luck on this project's own development platform: ARM64's saturating float-to-`int` conversion happens to produce `0` for `NaN`, caught downstream only via the ordinary `nargout` mismatch path, with no such guarantee on other platforms this project targets (x86 has its own, differently-undefined conversion behaviour — the same class of platform divergence already documented for `SeedPointsToIndices` in `mexitk_common.h`). All three casts now route through `CastParam<int>` instead, which was also the point where a second, structural gap surfaced and was fixed in the same pass: `mexFunction` (`src/mexitk.cpp`) calls `OutputCount()` *before* the `try`/`catch` block that wraps `Execute()`, so a `CastParam`-thrown `OpcodeError` from inside `OutputCount()` would have been an uncaught C++ exception crossing the `extern "C" mexFunction` boundary — undefined behaviour in its own right, and in practice an abort taking the whole session down, the same failure mode as `FMMCF`'s crash, just introduced fresh rather than inherited. `OutputCount()`'s own call site now has its own `try`/`catch`, mirroring `Execute()`'s. Three deliberate exceptions to this project-wide rule, all confirmed empirically to be genuinely benign, not merely unexamined: `FAAB`'s `maximumRMSError` is a convergence threshold checked each iteration as "has the RMS change dropped below this?"; a `NaN` value makes that comparison always false, so early stopping simply never fires and the solver runs its full `numberOfIterations` instead — verified bit-identical to a call using an extremely small but finite threshold that also never triggers (not merely "didn't crash"), with a measured negative control confirming the threshold genuinely matters on this data (the registry default, `0.01`, DOES trigger early stopping and produces a measurably different result: 73157/442368 voxels differ). `FF`'s `XDIRECTION`/`YDIRECTION`/`ZDIRECTION` are compared with `!= 0.0` to produce a boolean flip flag, a well-defined IEEE comparison (`NaN != 0.0` and `Inf != 0.0` are both `true`) with no numeric ITK computation downstream at all. `SFM`'s `stoppingTime` passes `CastParam<double>` through unguarded by design (Epic 3 Phase 1): a negative value stops marching at the seed's own first heap pop (defined); `NaN` is never exceeded by the stopping check, so marching runs to its own natural exhaustion instead of stopping early (also defined, and distinct from "every voxel loses its sentinel" — voxels with no finite-speed path from a seed stay at the sentinel regardless of `stoppingTime`, a property of the speed image, not of this parameter). | Same rationale as deviation 5: refuse an input whose original behaviour cannot be reproduced or verified, while leaving every previously-defined value unaffected — the sign/range constraint an opcode already enforced keeps its exact prior meaning, `timeStep == 0` and similar defined edge cases are untouched, and the three benign passthroughs stay unguarded because there is nothing undefined about them to refuse. `FMMCF`'s case is closer to deviation 1/9's rationale: taking down the user's MATLAB session is not behaviour worth preserving regardless of what the original would have done. `FOMT`'s repair is closer to deviation 10's rationale (`SeedPointsToIndices`'s own seed-casting fix): undefined behaviour that happened to look safe on one platform is not safe, and is not something to leave relying on luck once identified. |
| 13 | **`FDM`/`FDMV` reject an all-background input** (no nonzero voxel anywhere) with `mexitk:fdm:noObject`. Measured directly against the `fdm_zero_double`/`fdm_zero_uint8` fixtures, where the original itself succeeded: an all-zero `uint8` input yields distances of roughly 294 to 443 across this project's reference geometry, every one of them past `uint8`'s 255 max and, on every pixel type, not a meaningful answer to "distance to the nearest object" when there is no object — an artifact of the distance filter's internal initialization, not a defined computation. | Same severity/rationale class as deviation 5: the original's own output for this input is not a value worth reproducing, since "distance to the nearest of zero objects" has no defined answer. Refusing it is a strict subset of accepted inputs; every volume with at least one nonzero voxel is unaffected. |
| 14 | **`FD` accepts `uint8` and `int32` input; the original rejects both outright** with "This method is not supported with this data type! Try converting to double first.", regardless of parameters (measured directly against `fd_0_0_uint8`/`fd_1_0_uint8`/`fd_1_0_int32`, where the original itself failed). `mexitk` promotes `uint8` to `float` for the derivative (`itk::DerivativeImageFilter` requires a signed output pixel type, which `uint8` fails) and runs `int32` natively, returning a defined result for both. No agreement claim is made about the VALUE `mexitk` returns for these two pixel types — the original never produced one to compare against — only that the call succeeds; see `tests/tReferenceRejections.m`. | Accept strictly more, the same direction as deviation 2 (string objects): every call that worked against the original still works and still matches; `uint8`/`int32` input, which the original refused unconditionally, now succeeds instead of erroring. Nothing about the original's own defined behaviour (double/single) changes. |
| 15 | **`RD` rejects `NumberOfHistogramLevels < 1`** with `mexitk:RD:NumberOfHistogramLevels`, instead of running `HistogramMatchingImageFilter`. Measured directly, not assumed: `NumberOfHistogramLevels = 0` segfaults the whole MATLAB process (a crash dump shows the fault inside `itk::HistogramMatchingImageFilter::ConstructHistogramFromIntensityRange`, called from `BeforeThreadedGenerateData`, called from `RdOpcode::Execute`), not a catchable `itk::ExceptionObject`. Traced to `itkHistogramMatchingImageFilter.hxx`: `histogram->SetBinMax(0, m_NumberOfHistogramLevels - 1, imageTrueMaxValue)` computes `0 - 1` on an unsigned `SizeValueType`, underflowing to `SIZE_MAX`, and writes out of the histogram's actual bin range — an out-of-bounds write. `CastParam<itk::SizeValueType>` (`src/mexitk_common.h`) already rejects non-finite and negative values for this parameter, but 0 is a perfectly valid `SizeValueType` and passes that check untouched, so a separate semantic guard is needed. The threshold is exactly 1, verified empirically rather than assumed or chosen for a safety margin: `NumberOfHistogramLevels = 1` was run in isolation and confirmed to complete normally (finite `128x128x27` output), before this bound was written. `NumberOfHistogramLevels >= 1` is unaffected. | Same severity class as deviation 1 (`SWS` overthresholding) and deviation 9 (`SOT` histogram bins): taking down the user's MATLAB session is not behaviour worth preserving, and there is no reference capture for a crashing call to match against in the first place. The guard refuses only the measured defect (0), not a wider margin invented around it, the same discipline as deviation 9's own `>= 2` bound for `SOT`. |
| 16 | **`SCSS` registers and appears in `mexitk('?')`, but `Execute()` always throws `mexitk:SCSS:unsupported`**, refusing every call regardless of parameters. Confirmed against the captured fixture (`scss_scss_20_60_10_seedS1_double`): the original itself succeeded, and its own output is a `[10 1]` column of ones (one entry per `AdvanceTimeStep()` iteration), not an image of any size or shape `mexitk`'s calling convention could return under this name. | Refuse to reproduce an output-type mismatch mexitk's own calling convention cannot represent honestly: the original's own result for this opcode is not an image, and shipping an image-shaped substitute under the `SCSS` name would look like agreement where none exists — worse than refusing outright. See "`SCSS`: formally unsupported (Epic 4 Phase 2)" below for the full rationale. |

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

`mexitk` currently implements **39 of the original's 40 opcodes**, and formally
disposes of the fortieth (`SCSS`) as unsupported rather than leaving it silently
absent -- all 40 are addressed. Epic 2 Phases 1-3 extended the capture harness
to 30 of them, captured reference fixtures for every one, and measured
`mexitk`'s own agreement against every fixture (`tools/classify_fixtures.m`;
see "Second capture campaign: Phase 3 findings" above for how). Epic 3 Phase 1
added `FMMCF` and `SFM`; Epic 3 Phase 2 added `SGAC`, `SLLS`, and `SSDLS` --
the first opcodes to genuinely consume a second image volume (`inputArray2`)
rather than accept-and-ignore it. Epic 4 Phase 1 added `RD` and `RTPS`, the
first `Category::kRegistration` opcodes -- see "RD and RTPS: the first
registration opcodes" below. `RTPS`'s own initial fixture was a rejection
only; two follow-up reference-host capture rounds (`s14`, nine more fixtures)
then settled its calling convention, supplied eight successful captures, and
isolated the exact cause of its two initially-unexplained residuals, promoting
it out of smoke-tested. Epic 4 Phase 2 closed out the roadmap: `FGMS` is
implemented as a registry duplicate of `FGMRG` (fixture-confirmed
bit-identical in the original); `FFFT`'s packing was fully determined by a
follow-up controlled capture round (`s15`) after the original two (mri-sized)
fixtures alone proved insufficient, and carries a real, measured, bounded
residual on those two fixtures even with the confirmed packing (investigated
down to independently proving this codebase's own FFT computation exact, not
left as an open question); and `SCSS` is registered with a deliberate refusal
-- see "`SCSS`: formally unsupported (Epic 4 Phase 2)" and "`FGMS` and `FFFT`:
resolved (Epic 4 Phase 2)" above. All ten opcodes from Epic 3 and Epic 4
(FMMCF, SFM, SGAC, SLLS, SSDLS, RD, RTPS, FGMS, FFFT, SCSS) have their own
captured fixture(s), measured the same way. The status ladder now splits the
40 into four tiers by that measurement, not by guesswork:

- **Validated (15):** FBB, FBD, FBE, FBT, FD, FF, FGM, FMEAN, FMEDIAN,
  FVBIH, SCC, SCT, SGAC, SIC, SOT.
  Bit-identical to the original on every comparable captured fixture
  (`tests/tReferenceExact.m`).
  "Comparable" excludes fixtures where the original itself rejected the
  call, or where a captured fixture is a non-reproducible artifact rather
  than a defined reference (SCC's empty-seed fixture; see above) — those
  are asserted separately in `tests/tReferenceRejections.m` with no
  agreement claim.
- **Bounded deviation (23):** FCA, SWS (their own dedicated sections
  above), FBL, FCF, FDG, FDM, FDMV, FFFT, FGA, FGAD, FGMRG, FGMS, FLS,
  FMMCF, FOMT, FSN, FVMI, SFM, SLLS, SNC, SSDLS, RD, RTPS.
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
  `src/opcodes/fmmcf.cpp` / `src/opcodes/sfm.cpp`. SLLS and SSDLS (Epic 3
  Phase 2) also each have exactly one captured fixture (double only):
  SLLS's residual (280/442368 voxels, 0.063%, each within 0.077 of the
  zero crossing) is the floating-point noise floor of a 50-iteration
  finite-difference solver flipping a boundary voxel's sign after
  thresholding, not an algorithmic difference; SSDLS's residual (RMS
  6.7e-8, max-abs 5.25e-6, on its raw un-thresholded output) is the same
  noise-floor category as SFM's — see their own `StatusNote`s in
  `src/opcodes/slls.cpp` / `src/opcodes/ssdls.cpp`. RD (Epic 4 Phase 1)
  also has exactly one captured fixture (double only): its residual (RMS
  4.63626, max-abs 88 -- the full 0-88 input intensity range -- on
  173173/442368 voxels, 39.1%) is far above the floating-point noise
  floor, a real numerics difference in the iterative Demons solver, the
  same category as FCA/FMMCF rather than SFM/SLLS/SSDLS's noise-floor
  category -- see "RD and RTPS: the first registration opcodes" below and
  `src/opcodes/rd.cpp`'s own `StatusNote`. RTPS (Epic 4 Phase 1, `s14`
  capture round, two rounds) has eight captured fixtures (double only):
  five are at the floating-point noise floor, in two magnitude bands
  (three at RMS ~1e-12, two at RMS ~2e-10 -- not one uniform ceiling);
  the other three have a real, modest residual (RMS 2.226571, 3.647131,
  4.159985) traced specifically to fewer than 3 distinct landmark pairs,
  not coplanarity as first suspected — see "RD and RTPS: the first
  registration opcodes" below and
  `src/opcodes/rtps.cpp`'s own `StatusNote` for the full evidence,
  including how the calling convention itself was determined. FGMS (Epic
  4 Phase 2) has three captured fixtures (double only, sigma 1/2/4): the
  original's own FGMS output is bit-identical to its own FGMRG output at
  every one, so mexitk implements it as the identical filter call and
  measures the identical residual FGMRG measures against its own
  fixtures at the same sigma -- see "`FGMS` and `FFFT`: resolved (Epic 4
  Phase 2)" above and `src/opcodes/fgmrg.cpp`'s `FgmsOpcode::StatusNote`.
  FFFT (Epic 4 Phase 2, `s15` controlled-capture round) has its packing
  fully confirmed (4 of 6 small captures bit-exact, the other 2 at the
  double-precision noise floor -- see `tests/tReferenceExact.m`) but
  still shows a real, larger residual on the two original mri-sized
  fixtures despite the confirmed packing (real mode RMS 20.2/maxabs
  95.5; complex mode RMS 16121/maxabs 3.54495e6) -- independently traced
  to a genuine difference in the original's own ITK-2.4-vintage VNL FFT
  on this specific composite size, not a bug in this codebase (this
  codebase's own FFT was proven exact against MATLAB's `fftn` on the
  same volume) -- see "`FGMS` and `FFFT`: resolved (Epic 4 Phase 2)"
  above and `src/opcodes/ffft.cpp`'s `StatusNote` for the full evidence.
- **Smoke-tested (1):** FAAB. Its disagreement with the
  original is large enough (RMS in the hundreds) that pinning a bound
  would not be a useful signal — see "SWS and FAAB: not bounded" below.
- **Unsupported (1):** SCSS. Registers and appears in `mexitk('?')`, but
  `Execute()` always throws `mexitk:SCSS:unsupported` by design: the
  original's own output for this opcode is not an image (a `[10 1]`
  vector of iteration counters, fixture-confirmed), so no image-shaped
  result could be returned under this name without misleading a caller
  — see "`SCSS`: formally unsupported (Epic 4 Phase 2)" above.

**Worst measured deviation per bounded-deviation opcode** (excluding FCA,
SWS, and FOMT, each of which has its own dedicated measurement table or
section above, in FOMT's case using a different metric entirely --
per-output voxel-disagreement percentage, not RMS/max-abs, since its
deviation is a discrete multi-class labeling difference rather than a
continuous-valued one; see "FOMT: bit-identical for floating-point input,
and for uint8 at N=1" above). This is
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
| FGMS | 2.7e-7 (double) | 5.4e-6 (double) | registry duplicate of FGMRG; identical measured numbers at matching sigma; only double captured |
| FLS | 98.7 (uint8) | 255.0 (uint8) | double/single at noise floor; int32 exact at sigma=2 |
| FDM | 0.218 (uint8) | 6.0 (uint8) | double/single/int32 exact |
| FDMV | 11.4 (uint8) | 255.0 (uint8) | double at noise floor (~3e-12); single/int32 exact |
| FMMCF | 1.60 (double) | 43.3 (double) | only one fixture (double); uint8/int32 unmeasured |
| SFM | 6.1e-15 (double) | 9.0e-14 (double) | floating-point noise floor; only one fixture (double); uint8/int32 unmeasured |
| SLLS | 6.42 (double) | 255.0 (double) | 280/442368 voxels (0.063%) flip category near the zero crossing; only one fixture (double); uint8/int32 unmeasured |
| SNC | 73.3 (double) | 255.0 (double) | radius [1,1,1] and base-threshold fixtures exact |
| SSDLS | 6.7e-8 (double) | 5.3e-6 (double) | floating-point noise floor, raw un-thresholded output; only one fixture (double); uint8/int32 unmeasured |
| RD | 4.63626 (double) | 88.0 (double) | full input intensity range; only one fixture (double); uint8/int32 unmeasured |
| RTPS | 4.159985 (double) | 88.0 (double) | worst of 3 captures with fewer than 3 distinct landmark pairs; 5 well-posed (3+ distinct pairs) captures at the floating-point noise floor instead (3 at RMS ~1e-12, 2 at RMS ~2e-10); only double captured, uint8/int32/single unmeasured |
| FFFT | 16121.494 (double, complex mode) | 3544950.7 (double, complex mode) | packing confirmed exact (s15 controlled captures, 4/6 bit-exact, 2/6 at noise floor); real mode alone is much smaller, RMS 20.2/maxabs 95.5; residual independently traced to the original's own FFT on this composite (non-power-of-2) size, not this codebase (own FFT proven exact vs MATLAB fftn); only double captured, uint8/int32/single unmeasured |

All 40 opcodes are catalogued in `docs/matitk_opcode_registry.txt`
(the original binary's own parameter dump)
and mapped to modern ITK classes in `docs/itk_opcode_mapping.md`.
39 are implemented above; the fortieth, `SCSS`, is formally **unsupported**
(registered, documented, always refuses -- see "`SCSS`: formally unsupported
(Epic 4 Phase 2)" above) rather than silently absent.
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

## Bound margins for noise-floor entries

`tests/tReferenceBounded.m`'s ceiling formula gates its headroom by
magnitude, a policy ruling from Epic 4 Phase 1's PR #30 review, applied
project-wide, not a per-fixture exception, and applied identically and
independently to BOTH metrics it asserts. Below 1e-5 (relative ~1e-7 on
this project's 0-88 reference volume), the RMS ceiling is
`max(measured * 1.5, measured + 1e-12)` and the max-abs ceiling is
`max(measured * 1.5, measured + 1e-9)`; at or above 1e-5, each stays
`max(measured * 1.1, measured + <its own floor>)`, exactly the original
flat 10% rule. The gate is evaluated separately per metric, so a single
fixture can have its RMS gated while its max-abs is not (or vice versa)
if the two measured values straddle the 1e-5 threshold -- this is
correct, not an inconsistency: RMS and max-abs are different
measurements of the same output and are not guaranteed to sit in the
same regime. Only the ASSERTION MARGIN changed. No measured value in
`tests/tReferenceBounded.m`'s `Cases` table changed because of this
policy, and it is not a relaxation of "never loosen a tolerance to make
a test pass": the entries it widens are not being reproduced any
differently than before, and the entries it does not touch (any real
algorithmic disagreement, however small, in either metric) keep exactly
the tight margin they always had.

**Why the gate exists.** A measured RMS below 1e-5 on this project's
data is presumptively floating-point/library noise, not a real
algorithmic difference: several opcodes here (`RTPS`'s
`ThinPlateSplineKernelTransform`, and others with an internal
finite-difference or kernel solve) route through `vnl_svd` or similar
LAPACK/BLAS-backed linear algebra, whose exact last-bit result is
platform-dependent -- the same class of non-determinism this project
already documents for ITK's own 2.4-to-5.x numerics evolution, except
here the two things being compared are two runs of the SAME `mexitk`
build on different platforms, not `mexitk` versus the original. A bound
tighter than the platform variation itself does not test agreement with
the original; it tests which platform's linear-algebra library happened
to run the test.

**What was actually observed, not assumed.** `rtps_pairs3_distinct_double`
measured RMS 5.264588848e-12 on macOS arm64 and 6.78818e-12 on Linux
x86_64 -- a ~29% spread between two measurements that are both genuine
double-precision noise (see "RD and RTPS: the first registration
opcodes" above for the full writeup of that specific fixture). The prior
flat 10% margin, derived from the macOS measurement alone, did not
absorb the Linux measurement and failed CI on PR #30. A magnitude-gated
survey across every noise-floor-adjacent entry in `tests/
tReferenceBounded.m`'s `Cases` table (not just `RTPS`'s own) found 13
entries sitting at exactly the prior flat-10%-headroom floor once their
own RMS clears roughly 1e-11 (where the formula's `+1e-12` additive term
becomes negligible): `FCF`'s `fcf_10_0p0625_single`; `FGMRG`'s
`fgmrg_1_double`, `fgmrg_2_double`, `fgmrg_2_single`, `fgmrg_4_double`;
`FLS`'s `fls_1_double`, `fls_2_double`, `fls_2_single`, `fls_4_double`;
`SSDLS`'s `ssdls_ssdls_volB_seedS1_double`; `RTPS`'s
`rtps_nc5_identity_double`, `rtps_nc5_translate_double`, and
`rtps_pairs3_distinct_double` itself even after its own bound was
corrected -- all with 10-15% headroom, less than the ~29% spread already
measured on one of them. Under the 1.5x gate, all 13 now carry 50%
headroom, comfortably above the observed spread with room to spare. The
identical survey run against max-abs found the same pattern (12 of the
13 RMS-affected fixtures also have a sub-1e-5 max-abs, gaining the same
50% headroom there too; the one exception, `FCF`'s
`fcf_10_0p0625_single`, has max-abs 5.34e-05 -- just above the
threshold -- so its max-abs bound stays at 10% even though its RMS bound
is gated to 1.5x, the straddling case described above). Every entry at
or above 1e-5 in EITHER metric -- every genuine algorithmic disagreement
this project has measured, from `FGAD`'s uint8 residual through `RD`'s
Demons-solver drift to the three real-residual `RTPS` captures
(`rtps_pairs4_identity_double`, `rtps_pair1_minimal_double`,
`rtps_pairs2_distinct_double`) -- keeps exactly the 10% margin it had
before this policy, unchanged, because a real disagreement is exactly
where a tight margin is meaningful regression detection.

`rtps_pairs3_distinct_double`'s own stored RMS (6.78818e-12, the
cross-platform maximum) is kept even though the 1.5x gate alone would
now absorb the Linux measurement starting from the macOS-only value:
the cross-platform maximum is the more accurate number, and recording it
is belt-and-suspenders on top of the wider margin, not a substitute for
measuring it. A third platform's own noise-floor measurement, whatever
it turns out to be, is best compared against the most accurate value
already on file, not a smaller one kept only because a wider margin
happens to cover the two platforms measured so far.

## Opcode-to-ITK-class reference

This table covers all 37 implemented opcodes regardless of tier (it
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
| FCA | `CurvatureAnisotropicDiffusionImageFilter` |
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
| FOMT | `OtsuMultipleThresholdsImageFilter` (see "FOMT" above) |
| FSN | `SigmoidImageFilter` |
| FVBIH | `VotingBinaryIterativeHoleFillingImageFilter` |
| FVMI | `HessianRecursiveGaussianImageFilter` + `Hessian3DToVesselnessMeasureImageFilter` |
| RD | `HistogramMatchingImageFilter` + `DemonsRegistrationFilter` + `WarpImageFilter` (see "RD and RTPS" below) |
| RTPS | `ThinPlateSplineKernelTransform` + `ResampleImageFilter` (see "RD and RTPS" below) |
| SCC | `ConfidenceConnectedImageFilter` |
| SCT | `ConnectedThresholdImageFilter` |
| SFM | `FastMarchingImageFilter` |
| SGAC | `GeodesicActiveContourLevelSetImageFilter` (see "SGAC, SLLS, SSDLS" below) |
| SIC | `IsolatedConnectedImageFilter` |
| SLLS | `LaplacianSegmentationLevelSetImageFilter` (see "SGAC, SLLS, SSDLS" below) |
| SNC | `NeighborhoodConnectedImageFilter` |
| SOT | `OtsuThresholdImageFilter` |
| SSDLS | `ShapeDetectionLevelSetImageFilter` (see "SGAC, SLLS, SSDLS" below) |
| SWS | `WatershedImageFilter` (see "SWS: bounded deviation" above) |

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

### SGAC, SLLS, SSDLS: the first two-volume opcodes, roles and polarity determined empirically

`SGAC`, `SLLS`, and `SSDLS` (Epic 3 Phase 2) are the first opcodes in this
codebase where `inputArray2` is genuinely consumed rather than
accepted-and-ignored. All three wrap a classic-framework ITK level-set
segmentation filter (`itk::SegmentationLevelSetImageFilter` subclasses,
module `ITKLevelSets`), which take two image inputs with distinct roles: an
initial level set (the seed isosurface) and a feature image (the speed
function's source). `docs/matitk_opcode_registry.txt`'s own dump for these
three opcodes was captured from a zero-volume call (it only reaches the
"not enough parameters" error path), so it says nothing about role
assignment — but the original binary's own console output on a genuine
two-volume call, preserved verbatim in each opcode's captured fixture
(`consoleText`), does: **"This method requires two image volumes. Input A
will be used as feature image. Input B will be used as input A's
gradient."**, identical across all three fixtures. This corroborates that
`inputArray1` is the feature image — the same conclusion the swap-test
below reaches independently — but it does not by itself prove which ITK
setter each argument is wired to: the original's own wording, "input A's
gradient", is not the same concept as ITK's own "initial level set" role
for `SetInput()` (a gradient image and a seed isosurface are different
things), and no assumption is made here that they must mean the same
argument. The swap-test is what actually confirms the `SetInput()`/
`SetFeatureImage()` wiring below; the console text is corroborating
context for `inputArray1`'s role, not a substitute for it.

**Role assignment, the same for all three:** `inputArray1` (volume A) is the
**feature image**; `inputArray2` (volume B) is the **initial level set**.
Determined by building each opcode with the roles wired one way, running it
against the fixture's own natural argument order, and comparing; then
rebuilding with the roles swapped and comparing again. For all three
opcodes the correct assignment reproduces the fixture (bit-exact for SGAC,
within the measured bounded deviation for SLLS/SSDLS); the swapped
assignment produces a substantially different result every time — for
SGAC, a close-but-wrong match (1492-voxel difference on a ~235000-voxel
region, not exact); for SLLS, a massive difference (422527/442368 voxels
differ, a completely different segmentation, against the correct
assignment's 280/442368); for SSDLS, a massive difference (max-abs 8 vs.
5.25e-6, RMS 1.57 vs. 6.7e-8). The swapped-role numbers are recorded here,
not tuned away, specifically so a future reader can see this was verified,
not assumed uniform after the first opcode confirmed it.

**Threshold polarity is opcode-specific, not filter-generic.** `SGAC` and
`SLLS` binary-threshold their raw level-set output to `{0, 255}`; `SSDLS`
does not (see below). For the two that threshold, negative level-set values
map to 255 (inside) and non-negative values map to 0 (outside). For `SGAC`
this matches what `GeodesicActiveContourLevelSetImageFilter`'s own header
documents ("negative … inside … positive … outside") — but it does **not**
match what `LaplacianSegmentationLevelSetImageFilter`'s own header documents
for `SLLS` ("positive … inside … negative … outside", the opposite). The
documented `SLLS` polarity was tried first and was wrong by nearly the
entire volume (442088/442368 voxels differed, mean output 101 vs. the
fixture's 154); the polarity that actually matches the fixture is the same
as `SGAC`'s (negative → 255), not what `SLLS`'s own class documentation
says. This is fixture evidence overriding documented semantics, recorded
here rather than silently "fixed" to match the docstring.

**`SSDLS` alone returns the raw, un-thresholded narrow-band level set.**
Verified directly against its fixture: output range `[-4, 4]`, not `{0,
255}`. `SGAC` and `SLLS` both binary-threshold; `SSDLS` does not — three
opcodes wrapping filters from the same ITK module, with two different
output conventions, confirmed per-opcode rather than assumed from the
other two.

Full detail, including the exact measured residuals and the swapped-role
control numbers, is in each opcode's own `StatusNote()`:
`src/opcodes/sgac.cpp`, `src/opcodes/slls.cpp`, `src/opcodes/ssdls.cpp`.

### RD and RTPS: the first registration opcodes

`RD` (Demons deformable registration) and `RTPS` (thin-plate-spline
landmark warping) are Epic 4 Phase 1's two additions, the first opcodes in
`Category::kRegistration`. Both are now bounded-deviation, but `RTPS` got
there in three steps: its own first captured fixture was a rejection
only, enough to cap it at smoke-tested with an INFERRED calling
convention; `s14`'s first capture round
(`tools/capture_reference/s14_rtps_landmarks.m`, six fixtures) then
disproved that inference outright and pinned down the real one,
promoting it to bounded-deviation; `s14`'s second round (three more
fixtures) then isolated the exact cause of the two residual fixtures
round 1 left unexplained, refining -- not changing -- the status. All
three steps, including the disproven inference and the disproven
"monotonic shrink" prediction from round 2's own plan, are recorded
below, not just the final answer, because a wrong hypothesis is itself
useful evidence about what does and does not follow from "landmarks
ride the seed argument, one point is rejected, the count must be even."

**RD: fixed/moving role assignment, determined by the same swap-test
method as SGAC.** The registry (`docs/matitk_opcode_registry.txt`) gives
no role hint -- it only dumps the four numeric parameters. Built both
ways and run against `rd_demons_volB_double` (`NumberOfHistogramLevels
=1024, NumberOfMatchPoints=7, DemonNumberofIterations=150,
DemonStandardDeviations=1`, `volumeB=circshift(volumeA,[3 3 1])`): with
volumeA fixed / volumeB moving, RMS 4.63626, max-abs 88, 173173/442368
voxels differ (39.1%); with the roles swapped, RMS 21.7, 189263/442368
voxels differ (42.8%) -- clearly worse, not merely different, so
volumeA=fixed / volumeB=moving is the assignment used, though neither
wiring reaches bit-exactness. **This is a real, measured numerics
difference, not floating-point noise**: `numberOfIterations=0` is
confirmed an exact identity no-op (warping by an all-zero displacement
field returns the moving image unchanged, 0/442368 voxels differ),
ruling out a basic wiring error, so the residual traces to the Demons
solver's own 150-iteration numerics having moved between ITK 2.4 and
5.4 -- the same broad category as `FCA`/`FMMCF` (an iterative PDE-style
solver whose exact per-step arithmetic evolved upstream), not the
floating-point-noise-floor category `SFM`/`SLLS`/`SSDLS` fall into. Two
consecutive local runs were compared bit-for-bit before comparing
against the fixture at all, to rule out iterative/multithreaded
nondeterminism as a confound (registration is both); they matched
exactly. Only one fixture exists (double), so `uint8`/`int32`/`single`
carry no agreement claim; they promote to `float` internally the same as
every other promoted opcode.

**RD: which image gets warped, the original moving image or the
histogram-matched intermediate.** The classic ITK Demons registration
example (`HistogramMatchingImageFilter` feeding `DemonsRegistrationFilter`
feeding `WarpImageFilter`) warps the ORIGINAL pre-match moving image with
the resulting displacement field, using the histogram-matched image only
as the Demons filter's own input -- histogram matching is a computational
aid for registration, not something meant to survive into the final
output. `mexitk` follows that convention, but `rd_demons_volB_double`
cannot independently prove it either way: `volumeB` is
`circshift(volumeA,[3 3 1])`, so both images share EXACTLY the same
histogram (a circular shift permutes voxel positions, not values), and
histogram-matching an image against its own histogram is very close to
identity here -- measured directly, warping `matcher->GetOutput()`
instead of the original moving image produces bit-identical `mexitk`
output on this fixture. A future fixture with genuinely different
fixed/moving intensity distributions would be needed to settle this
independently; see `src/opcodes/rd.cpp`.

**`SetStandardDeviations` is silently inert unless smoothing is
explicitly enabled.** `PDEDeformableRegistrationFilter::
m_SmoothDisplacementField` default-initializes to `false`, and
`DemonsRegistrationFilter`'s own constructor never touches it -- a real
silent-failure trap, not a hypothetical one (this is why it was flagged
in `docs/itk_opcode_mapping.md` before implementation even began). `RD`
calls `SmoothDisplacementFieldOn()` explicitly; removing it would make
`DemonStandardDeviations` a parameter that is accepted, validated, and
then silently ignored.

**RTPS before `s14`: only a rejection fixture existed.** The one fixture
captured before `s14` (`rtps_tps_volB_seedS1_double`, a single seed point
`[70 50 14]`) is a FAILED capture: the original's full error text is
`This method requires landmarks.  Each landmark should be 3-dimensional,
and there should be even number of landmarks (source->target)`. This
proved three things and no more: landmarks ride the seed argument
(arg5); a single landmark point is refused; the count must be even.
`mexitk` reproduces exactly that -- `mexitk:RTPS:landmarks` on an empty
or odd-count landmark list. With no successful capture, Phase 1 shipped
an INFERENCE: landmarks split in half (a full source block then a full
target block, the Insight Software Guide's own landmark-warping worked
example), fixed/moving roles carried over from RD's own determination
(volumeA fixed, volumeB moving), and the standard source=fixed-space /
target=moving-space wiring into `ResampleImageFilter`. Status was capped
at smoke-tested accordingly, since none of that was checked against the
original.

**RTPS, `s14` round 1: the captures disproved the inference directly.**
`tools/capture_reference/s14_rtps_landmarks.m`'s first round captured six
fixtures targeting exactly the two open questions the original rejection
fixture's error text left open: does the landmark list split in half or
interleave, and which
volume does the transform resample, in which direction. One structural
finding surfaced along the way, worth recording on its own: the original
rejects a landmark argument passed as a **matrix** with `Seed array must
be a vector.` -- landmarks, like every other seed array in this
codebase, must be a flat row vector of concatenated 3-tuples, not a
2-column matrix of points.

The DECISIVE result is `rtps_nc5_identity_double`: `volumeA==volumeB`
(both the raw `mri` volume) and a landmark seed array built as
`[src5 src5]` (five well-spread, non-coplanar points, repeated). Under
Phase 1's split-half reading this is a literal identity landmark set
(source==target, 5 well-posed pairs) and the resulting warp MUST
reproduce the input exactly. It does not: measured, 181548/442368 voxels
differ (41%), output mean 2.62 against the raw volume's own mean 21.82 --
proof the split-half inference was simply wrong, not merely imprecise.
`rtps_nc5_translate_double` (same `volumeA==volumeB`, second half offset
by a fixed `[6 -4 2]` translation instead of repeated) gave the second
data point needed to diagnose it: since both `nc5_*` fixtures share the
identical FIRST-HALF/SECOND-HALF point stream structure and differ only
in whether the second half repeats or offsets, comparing candidate
readings against both together isolates the correct one. **The flat
landmark list is INTERLEAVED**
(`source1,target1,source2,target2,...`), not split into a source block
and a target block: reading `[src5 src5]` as 5 interleaved pairs gives
`(src5pt1,src5pt2), (src5pt3,src5pt4), (src5pt5,src5pt1), ...` -- NOT an
identity correspondence at all, which is exactly why the fixture named
"identity" does not reproduce the input under either reading naively
assumed identity, but DOES reproduce it under interleaved reading once
the correct fixed/moving assignment below is also used (verified
directly: RMS 2.12e-10, 20898/442368 voxels differ only at the
floating-point noise floor, not zero, because the "identical" landmark
stream is not literally an identity map, just a self-consistent one that
the original and `mexitk` now agree on bit-for-bit modulo double-precision
noise). `rtps_nc5_translate_double` confirms the same reading
independently: RMS 2.00e-10.

`rtps_pairs4_translate_double` is the DECISIVE capture for direction:
`volumeB` here is `circshift(flip(volumeA,1),[5 9 2])`, asymmetric on
purpose (flipped, not just shifted), so a source/target or fixed/moving
mixup misplaces the output visibly rather than looking coincidentally
close. **volumeB is FIXED (the source-landmark/output space) and volumeA
is MOVING (the target-landmark/input space, the one actually
resampled)** -- the OPPOSITE of `RD`'s own role assignment. With volumeB
fixed, this capture reproduces at RMS 2.63e-12 (floating-point noise
floor); with volumeA fixed (Phase 1's original, RD-consistent
assumption), RMS is 37.7 -- not a close call. Three of round 1's five
successful captures (`nc5_identity`, `nc5_translate`, `pairs4_translate`)
are therefore reproduced at the floating-point noise floor under
INTERLEAVED landmarks + volumeB-fixed/volumeA-moving, with the
source/target roles read literally (no further swap needed): this rules
out a wiring bug as the residual's source in round 1's two remaining
captures, since the wiring is identical across all five and three of
them match essentially exactly.

**Two of round 1's five captures have a real, modest, measured
residual, not a wiring problem -- and round 2's follow-up captures
isolated exactly why.** `rtps_pairs4_identity_double` (RMS 2.226571,
58566/442368 voxels differ, 13.2%) and `rtps_pair1_minimal_double` (RMS
3.647131, 100523/442368 voxels differ, 22.7%) both involve landmark
configurations that are structurally degenerate for a thin-plate spline.
The first hypothesis tried here was coplanarity: `pairs4_identity`'s
four interleaved pairs collapse to only TWO distinct (source,target)
pairs, each supplied twice (verified directly, pair 1 equals pair 3 and
pair 2 equals pair 4 exactly), built from a coplanar 4-point source set.
A second capture round (`s14`, round 2: `rtps_coplanar3_distinct_double`,
`rtps_pairs2_distinct_double`, `rtps_pairs3_distinct_double`) tested this
directly and DISPROVED it: `rtps_coplanar3_distinct_double` (3 DISTINCT
pairs, sources coplanar, no duplication) reproduces EXACTLY (RMS
8.146892e-13) -- coplanarity alone is not the cause.
`rtps_pairs3_distinct_double` (3 distinct, well-spread, non-coplanar
pairs) is likewise exact -- **RMS 5.264589e-12 on macOS arm64, 6.78818e-12
on Linux x86_64**, a ~29% spread between two measurements that are BOTH
genuine double-precision noise (relative to the 0-88 intensity range,
each is roughly 1e-13). `ThinPlateSplineKernelTransform`'s `ComputeWMatrix`
solves its augmented system via `vnl_svd`, which runs through each
platform's own LAPACK/BLAS; the two platforms do not agree on the exact
noise-floor residual, only on its ORDER of magnitude. The bound asserted
in `tests/tReferenceBounded.m` is the MAXIMUM of the two measurements
(6.78818e-12), not the macOS-only value this project first measured and
shipped in PR #30 -- CI caught the gap when Linux's own run (6.78818e-12)
exceeded the macOS-derived bound (ceiling 6.2646e-12, about 8% under)
by exercising a platform this project had not yet measured this specific
fixture against. This is completing an under-measured bound with a
second platform's own data, not raising one to hide a real disagreement
with the original: no comparison against the original binary moved,
only the recorded floor of platform-dependent SVD noise grew to reflect
a measurement that already existed in reality and simply had not been
taken yet. `rtps_pairs2_distinct_double` (only 2 distinct pairs), by
contrast, has a real residual
(RMS 4.159985, comparable in kind to `pair1_minimal`'s single pair).
**The threshold is the number of DISTINCT landmark pairs: 3 or more
reproduces exactly (regardless of coplanarity), fewer than 3 leaves a
real, measured residual.** This also explains `pairs4_identity`
precisely: its 4 landmark pairs carry only 2 pieces of DISTINCT
information (the duplication), the same effective count as
`pairs2_distinct`, and its residual is the same order of magnitude.
All of this is consistent with ITK's SVD-based pseudo-inverse resolving
an underdetermined augmented least-squares system slightly differently
between 2.4 (the original's 2006 build) and 5.4 once fewer than 3
distinct correspondences are available to constrain it -- the same
upstream-numerics-evolution category as `FCA`/`SNC`/`SWS` elsewhere in
this project, not tuned away, measured and asserted as-is in
`tests/tReferenceBounded.m`. Five captures spanning coplanar and
non-coplanar, identity and translation, and symmetric and asymmetric
volumes all reproduce exactly under the identical wiring, which rules
out a systematic wiring error as the source of the remaining three
residuals.

**This is a threshold, not a gradual improvement -- a disproven
assumption worth recording explicitly, the same way `FDMV`'s accessor
guess and `SOT`'s inside-value default are recorded above once
measurement contradicted them.** Round 2's own plan predicted the
residual would shrink monotonically as distinct-pair count rose from 1
toward 4+; it does not. The full sequence, ordered by distinct-pair
count: 1 pair (`pair1_minimal`, RMS 3.647131), 2 pairs
(`pairs2_distinct`, RMS 4.159985 -- WORSE than 1 pair, not smaller), 3
pairs (`pairs3_distinct`, RMS 5.26e-12 on macOS/6.79e-12 on Linux --
suddenly at the noise floor, platform-dependent order of magnitude and
all), 5 pairs (`nc5_identity`/`nc5_translate`, RMS ~2e-10 -- still at
the noise floor). Agreement does not improve gradually as more distinct
pairs are added; it steps from "real, measured residual" to
"floating-point noise floor" the moment 3 distinct pairs are reached,
with no smooth transition through 2.

`rtps_odd3_reject_double` (three landmarks, captured in `s14`'s first
round alongside its five successes) is a second rejection fixture,
confirming the even-count requirement independently of the original,
pre-`s14` single-seed rejection; both rejections are asserted in
`tests/tReferenceRejections.m`.

**RTPS's status is now bounded-deviation, not smoke-tested.** Eight
successful fixtures exist across the two `s14` rounds (all double only;
`uint8`/`int32`/`single` carry no agreement claim and promote to `float`
internally, same as every other promoted opcode). The internal identity
self-check Phase 1 used as a stand-in for reference evidence
(`volumeA==volumeB` with matching source/target landmarks reproduces the
input exactly) still holds, but now under the CORRECT interleaved
reading -- a landmark list built from repeated `(p_i, p_i)` pairs, not
Phase 1's `[p1 p2 ... pN p1 p2 ... pN]`, which the `s14` captures proved
is not an identity map at all under the real convention.

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

### `SCSS`: formally unsupported (Epic 4 Phase 2)

**Decision: `SCSS` is registered but deliberately refused, not implemented.**
This closes out the earlier "will not support" plan with a captured fixture and a
real disposition, rather than leaving the opcode silently absent from the registry.

`SCSS` is not a segmentation filter in the modern sense.
It maps to `itk::bio::CellularAggregate`, which:

- lives in `ITKBioCell`, an opt-in *remote* module that is not part of a default ITK build,
  so supporting it would impose an extra dependency on everyone building mexitk;
- produces **mesh** output rather than an image,
  so it cannot satisfy the MATITK contract of returning image volumes through the same
  calling convention;
- carries global static state, which is hostile to a MEX file that is loaded once and
  called repeatedly inside a long-lived MATLAB session.

A reference-host capture (Epic 4 Phase 2, `scss_scss_20_60_10_seedS1_double`) confirms this
directly rather than leaving it inferred: the original itself ran without error on
`SCSS([20 60 10], V, [], S1)`, and its own captured output is a `[10 1]` column of ones, one
entry per `AdvanceTimeStep()` iteration (`numberOfIterations=10`) — a vector of iteration
counters, not an image of any size or shape `mexitk`'s calling convention expects.

There is no modern ITK filter that is behaviourally equivalent.
Shipping something merely *similar* under the name `SCSS` would be worse than not
shipping it: callers would get silently different results under a familiar name,
which is exactly the failure mode this project exists to avoid. `SCSS` is registered with
`Status::kUnsupported` (`src/opcode.h`) — it appears in `mexitk('?')` like every other
opcode, so a caller can discover it exists and why it refuses, but `Execute()` always throws
`mexitk:SCSS:unsupported` with the rationale above. This is a deliberate refusal, not the
generic `mexitk:unknownOpcode` error an unregistered name would produce, and not a
placeholder for a future implementation: per this project's core honesty principle, a
plausible-looking image-shaped substitute under this name would be strictly worse than
refusing. See `src/opcodes/scss.cpp` and `tests/tReferenceRejections.m`'s
`scssRefusesDespiteOriginalSuccess`.

### `FGMS` and `FFFT`: resolved (Epic 4 Phase 2)

Both were left open after the initial mapping pass; both are now resolved with fixture
evidence rather than left as "needs verification":

- **`FGMS`**: reference-host capture (`fgms_sigma1_double`, `fgms_sigma2_double`,
  `fgms_sigma4_double`) settles the question the mapping pass could not: the original's own
  `FGMS` output is bit-identical to its own `FGMRG` output at every captured sigma
  (`isequal` plus an independent hash check, not merely close). `mexitk` implements `FGMS` as
  the same `GradientMagnitudeRecursiveGaussianImageFilter` call as `FGMRG` (`src/opcodes/
  fgmrg.cpp`), the same registry-duplicate situation as `FGA`/`FDG`, and measures the
  identical residual against these fixtures as `FGMRG` measures against its own (RMS
  2.73366e-07 at sigma=1, 1.32290e-07 at sigma=2, 7.13001e-08 at sigma=4 — the
  floating-point noise floor). Status: **bounded deviation**.
- **`FFFT`**: the concrete `itk::VnlForwardFFTImageFilter` (not the abstract, object-factory-
  resolved `ForwardFFTImageFilter` the mapping pass pointed at, which fails to instantiate on
  this build with no PocketFFT backend compiled in) runs cleanly on all four pixel types. The
  packing was initially undetermined from the original two (mri-sized) fixtures alone — one
  inline guess from that first pass was directly disproven, not just unconfirmed:
  `ffft_complex1_double`'s own extreme value (±3543768.099) is NOT the DC component of the
  volume's FFT (the true DC term, computed directly, is 9650539 — the sum of all voxel
  intensities). A follow-up controlled reference-host capture round (`s15`:
  `tools/capture_reference/s15_ffft_packing.m`, three small 8x8x8 volumes with analytically
  known spectra) then settled the packing exactly, not by inference: **Real mode (param 0)
  = the REAL PART of the full 3-D forward FFT, rescaled to [0,255]; Complex mode (param 1) =
  the IMAGINARY PART, raw and unscaled.** Proof: an impulse one voxel off-origin has a
  real/imaginary phase-ramp spectrum in closed form, and its real-mode fixture is exactly
  that rescaled to [0,255] (maxabs 2.84e-14); an impulse at the origin has a constant,
  purely-real spectrum, and its real-mode fixture is exactly all-zero, matching
  `RescaleIntensityImageFilter`'s own documented min==max collapses to `OutputMinimum`
  behaviour — and ruling out magnitude (the earlier top candidate) decisively, since
  magnitude is *also* constant for the off-origin impulse (only phase varies), which would
  wrongly all-zero that case too. The captures also forced one correction nobody predicted in
  advance: `itk::VnlForwardFFTImageFilter`'s own raw imaginary part is the *exact negation* of
  the original's (confirmed: `mexitk_output + fixture == 0` to floating-point noise, not
  merely `mexitk_output - fixture` being small), so Complex mode negates post-hoc via
  `ShiftScaleImageFilter`. 4 of the 6 `s15` fixtures are bit-exact; the other 2 (the two
  impulse cases' real-mode outputs) are at the absolute double-precision noise floor
  (~1e-14/1e-15). The two *original* mri-sized fixtures still do not match closely even with
  the now-confirmed packing (real mode RMS 20.2/maxabs 95.5 against `[0,255]`; complex mode
  RMS 16121/maxabs 3.54495e6 against a fixture ranging ±3.54377e6) — investigated, not left
  unexplained: this codebase's own ITK-native FFT was independently verified mathematically
  EXACT (RMS 1.8e-11) against MATLAB's own `fftn` on the real 128×128×27 volume, ruling out
  every hypothesis that would implicate this implementation specifically (axis-order
  mismatch — tested via all 6 permutations, all land at the same ~1e-11 floor; `z=27`
  radix-3 mixed-radix mishandling — the one prime factor the cubic, power-of-2-only `s15`
  captures never exercise; an unapplied `fftshift` — already ruled out at small scale; and
  size-driven zero-padding — ruled out by reading `itkVnlForwardFFTImageFilter.hxx` directly,
  which explicitly *rejects* illegal sizes via `VnlFFTCommon::IsDimensionSizeLegal` rather
  than padding them, and 27=3³ is a legal, unpadded radix-3 size). With this implementation's
  own FFT independently proven exact, the residual is best explained as a genuine difference
  between the original 2006 binary's own ITK-2.4-vintage VNL FFT and modern ITK's, specific to
  this composite (non-power-of-2) size — the same category of real, measured, bounded
  numerics difference as `FCA`/`RD`, not floating-point noise, and not something the
  power-of-2-only `s15` captures could have revealed even in principle. Status: **bounded
  deviation**, scoped to `double` (`single`/`uint8`/`int32` promote to a real type the same
  way but carry no fixture of their own). See `src/opcodes/ffft.cpp`'s `StatusNote` for the
  full evidence trail, `tests/tReferenceExact.m`/`tests/tReferenceBounded.m` for the
  assertions, and `tools/capture_reference/s15_ffft_packing.m` for the capture script.
