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
| 8 | **Out-of-range filter *results* saturate to the target pixel type's range on export, instead of an undefined-behaviour cast.** `FCA`/`FD`'s promoted (`uint8`/`int32`) paths and `FDM`'s integral-input distance output export via `itk::ClampImageFilter` rather than `itk::CastImageFilter`. Deterministically reachable: `FDM` on an all-zero `uint8` volume computes a distance of about 443 everywhere, which exceeds `uint8`'s 255 max, so the plain cast back was undefined behaviour, not merely lossy. | Refuse to reproduce undefined behaviour; the original's behaviour on these exact inputs was undefined, not reproducible even in principle, so there is nothing to match. In-range results are unaffected: clamp-then-truncate equals truncate when the value already fits, so this changes no previously-defined output. |

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

`mexitk` currently implements **17 of the original's 40 opcodes**:
FCA, FOMT, SWS, and the 14 smoke-tested filters FBB, FBD, FBE, FBT, FD, FDG,
FDM, FDMV, FF, FGA, FMEAN, FMEDIAN, FSN and FVBIH.
FCA, FOMT and SWS are the three NFT depends on, and the only three with
reference data; the other 14 have no captured reference (see "Smoke-tested
opcodes" below).
The remaining 23 are catalogued in `docs/matitk_opcode_registry.txt`
(the original binary's own parameter dump)
and mapped to modern ITK classes in `docs/itk_opcode_mapping.md`,
but they are **not implemented**.
See the README for the current status of each.

## Smoke-tested opcodes (no reference)

FBB, FBD, FBE, FBT, FD, FDG, FDM, FDMV, FF, FGA, FMEAN, FMEDIAN, FSN and
FVBIH run and return plausible output, but no reference capture exists for
them: the only captured reference is the 2006 MATITK binary's FCA/FOMT/SWS
output (see "The reference" above), so there is nothing to measure these 14
against. There are no measurement tables for them, unlike FCA and SWS above,
because there is no reference to measure against.

| Opcode | ITK class |
|---|---|
| FBB | `BinomialBlurImageFilter` |
| FBD | `BinaryDilateImageFilter` |
| FBE | `BinaryErodeImageFilter` |
| FBT | `BinaryThresholdImageFilter` |
| FD | `DerivativeImageFilter` |
| FDG | `DiscreteGaussianImageFilter` |
| FDM | `DanielssonDistanceMapImageFilter` (distance output) |
| FDMV | `DanielssonDistanceMapImageFilter` (Voronoi output; see below) |
| FF | `FlipImageFilter` |
| FGA | `DiscreteGaussianImageFilter` (see below) |
| FMEAN | `MeanImageFilter` |
| FMEDIAN | `MedianImageFilter` |
| FSN | `SigmoidImageFilter` |
| FVBIH | `VotingBinaryIterativeHoleFillingImageFilter` |

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
geometry yields a distance of about 443 everywhere, an order of magnitude
past `uint8`'s 255 max), and casting an out-of-range value into an integral
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

**One pixel-type deviation: FD promotes `uint8` to `float`.** ITK's
`DerivativeImageFilter` requires a signed output pixel type
(`Concept::Signed<OutputPixelType>`), which `uint8` fails and
`int32`/`float`/`double` satisfy. So `FD` promotes `uint8` input to `float`
for the derivative and casts back on the way out, mirroring FCA's
promote-and-cast-back pattern but keyed on signedness rather than
floating-pointness. The other 8 opcodes in this table run at the native input
pixel type for all four supported classes (`double`, `single`, `uint8`,
`int32`); no promotion.

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
