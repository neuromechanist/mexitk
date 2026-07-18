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

## FOMT: bit-identical for floating-point input

`FOMT` reproduces the original **exactly**, bit for bit,
for `double` and `single` input
at N = 2 (50 bins), N = 3 (128 bins) and N = 4 (100 bins).
Those cover every threshold count NFT uses.

`uint8` input does **not** match exactly:
outputs disagree on roughly 0.2% of voxels
(for example 755 of 442,368 voxels on output 2 at N=2).
ITK changed how integral pixel types are binned into the Otsu histogram since 2.4.
The disagreement is asserted to stay under 2% by `tests/tFomtReference.m`.

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
| 8 | **Out-of-range filter *results* saturate to the target pixel type's range on export, instead of an undefined-behaviour cast.** `FCA`/`FD`'s promoted (`uint8`/`int32`) paths and `FDM`'s integral-input distance output export via `itk::ClampImageFilter` rather than `itk::CastImageFilter`. Deterministically reachable: `FDM` on an all-zero `uint8` volume computes distances measured at roughly 294 to 443 across the volume, all past `uint8`'s 255 max, so the plain cast back was undefined behaviour, not merely lossy. | Refuse to reproduce undefined behaviour; the original's behaviour on these exact inputs was undefined, not reproducible even in principle, so there is nothing to match. In-range results are unaffected: clamp-then-truncate equals truncate when the value already fits, so this changes no previously-defined output. |
| 9 | **`SOT` rejects `numberOfHistogram < 2`** with `mexitk:SOT:numberOfHistogram`, instead of running ITK's Otsu calculator. Measured directly, not assumed: 0 or 1 histogram bins crash the whole MATLAB process (a bus error / SIGSEGV inside `itk::Statistics::Histogram::GetIndex`), not a catchable `itk::ExceptionObject`. `numberOfHistogram >= 2` is unaffected. | Same severity class as deviation 1 (`SWS` overthresholding): taking down the user's MATLAB session is not behaviour worth preserving, and there is no reference capture for a crashing call to match against in the first place. |
| 10 | **Non-finite or wildly out-of-range seed coordinates raise `mexitk:seeds` instead of casting with undefined behaviour.** `SeedPointsToIndices` (`SCT`/`SCC`/`SNC`/`SIC`) validates every coordinate as a finite `double` truncating into `[1, size(axis)]` before casting to an ITK index. `NaN`/`Inf` previously passed central validation's `s < 1.0` check unrejected (an IEEE unordered comparison, false for both) and then hit a raw cast; a huge finite coordinate overflowed `itk::IndexValueType` on that same cast. Both are undefined behaviour in C++, and the overflow case was platform-dependent in a way that stayed hidden on one architecture: ARM64's saturating convert masked it (the garbage result still failed the old bounds check), but x86 wrapped to `INT64_MIN`, where the following `-1` base shift was a second, independent signed-overflow UB. In-range values, including fractional truncation (`70.9` behaves as `70`), are unaffected. | Same rationale as deviation 5: the original's behaviour on these exact inputs is unknown and unreproducible, and reproducing undefined behaviour on purpose is not a defect worth keeping. One identifier (`mexitk:seeds`) covers both the non-finite and out-of-range cases deliberately, rather than splitting non-finite seeds off under `mexitk:paramRange`. |

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

`mexitk` currently implements **30 of the original's 40 opcodes**:
FCA, FOMT, SWS, the 22 smoke-tested filters FAAB, FBB, FBD, FBE, FBL, FBT,
FCF, FD, FDG, FDM, FDMV, FF, FGA, FGAD, FGM, FGMRG, FLS, FMEAN, FMEDIAN,
FSN, FVBIH and FVMI, and the 5 smoke-tested segmentation opcodes SCC, SCT,
SIC, SNC and SOT.
FCA, FOMT and SWS are the three NFT depends on, and the only three with
reference data; the other 27 have no captured reference (see "Smoke-tested
opcodes" below).
The remaining 10 are catalogued in `docs/matitk_opcode_registry.txt`
(the original binary's own parameter dump)
and mapped to modern ITK classes in `docs/itk_opcode_mapping.md`,
but they are **not implemented**.
See the README for the current status of each.

## Smoke-tested opcodes (no reference)

FAAB, FBB, FBD, FBE, FBL, FBT, FCF, FD, FDG, FDM, FDMV, FF, FGA, FGAD, FGM,
FGMRG, FLS, FMEAN, FMEDIAN, FSN, FVBIH, FVMI, SCC, SCT, SIC, SNC and SOT
run and return plausible output, but no reference capture exists for them:
the only captured reference is the 2006 MATITK binary's FCA/FOMT/SWS output
(see "The reference" above), so there is nothing to measure these 27
against. There are no measurement tables for them, unlike FCA and SWS
above, because there is no reference to measure against.

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
| FSN | `SigmoidImageFilter` |
| FVBIH | `VotingBinaryIterativeHoleFillingImageFilter` |
| FVMI | `HessianRecursiveGaussianImageFilter` + `Hessian3DToVesselnessMeasureImageFilter` |
| SCC | `ConfidenceConnectedImageFilter` |
| SCT | `ConnectedThresholdImageFilter` |
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
`itk::ClampImageFilter` before the narrowing export; see deliberate
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

`SOT` (`OtsuThresholdImageFilter`) leaves `InsideValue` and `OutsideValue`
at ITK's own defaults: inside = the pixel type's max, outside = `0`. The
registry exposes neither parameter, and both the ITK 2.4 constructor and
the 5.4 `HistogramThresholdImageFilter` base agree on this default, so
leaving it alone matches the original's own behaviour, not a choice mexitk
made. Threshold polarity is unchanged 2.4-to-5.4 too: intensity in
`[min, otsuThreshold]` receives `InsideValue`, i.e. the **low side** of the
Otsu cut becomes inside. Consequence: the two-valued output is `{0,255}` on
`uint8` but `{0,realmax('double')}` &asymp; `{0, 1.8e308}` on `double`
(`{0,realmax('single')}` &asymp; `{0, 3.4e38}` on `single`). This is ITK's
faithful default, not a bug, and is flagged loudly rather than silently
"fixed" to `{0,255}`. Bins are always set explicitly
(`filter->SetNumberOfHistogramBins(...)`), since ITK's base default (256)
disagrees with MATITK's own hint (128).

**`numberOfHistogram` below 2 crashes MATLAB outright** and is rejected
before reaching ITK; see deliberate deviation 9 above.

**SOT vs FOMT agreement is measured, not assumed, and is not exactly 1.**
`SOT` (`OtsuThresholdImageFilter`) and `FOMT` at N=1
(`OtsuMultipleThresholdsImageFilter`) both label the low side of a single
Otsu cut, so their partitions should nearly match, but the two classes use
different histogram/threshold calculators internally and can pick a
threshold differing by up to one bin edge. Measured on the reference volume
at 128 bins, `uint8`: agreement is **0.997542769821** (441281 of 442368
voxels), not exactly 1. Every one of the 1087 disagreeing voxels has
intensity exactly 33, consistent with the two calculators landing on
threshold values one bin edge apart. `tests/tPhase3RegionGrowingSmoke.m`
asserts the measured bound (`agree > 0.997`), not equality, per project
policy: the number is measured, not invented or tuned to pass.

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
  type regardless of what compiles.
- **Float-promoted with clamp-back export (seven opcodes): `FCA`, `FGAD`,
  `FCF`, `FGMRG`, `FLS`, `FAAB`, `FVMI`.** Integral (`uint8`/`int32`) input
  promotes to `float`; the result exports back through `itk::ClampImageFilter`
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
  None of the seven has any integral reference capture, so the promotion
  target (`float`, not `double`) is unverified against the original by
  construction, same caveat as `FCA`'s own `StatusNote`.

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
