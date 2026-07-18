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

This is version 0.2.0.
**30 of the original's 40 opcodes are implemented.**
3 of those are the ones NFT depends on, and the only 3 with captured reference data.
The other 27 are smoke-tested (22 filters and 5 segmentation opcodes) with no reference capture.

| Opcode | ITK filter | Status | What that means |
|---|---|---|---|
| `FOMT` | `OtsuMultipleThresholdsImageFilter` | **validated** | Bit-identical to the original for `double` and `single` at N=2,3,4. `uint8` differs on ~0.2% of voxels. |
| `FCA` | `CurvatureAnisotropicDiffusionImageFilter` | **bounded deviation** | Not bit-identical. RMS 2.6e-3, max 4.7e-2 at 1 iteration over a 0-88 range; compounds with iterations. |
| `SWS` | `WatershedImageFilter` | **bounded deviation** | Region count matches exactly at every tested setting; label images are not bit-identical at fine levels. |
| `FAAB` | `AntiAliasBinaryImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. Output is a signed level-set field (positive inside). Integral input promotes to `float`; on `uint8` the negative (outside) half saturates to 0 on export. |
| `FBB` | `BinomialBlurImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. |
| `FBD` | `BinaryDilateImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. Non-foreground output is the original input value, unchanged. |
| `FBE` | `BinaryErodeImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. Unlike `FBD`, eroded-away foreground becomes the type's min sentinel (0 for `uint8`); untouched background is unchanged. |
| `FBL` | `BilateralImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. |
| `FBT` | `BinaryThresholdImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. |
| `FCF` | `CurvatureFlowImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. `uint8`/`int32` promote to `float` internally. |
| `FD` | `DerivativeImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. `uint8` promotes to `float` internally. |
| `FDG` | `DiscreteGaussianImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. |
| `FDM` | `DanielssonDistanceMapImageFilter` (distance) | **smoke-tested** | Runs and returns plausible output; no reference capture exists. Distance is computed in `float` and saturates at the pixel-type max on integral input. |
| `FDMV` | `DanielssonDistanceMapImageFilter` (Voronoi) | **smoke-tested** | Voronoi accessor identification is provisional (see COMPATIBILITY). |
| `FF` | `FlipImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. |
| `FGA` | `DiscreteGaussianImageFilter` | **smoke-tested** | Duplicate of `FDG`; the registry's parameter signature for `FGA` is identical to `FDG`'s. |
| `FGAD` | `GradientAnisotropicDiffusionImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. Gradient-conductance sibling of `FCA`; `uint8`/`int32` promote to `float` internally. |
| `FGM` | `GradientMagnitudeImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. Zero parameters. Distinct algorithm from `FGMRG`. |
| `FGMRG` | `GradientMagnitudeRecursiveGaussianImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. `uint8`/`int32` promote to `float` internally. Distinct algorithm from `FGM`. |
| `FLS` | `LaplacianRecursiveGaussianImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. Signed output; on `uint8` negative response saturates to 0 on export (`uint8`/`int32` promote to `float`). |
| `FMEAN` | `MeanImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. |
| `FMEDIAN` | `MedianImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. |
| `FSN` | `SigmoidImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. |
| `FVBIH` | `VotingBinaryIterativeHoleFillingImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. |
| `FVMI` | `HessianRecursiveGaussianImageFilter` + `Hessian3DToVesselnessMeasureImageFilter` | **smoke-tested** | Runs and returns plausible output; no reference capture exists. Two-filter vesselness pipeline; integral input promotes to `float`. |
| `SCC` | `ConfidenceConnectedImageFilter` | **smoke-tested** | Region growing from seed(s); no reference capture exists. InitialNeighborhoodRadius left at ITK default. |
| `SCT` | `ConnectedThresholdImageFilter` | **smoke-tested** | Region growing from seed(s); no reference capture. ReplaceValue hardcoded to 255 (inferred from ITK's example; registry exposes none). |
| `SIC` | `IsolatedConnectedImageFilter` | **smoke-tested** | Region growing, two seed groups (first two seed points); no reference. Needs at least 2 seed points. |
| `SNC` | `NeighborhoodConnectedImageFilter` | **smoke-tested** | Region growing from seed(s); no reference capture exists. |
| `SOT` | `OtsuThresholdImageFilter` | **smoke-tested** | Two-valued output; no reference. Inside/outside left at ITK defaults (inside = pixel-type max, so {0,255} on uint8 but {0,realmax} on double). `numberOfHistogram` below 2 is rejected: it crashes the MATLAB process outright inside ITK's Otsu calculator. |

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
> Output from `FCA` and `SWS` will differ slightly from what the original `matitk`
> binary produced on Linux before 2026.
> `FOMT` is identical.
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
| macOS arm64 (`maca64`) | Builds, loads, 196/196 tests pass locally against Homebrew ITK. CI confirmed 156/156 (static ITK, no-ITK-installed runner) before the Phase 4 opcodes; re-verification against the current suite is pending. |
| Linux x86_64 (`glnxa64`) | Builds, loads. Last CI-verified at 156/156 on a runner with **no ITK installed**, before the Phase 4 opcodes; re-verification against the current 196-test suite is pending. Must be built with GCC 12 or older; see BUILDING.md. |
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
