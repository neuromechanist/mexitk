# mexitk

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21405977.svg)](https://doi.org/10.5281/zenodo.21405977)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](LICENSE)

A MATLAB to ITK bridge: call [ITK](https://www.itk.org) (Insight Segmentation and Registration Toolkit)
image filters from MATLAB through a MEX interface.

`mexitk` is a clean-room reimplementation of the *calling convention* of
**MATITK** (Vincent Chu and Ghassan Hamarneh, Simon Fraser University, 2005-2006),
which is abandoned, has no public source, no licence, and no Apple Silicon build.
Existing MATITK callers work unchanged.

## Why this exists

MATITK ships Intel-only MEX binaries.
There is no `mexmaca64`, and MEX files cannot run under Rosetta:
they must match MATLAB's own architecture.
So on Apple Silicon, which is the only Mac platform MathWorks supports from R2026a onward,
anything depending on MATITK is simply dead.

The immediate case is [NFT](https://github.com/sccn/NFT),
an EEG head-modeling EEGLAB plugin whose MRI segmentation path calls `matitk`.
The general case is that a useful bridge to ITK's filter library
should not be unmaintainable and unbuildable.

The alternative, rewriting on MATLAB's Image Processing Toolbox,
was considered and rejected:
its equivalents are *different algorithms* and would silently change segmentation output.
Keeping ITK keeps the algorithms.

## Status: honest summary

This is version 0.4.0.
**30 of the original's 40 opcodes are implemented.**
Epic 2 (Phases 1-3) extended reference capture to all 30 and measured every one of them
against the original binary; the table below reflects that measurement, produced by
`tools/classify_fixtures.m`.
Every claim in the table is enforced by the test suite
(`tests/tReferenceExact.m`, `tests/tReferenceBounded.m`,
`tests/tReferenceRejections.m`, plus the dedicated FCA/FOMT/SWS suites):
721 tests, run green in CI on Linux x86_64 and macOS arm64
for the tree this table describes.

| Opcode | ITK filter | Status | What that means |
|---|---|---|---|
| `FBB` | `BinomialBlurImageFilter` | **validated** | Bit-identical to the original on every captured fixture (4 of 4, all four pixel types). |
| `FBD` | `BinaryDilateImageFilter` | **validated** | Bit-identical to the original on every fixture it itself accepted (7 of 8 captured, all four pixel types); the eighth is a deliberate out-of-range rejection. Non-foreground output is the original input value, unchanged. |
| `FBE` | `BinaryErodeImageFilter` | **validated** | Bit-identical to the original on every captured fixture (7 of 7, all four pixel types). |
| `FBT` | `BinaryThresholdImageFilter` | **validated** | Bit-identical to the original on every fixture it itself accepted (7 of 9 captured, all four pixel types); the other two are deliberate out-of-range rejections. |
| `FD` | `DerivativeImageFilter` | **validated** | Bit-identical on every fixture the original itself accepted (double/single). `uint8`/`int32` are rejected outright by the original; `mexitk` accepts both and returns a defined result, with no agreement claim for that pair. |
| `FF` | `FlipImageFilter` | **validated** | Bit-identical to the original on every captured fixture (12 of 12, all four pixel types). `XDIRECTION`/`YDIRECTION` are axis-swapped relative to their registry order. |
| `FGM` | `GradientMagnitudeImageFilter` | **validated** | Bit-identical to the original on every captured fixture (4 of 4, all four pixel types). Zero parameters. Distinct algorithm from `FGMRG`. |
| `FMEAN` | `MeanImageFilter` | **validated** | Bit-identical to the original on every captured fixture (8 of 8, all four pixel types); every captured point is symmetric-radius, so the X/Y axis swap is family-inferred rather than independently proven for this opcode. |
| `FMEDIAN` | `MedianImageFilter` | **validated** | Bit-identical to the original on every captured fixture (10 of 10, all four pixel types). |
| `FVBIH` | `VotingBinaryIterativeHoleFillingImageFilter` | **validated** | Bit-identical to the original on every fixture the original itself accepted (9 of 10 captured); the tenth is a deliberate out-of-range rejection. |
| `SCC` | `ConfidenceConnectedImageFilter` | **validated** | Bit-identical to the original on every fixture with a genuine seed (8 of 10 captured); the empty-seed fixture is a non-reproducible session-state artifact of the original, not a defined reference (see COMPATIBILITY). |
| `SCT` | `ConnectedThresholdImageFilter` | **validated** | Bit-identical to the original on every fixture it itself accepted (14 of 17 captured); the rest are rejection/accepts-more cases. ReplaceValue hardcoded to 255 (inferred from ITK's example; registry exposes none). |
| `SIC` | `IsolatedConnectedImageFilter` | **validated** | Bit-identical to the original on every fixture with two valid seed groups (7 of 10 captured). Needs at least 2 seed points. |
| `SOT` | `OtsuThresholdImageFilter` | **validated** | Bit-identical to the original on every captured fixture (6 of 6, all four pixel types). Inside/outside are a fixed `{0,255}` on every pixel type, matching the original (not the pixel type's own max, an earlier unverified assumption). |
| `FCA` | `CurvatureAnisotropicDiffusionImageFilter` | **bounded deviation** | Not bit-identical. RMS 2.6e-3, max 4.7e-2 at 1 iteration over a 0-88 range; compounds with iterations. |
| `SWS` | `WatershedImageFilter` | **bounded deviation** | Region count matches exactly at every tested setting; label images are not bit-identical at fine levels. |
| `FBL` | `BilateralImageFilter` | **bounded deviation** | Bit-identical on int32/single/uint8; double has a floating-point-noise-floor residual (RMS order 1e-13 to 1e-12). |
| `FCF` | `CurvatureFlowImageFilter` | **bounded deviation** | Double/single at the floating-point noise floor; `uint8`/`int32` promote to `float` internally and have a much larger measured residual (RMS up to ~7.3 on uint8). |
| `FDG` | `DiscreteGaussianImageFilter` | **bounded deviation** | RMS order 1e-3 to 4e-3 on double/single/int32; `uint8` is rejected by the original outright, `mexitk` accepts it with no agreement claim. |
| `FDM` | `DanielssonDistanceMapImageFilter` (distance) | **bounded deviation** | Bit-identical on double/single/int32; `uint8` has a small measured residual (RMS ~0.2, max abs 6). All-background input is rejected (`mexitk:fdm:noObject`). |
| `FDMV` | `DanielssonDistanceMapImageFilter` (Voronoi) | **bounded deviation** | Bit-identical on single/int32; double has a floating-point-noise-floor residual, `uint8` uses a different (wraparound, not rescale) formula with its own small residual. Voronoi labels are sequential per-object ids, not drawn from the input's own pixel values (an earlier assumption, now disproven). |
| `FGA` | `DiscreteGaussianImageFilter` | **bounded deviation** | Duplicate of `FDG`, now fixture-confirmed: bit-identical to `FDG`'s own output in the original at every capturable point. Same measured deviation as `FDG`. |
| `FGAD` | `GradientAnisotropicDiffusionImageFilter` | **bounded deviation** | Gradient-conductance sibling of `FCA`. RMS order 5e-5 to 0.35 on double/single; `uint8`/`int32` promote to `float` internally with a larger residual (RMS up to ~11.7 on uint8). |
| `FGMRG` | `GradientMagnitudeRecursiveGaussianImageFilter` | **bounded deviation** | Bit-identical on int32/uint8 at sigma=2; double/single have a floating-point-noise-floor residual otherwise. Distinct algorithm from `FGM`. |
| `FLS` | `LaplacianRecursiveGaussianImageFilter` | **bounded deviation** | Bit-identical on int32 at sigma=2; double/single at the floating-point noise floor. `uint8`'s clamp-to-0 export of the signed field amplifies that tiny difference into a much larger measured residual (RMS ~98.7). |
| `FOMT` | `OtsuMultipleThresholdsImageFilter` | **bounded deviation** | Bit-identical to the original for `double`/`single` at N=2,3,4, and for `uint8` at N=1 (asserted exactly). `uint8` at N=2,3,4 deviates (0.17%/0.38%/0.84% of voxels, measured); confirmed a genuine ITK 2.4-to-5.x integral-histogram-binning difference, not the same fixable bug SOT had. |
| `FSN` | `SigmoidImageFilter` | **bounded deviation** | Bit-identical on 5 of 6 captured fixtures; the sixth has a floating-point-noise-floor residual. |
| `FVMI` | `HessianRecursiveGaussianImageFilter` + `Hessian3DToVesselnessMeasureImageFilter` | **bounded deviation** | Not bit-identical on any captured fixture; RMS 0.08-0.51, a real algorithmic drift from ITK's evolving Hessian/vesselness numerics, not noise. |
| `SNC` | `NeighborhoodConnectedImageFilter` | **bounded deviation** | Bit-identical at radius [1,1,1] and the base threshold fixtures; other radii have a measured residual independent of axis order (an upstream algorithm difference, the same class as FCA/SWS). |
| `FAAB` | `AntiAliasBinaryImageFilter` | **smoke-tested** | Runs and returns plausible output; reference fixtures exist but disagreement is too large to bound meaningfully (RMS in the hundreds). Output is a signed level-set field (positive inside). Integral input promotes to `float`; on `uint8` the negative (outside) half saturates to 0 on export. |

Status vocabulary, used consistently in the code, in `mexitk('?')`, and here:

- **validated**: reproduces the original bit-for-bit, asserted by a test against a stored reference fixture.
- **bounded deviation**: compared against a reference fixture and does *not* match bit-for-bit.
  The difference is a measured, bounded consequence of ITK's own evolution from 2.4 to 5.x,
  not a porting error. The bound is asserted by a test.
- **smoke-tested**: runs and returns plausible output, but no reference capture exists.
- **untested**: implemented from the ITK mapping only; never run against a reference.

The remaining 10 opcodes are **not implemented**.
They are catalogued in `docs/matitk_opcode_registry.txt` (the original binary's own parameter dump)
and mapped to modern ITK classes in `docs/itk_opcode_mapping.md`.

> **Comparing against an older result?**
> Output from any opcode marked **bounded deviation** above (`FCA` and `SWS` among them)
> will differ slightly from what the original `matitk` binary produced on Linux before 2026.
> Every opcode marked **validated** is identical.
> This is upstream ITK's own evolution from 2.4 to 5.4, not a porting error,
> and it is accepted deliberately: the alternative is that segmentation does not run
> on Apple Silicon at all.
> The measured magnitudes are in
> [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md#read-this-first-if-you-are-comparing-against-an-older-result).

**`docs/COMPATIBILITY.md` is the full record**: every measurement,
every quirk reproduced on purpose, and every deliberate deviation.
Read it before relying on this for science.

### Platform status

| Platform | State |
|---|---|
| macOS arm64 (`maca64`) | Builds, loads, 208/208 tests pass. Verified locally against Homebrew ITK and in CI against static ITK, including the full suite on a runner with **no ITK installed**. |
| Linux x86_64 (`glnxa64`) | Builds, loads, 208/208 tests pass. Verified in CI against static ITK, including the full suite on a runner with **no ITK installed**. Must be built with GCC 12 or older; see BUILDING.md. |
| macOS x86_64 (`maci64`) | Legacy; built on a best-effort basis only. R2025b is MathWorks' final Intel-Mac release. |
| Windows | Best-effort only; the ITK toolchain there is unresolved. Not attempted. |

Binaries link ITK **statically**, so they need no ITK install and no package manager.
"Verified on a runner with no ITK installed" means exactly that:
CI downloads the built artifact onto a fresh machine that never installed ITK,
loads it in MATLAB, and runs the full suite.
A build-and-test-on-the-same-machine result cannot make that claim,
because the toolchain is still sitting there.

## Quick start

Build (see [BUILDING.md](BUILDING.md) for prerequisites and troubleshooting):

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

Then in MATLAB:

```matlab
addpath('matlab');
load mri;  V = squeeze(D);          % MATLAB's built-in sample volume

% Edge-preserving smoothing
b = mexitk('FCA', [5 0.0625 3.0], double(V));

% Otsu multiple thresholds: N thresholds return N masks (see the gotcha below)
[c1, c2] = mexitk('FOMT', [2 128], double(V));

% Watershed; returns a label image
labels = mexitk('SWS', [0.05 0.01], double(V));

mexitk('?')                          % list opcodes with their validation status
```

## Calling convention

```
mexitk(operationName, [parameters], [inputArray1], [inputArray2], [seed(s)Array], [Image(s)Spacing])
```

- `operationName`: opcode, case-insensitive. Char array or string.
- `parameters`: numeric vector, in the exact order the opcode expects. `mexitk('?')` lists them.
- `inputArray1`: a 3-D volume of class `double`, `single`, `uint8` or `int32`.
- `inputArray2`: a second volume, or `[]` when unused.
- `seed(s)Array`: `[x1 y1 z1 x2 y2 z2 ...]`, 1-based, or `[]`.
- `Image(s)Spacing`: accepted and ignored, matching the original. See COMPATIBILITY.md.

**Type dispatch is significant, not cosmetic.**
The input's MATLAB class selects which ITK instantiation runs,
and casting the input can change the result.
This mirrors the original, and it is why `FOMT` on `uint8` differs from `FOMT` on `double`.

### Gotchas inherited from the original, on purpose

- **`FOMT` with N thresholds returns N outputs, not N+1**, and `nargout` must equal N exactly.
  Otsu produces N+1 classes; the top one is computed and silently dropped.
  This is an upstream off-by-one that callers depend on, so it is preserved.
- **`SWS` accepts a seed argument and ignores it.** Watershed never consumes it.
  Callers pass one anyway and index the label image afterwards.

## Testing

```bash
matlab -batch "addpath('matlab'); exit(run_mexitk_tests('.'))"
```

Tests run against fixtures captured from the real MATITK binary
(`MATITK v.2.4.04 Aug 18 2006`, md5 `c7d1432080e9edc6795a38717f5ab628`) on Linux x86_64.
There are no mocks and no synthetic-only data.
Fixtures are committed because regenerating them requires that Intel-Linux-only binary.
The capture harness is in `tools/capture_reference/`.

Where a test asserts a deviation bound rather than equality,
the bound is a value measured from an actual comparison run, recorded in the test,
and documented in COMPATIBILITY.md.
Re-measure with `tools/measure_deviation.m`.
A bound that starts failing means agreement with the original moved:
investigate and update the documentation, do not raise the number.

## Adding an opcode

The original was generated from ITK's examples by a Perl script.
`mexitk` uses a hand-written registry instead:

1. Add `src/opcodes/<name>.cpp` with a class implementing `Opcode`
   (name, category, description, parameter list, validation status, and a templated `Run`).
2. Add one line to `RegisterBuiltinOpcodes()` in `src/opcode.cpp`.
3. Add the source to `MEXITK_SOURCES` and any new ITK module to `MEXITK_ITK_COMPONENTS` in `CMakeLists.txt`.

The registry is the single source of truth for dispatch, parameter validation,
the `mexitk('?')` listing, and the published validation status,
so the documented status cannot drift from what the code actually claims.

**Keep the ITK component list minimal.**
It is a correctness requirement, not an optimisation:
an unpruned ITK links VTK through `ITKVtkGlue`,
and VTK's static destructors crash MATLAB on exit even when the filter succeeded.

## Licensing

`mexitk` is **BSD-3-Clause**. See [LICENSE](LICENSE).

**ITK is Apache-2.0, and that governs the combination.**
Apache-2.0 is incompatible with GPLv2-*only*, but compatible with GPLv3.
NFT is GPLv2-*or-later*, so an NFT plus mexitk plus ITK combination resolves via GPLv3.
If you are linking this into a GPLv2-only project, that is a real problem, and it is ITK's licence, not this one.

## Credits

The calling convention, the opcode names, the parameter ordering and the diagnostic wording
originate with **MATITK** by **Vincent Chu** and **Ghassan Hamarneh** (Simon Fraser University):

> Chu, V., Hamarneh, G. "MATITK: Extending MATLAB with ITK." *Insight Journal*, 2005.

`mexitk` reimplements that convention against modern ITK.
No MATITK source code was available or used;
the convention was reconstructed from the published paper
and from the binary's own printed self-documentation.
This is not endorsed by, or affiliated with, the MATITK authors.

ITK itself:

> McCormick, M., Liu, X., Jomier, J., Marion, C., Ibanez, L.
> "ITK: enabling reproducible research and open science."
> *Frontiers in Neuroinformatics* 8:13, 2014.

See [CITATION.cff](CITATION.cff) for how to cite `mexitk`.

## Author

Seyed Yahya Shirazi, Swartz Center for Computational Neuroscience (SCCN),
Institute for Neural Computation (INC), UC San Diego.
