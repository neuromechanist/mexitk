# MATITK opcode → modern ITK 5.4.x class mapping

Target: reimplement MATITK's 40 opcodes (auto-generated in 2005-06 from ITK 2.4
example files by a Perl script) as a modern C++ tool against ITK 5.4.x.

**Ground truth for parameter names/order**: `matitk_opcode_params.txt`
(dumped from the real MATITK binary's own self-documentation).
**Confirmed by the original paper** (`matitk-paper-ij2005.pdf`): FCA =
`CurvatureAnisotropicDiffusionImageFilter`, SCC = `ConfidenceConnectedImageFilter`,
FGM = `GradientMagnitudeImageFilter`, FOMT = `OtsuMultipleThresholdImageFilter`
(2.4-era singular "Threshold").

**Verification method**: every modern class/header/module/setter claim below was
checked directly against ITK source on GitHub
(`github.com/InsightSoftwareConsortium/ITK`, `master`/`v5.4.0`), fetched header
by header, not recalled from memory. `docs.itk.org` Doxygen was rate-limited
(HTTP 429) for direct fetches during this research pass, so GitHub source was
used as the primary source of truth throughout — it is in fact the more
authoritative source since it shows exact setter signatures, not just prose.
Two independent research passes additionally cross-checked results against
Vincent Chu's own MATITK opcode-documentation page (the original author),
which resolved several identity questions the ITK source alone could not
(FBB, FGMS, FSN, FVBIH names below).

One module-name conflict between research passes was found and resolved by
directly listing GitHub directory contents: `GradientMagnitudeImageFilter`
and `GradientMagnitudeRecursiveGaussianImageFilter` both live in
`Modules/Filtering/ImageGradient`, module **`ITKImageGradient`** — not
`ITKImageFeature` as one pass initially reported. This is corrected throughout
this document (affects FGM, FGMRG, and the FGM stage of FGMS).

---

## At-a-glance summary

| Opcode | Modern ITK 5.x class | Module | Confidence |
|---|---|---|---|
| FAAB | `AntiAliasBinaryImageFilter` | ITKAntiAlias | High |
| FBB | `BinomialBlurImageFilter` | ITKSmoothing | High |
| FBD | `BinaryDilateImageFilter` | ITKBinaryMathematicalMorphology | High |
| FBE | `BinaryErodeImageFilter` | ITKBinaryMathematicalMorphology | High |
| FBL | `BilateralImageFilter` | ITKImageFeature | High |
| FBT | `BinaryThresholdImageFilter` | ITKThresholding | High |
| FCA | `CurvatureAnisotropicDiffusionImageFilter` | ITKAnisotropicSmoothing | High |
| FCF | `CurvatureFlowImageFilter` | ITKCurvatureFlow | High |
| FD | `DerivativeImageFilter` | ITKImageFeature | High |
| FDG | `DiscreteGaussianImageFilter` | ITKSmoothing | High |
| FDM | `DanielssonDistanceMapImageFilter` (distance output) | ITKDistanceMap | High |
| FDMV | `DanielssonDistanceMapImageFilter` (Voronoi output) | ITKDistanceMap | Medium |
| FF | `FlipImageFilter` | ITKImageGrid | High |
| FFFT | `ForwardFFTImageFilter` (→ PocketFFT backend) | ITKFFT | Medium |
| FGA | `DiscreteGaussianImageFilter` (likely duplicate of FDG) | ITKSmoothing | Medium |
| FGAD | `GradientAnisotropicDiffusionImageFilter` | ITKAnisotropicSmoothing | High |
| FGM | `GradientMagnitudeImageFilter` | ITKImageGradient | High |
| FGMRG | `GradientMagnitudeRecursiveGaussianImageFilter` | ITKImageGradient | High |
| FGMS | `SmoothingRecursiveGaussianImageFilter` + `GradientMagnitudeImageFilter` (hypothesis) | ITKSmoothing + ITKImageGradient | **Low** |
| FLS | `LaplacianRecursiveGaussianImageFilter` | ITKImageFeature | High |
| FMEAN | `MeanImageFilter` | ITKSmoothing | High |
| FMEDIAN | `MedianImageFilter` | ITKSmoothing | High |
| FMMCF | `MinMaxCurvatureFlowImageFilter` | ITKCurvatureFlow | Medium |
| FOMT | `OtsuMultipleThresholdsImageFilter` (renamed, plural) | ITKThresholding | High |
| FSN | `SigmoidImageFilter` | ITKImageIntensity | High |
| FVBIH | `VotingBinaryIterativeHoleFillingImageFilter` | ITKLabelVoting (moved) | High |
| FVMI | `HessianRecursiveGaussianImageFilter` + `Hessian3DToVesselnessMeasureImageFilter` | ITKImageFeature | High |
| SCC | `ConfidenceConnectedImageFilter` | ITKRegionGrowing | High |
| SCSS | `itk::bio::CellularAggregate`/`CellBase` (BioCell) | ITKBioCell (remote, opt-in) | **Medium** |
| SCT | `ConnectedThresholdImageFilter` | ITKRegionGrowing | High |
| SFM | `FastMarchingImageFilter` | ITKFastMarching | Medium |
| SGAC | `GeodesicActiveContourLevelSetImageFilter` | ITKLevelSets | High |
| SIC | `IsolatedConnectedImageFilter` | ITKRegionGrowing | High |
| SLLS | `LaplacianSegmentationLevelSetImageFilter` | ITKLevelSets | High |
| SNC | `NeighborhoodConnectedImageFilter` | ITKRegionGrowing | High |
| SOT | `OtsuThresholdImageFilter` (unchanged, singular) | ITKThresholding | High |
| SSDLS | `ShapeDetectionLevelSetImageFilter` | ITKLevelSets | High |
| SWS | `WatershedImageFilter` | ITKWatersheds | High |
| RD | `HistogramMatchingImageFilter` + `DemonsRegistrationFilter` | ITKImageIntensity + ITKPDEDeformableRegistration | High |
| RTPS | `ThinPlateSplineKernelTransform` | ITKTransform | High |

**Confidence tally: 33 High / 6 Medium / 1 Low.**

---

## Load-bearing findings (read first)

### FOMT / Otsu — renamed, single-output, N masks must be derived

ITK 2.4's `itk::OtsuMultipleThresholdImageFilter` (singular "Threshold",
confirmed by the paper's own worked example
`[O1,O2,O3]=matitk('fomt',[3,128],D)`) is renamed in modern ITK to
`itk::OtsuMultipleThresholdsImageFilter` (plural "Thresholds").
Verified directly from
`Modules/Filtering/Thresholding/include/itkOtsuMultipleThresholdsImageFilter.h`.

- `SetNumberOfHistogramBins(SizeValueType)` — clamped ≥1, default 128.
- `SetNumberOfThresholds(SizeValueType)` — clamped ≥1, default 1.
- `GetThresholds() const` → `const ThresholdVectorType&`
  (`std::vector<MeasurementType>`, N computed intensity thresholds).

**Output arity, resolved**: the modern filter produces **exactly one output
image** — a labeled image with `NumberOfThresholds + 1` distinct integer
label values (0..N, offsettable via `SetLabelOffset`). It does not, and never
did, produce N/N+1 separate ITK images internally; the class docstring states
it "creates a labeled image that separates the input image into various
classes." The old MATITK wrapper's `[O1,O2,O3]=...` behavior must therefore
have been **wrapper-side post-processing**, not filter behavior, in the 2.4
version too.

**How to derive N separate volumes for the reimplementation**: run
`OtsuMultipleThresholdsImageFilter` once, call `GetThresholds()` to get the N
scalar threshold values, then run `itk::BinaryThresholdImageFilter` N times
directly on the *original intensity* input at each threshold value. This
needs no assumption about the label image's internal ordering and directly
uses the documented public API. (An alternative — binary-thresholding the
*label* image itself at each label boundary — also works but depends on
assumptions about label contiguity that `GetThresholds()` avoids.)

Confidence: **High** on the rename and the single-output-image behavior
(verified from header + docstring directly).

### SWS / Watershed — gradient-magnitude input, 0.0–1.0 fractional params, 64-bit label output

`itk::WatershedImageFilter<TInputImage>` **still exists**, unchanged in
identity, verified directly from
`Modules/Segmentation/Watersheds/include/itkWatershedImageFilter.h`.
Module **`ITKWatersheds`** (name unchanged).

- `SetLevel(double)` / `SetThreshold(double)` — confirmed still fractional,
  0.0–1.0, expressed as a percentage of the maximum height/depth in the
  input. Class documentation explicitly warns levels above ≈0.40
  undersegment.
- **Input requirement**: the filter does *not* compute gradient magnitude
  itself. Its documentation explicitly recommends chaining
  `itk::GradientMagnitudeImageFilter` (or an anisotropic-diffusion +
  gradient pipeline) beforehand — the same two-stage pattern as the classic
  ITK example. Feeding it a raw intensity image directly is a usage error,
  not a filter error.
- **Output type**: `itk::Image<IdentifierType, ImageDimension>`, where
  `IdentifierType = SizeValueType`. Per `itkIntTypes.h`, that resolves to
  `uint64_t` on standard `ITK_USE_64BITS_IDS=ON` builds (the default on
  modern 64-bit platforms), `unsigned long` as the 32-bit fallback. This is a
  **label image**, not a binary/float image — a real pitfall for the
  MATLAB bridge if it assumes a narrower integer type.

**Alternative checked and ruled out**: `itk::MorphologicalWatershedImageFilter`
(also module `ITKWatersheds`) is a genuinely different, newer algorithm
(pure morphological, not merge-tree). It exposes only
`SetLevel(InputImagePixelType)` (native pixel units, not 0–1 fractional) and
has **no** `SetThreshold` — it cannot match MATITK's two-parameter SWS
signature, confirming `itk::WatershedImageFilter` is the correct match.

Confidence: **High**. This corner of ITK has seen essentially no API churn;
the real risk is pipeline construction (must feed it a gradient-magnitude
image) and output-type handling (64-bit label image), not a rename.

### FCA / CurvatureAnisotropicDiffusionImageFilter time-step stability — corrects the task's premise

Directly sourced from
`Modules/Filtering/AnisotropicSmoothing/include/itkAnisotropicDiffusionImageFilter.hxx`
(the shared base class for both FCA and FGAD):

```
// constructor
m_TimeStep(0.5 / double{ 1ULL << ImageDimension })

// InitializeIteration()
if (m_TimeStep > (minSpacing / double{ 1ULL << (ImageDimension + 1) }))
{
  itkWarningMacro("Anisotropic diffusion unstable time step: "
                  << m_TimeStep << std::endl
                  << "Stable time step for this image must be smaller than "
                  << minSpacing / double{ 1ULL << (ImageDimension + 1) });
}
```

For unit spacing (MATITK's default when no spacing argument is supplied,
per the paper): 2D bound = 1/2³ = **0.125**; 3D bound = 1/2⁴ = **0.0625**.
This is stated explicitly in the class documentation too: *"Stable values
for most 2D and 3D functions are 0.125 and 0.0625, respectively, when the
pixel spacing is unity."*

**This corrects the task brief's stated premise.** MATITK's own documented
default of `timeStep = 0.0625` is not a 2D value overshooting a smaller 3D
limit — it is *exactly* ITK's own computed 3D-stable default
(`0.5 / 2³ = 0.0625`), matching the constructor's own default for a 3D
image at unit spacing. The check is strict `>`, so `0.0625` sits precisely
at the boundary and does not itself trigger the warning; it is
marginally stable, not unstable, for 3D data at unit (or coarser) spacing.
A genuinely unsafe case would be a 3D volume with `timeStep = 0.125`
(the 2D-safe value applied to 3D data), or any spacing finer than 1 voxel
unit combined with 0.0625.

**Runtime behavior when the limit is violated**: `itkWarningMacro` only —
a console warning via ITK's standard object logging, **not an exception and
not an automatic clamp**. The filter proceeds with the user-supplied
`timeStep` regardless; numerical instability (oscillation/blow-up) is left
to manifest in the output pixel values rather than being prevented.

**ITK 2.4 behavior**: not independently re-verified against actual 2.4
source (not fetched in this pass), but this is textbook explicit
finite-difference CFL stability arithmetic tied to the core
`FiniteDifferenceImageFilter` numerical scheme, which predates ITK 2.4 and
has not architecturally changed; multiple long-standing ITK Software Guide
passages already cite the same 0.125/0.0625 constants. Treat "unchanged
since 2.4" as medium-high confidence, not directly verified.

Same base class (`AnisotropicDiffusionImageFilter`) is shared by FGAD
(`GradientAnisotropicDiffusionImageFilter`), so this entire finding applies
identically to FGAD.

---

## Filters (27)

### `FAAB` — AntiAliasBinaryImageFilter
| Field | Value |
|---|---|
| ITK 2.4 class | `itk::AntiAliasBinaryImageFilter` (unchanged) |
| **Modern class** | `itk::AntiAliasBinaryImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKAntiAlias` (setters inherited from Core `ITKFiniteDifference`) |
| Header | `itkAntiAliasBinaryImageFilter.h` |
| Params → setters | `maximumRMSError → SetMaximumRMSError(double)`; `numberOfIterations → SetNumberOfIterations(IdentifierType)` (unsigned integral `SizeValueType`); `numberOfLayers → SetNumberOfLayers(unsigned int)` (default 2, matches hint) |
| Pixel constraints | input effectively binary; output pixel type must be convertible from `double` (typically float/double) |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | none in identity; deprecated alias `SetMaximumIterations`/`GetMaximumIterations` still exists (warns, forwards to `SetNumberOfIterations`) |
| Confidence | High — class + both base-class headers read directly |

### `FBB` — BinomialBlurImageFilter
| Field | Value |
|---|---|
| ITK 2.4 class | `itk::BinomialBlurImageFilter` (unchanged) |
| **Modern class** | `itk::BinomialBlurImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKSmoothing` |
| Header | `itkBinomialBlurImageFilter.h` |
| Params → setters | `repetitions → SetRepetitions(unsigned int)` (declared directly on the class) |
| Pixel constraints | input pixel type convertible to `double`; output constructible from `double` |
| Arity | 1 input, 1 output, no seeds; needs `2×Repetitions` extra border pixels on input relative to output region |
| Drift/risk | none — identity independently confirmed via the original author's own opcode-documentation page, ruling out initial hypotheses of `BinaryMinMaxCurvatureFlowImageFilter`/`VotingBinaryIterativeHoleFillingImageFilter` |
| Confidence | High |

### `FBD` — BinaryDilateImageFilter
| Field | Value |
|---|---|
| ITK 2.4 class | `itk::BinaryDilateImageFilter` (unchanged) |
| **Modern class** | `itk::BinaryDilateImageFilter<TInputImage,TOutputImage,TKernel>` |
| Module | `ITKBinaryMathematicalMorphology` (kernel object `itk::BinaryBallStructuringElement` is module `ITKMathematicalMorphology`) |
| Header | `itkBinaryDilateImageFilter.h` (+ `itkBinaryBallStructuringElement.h`) |
| Params → setters | `DilationRadius` is **not a filter setter** — build the kernel: `BinaryBallStructuringElement::SetRadius(SizeValueType)` (scalar overload) or `SetRadius(SizeType)` (per-axis), then `kernel.CreateStructuringElement()`, then `filter->SetKernel(kernel)` (`BinaryMorphologyImageFilter::SetKernel(const KernelType&)`). `ValueOverWhichDilateWillApply → SetDilateValue(InputPixelType)` (alias forwarding to `SetForegroundValue(InputPixelType)`; default = max value of PixelType, matches "usually 255") |
| Pixel constraints | kernel radius type is `itk::Size<Dimension>`, not a plain scalar, in the primary API |
| Arity | 1 input image + 1 kernel object (auxiliary, not an "image input"), 1 output, no seeds |
| Drift/risk | no renames since 2.4; **structural trap**: dilation radius requires two-step/two-object construction (kernel + `CreateStructuringElement()` + `SetKernel`), not a single filter setter — MATITK's flat parameter list hides this entirely |
| Confidence | High |

### `FBE` — BinaryErodeImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::BinaryErodeImageFilter<TInputImage,TOutputImage,TKernel>` |
| Module | `ITKBinaryMathematicalMorphology` |
| Header | `itkBinaryErodeImageFilter.h` |
| Params → setters | `ErosionRadius` → same kernel `SetRadius`/`CreateStructuringElement` pattern as FBD; `ValueOverWhichErodeWillApply → SetErodeValue(InputPixelType)` (alias for `SetForegroundValue`) |
| Pixel/arity/drift | symmetric to FBD in every respect |
| Confidence | High |

### `FBL` — BilateralImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::BilateralImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKImageFeature` (confirmed via directory listing) |
| Header | `itkBilateralImageFilter.h` |
| Params → setters | `domainSigma → SetDomainSigma(double)` (scalar convenience overload fills the internal per-axis array); `rangeSigma → SetRangeSigma(double)` |
| Pixel constraints | no explicit float requirement; works via `NumericTraits` on general numeric pixel types |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | none found |
| Confidence | High |

### `FBT` — BinaryThresholdImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::BinaryThresholdImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKThresholding` |
| Header | `itkBinaryThresholdImageFilter.h` |
| Params → setters (order confirmed) | `outsideValue → SetOutsideValue(OutputPixelType)`; `insideValue → SetInsideValue(OutputPixelType)`; `lowerThreshold → SetLowerThreshold(InputPixelType)`; `upperThreshold → SetUpperThreshold(InputPixelType)` |
| Pixel constraints | none special; input/output pixel types are independent template params |
| Arity | 1 input, 1 output (runtime `DataObject`-threshold overloads exist, unneeded here) |
| Drift/risk | none |
| Confidence | High |

### `FCA` — CurvatureAnisotropicDiffusionImageFilter
| Field | Value |
|---|---|
| ITK 2.4 class | `itk::CurvatureAnisotropicDiffusionImageFilter` — **confirmed by the original paper** |
| **Modern class** | `itk::CurvatureAnisotropicDiffusionImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKAnisotropicSmoothing` |
| Header | `itkCurvatureAnisotropicDiffusionImageFilter.h` |
| Params → setters | `numberOfIterations → SetNumberOfIterations(IdentifierType)`; `timeStep → SetTimeStep(TimeStepType)` (effectively `double`); `conductance → SetConductanceParameter(double)` |
| Pixel constraints | **explicitly requires scalar floating-point (float/double)** pixel type per class docs |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | see dedicated time-step-stability finding above — this is the load-bearing hazard, not a rename |
| Confidence | High |

### `FCF` — CurvatureFlowImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::CurvatureFlowImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKCurvatureFlow` |
| Header | `itkCurvatureFlowImageFilter.h` |
| Params → setters | `numberOfIterations → SetNumberOfIterations(IdentifierType)` (inherited); `timeStep → SetTimeStep(TimeStepType)` (declared directly on this class) |
| Pixel constraints | input/output pixels must be a floating-point type per header docs |
| Arity | 1 input, 1 output; filter internally pads by `NumberOfIterations` pixels at each edge |
| Drift/risk | none |
| Confidence | High |

### `FD` — DerivativeImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::DerivativeImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKImageFeature` (confirmed via directory listing) |
| Header | `itkDerivativeImageFilter.h` |
| Params → setters | `SETORDER → SetOrder(unsigned int)`; `SETDIRECTION → SetDirection(unsigned int)` (axis index) |
| Pixel constraints | none explicit |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | ITK's module system did not exist pre-4.0, so "did this filter move" is not meaningfully answerable for 2.4→5.x beyond "modularization happened"; no setter renames found |
| Confidence | High |

### `FDG` — DiscreteGaussianImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::DiscreteGaussianImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKSmoothing` |
| Header | `itkDiscreteGaussianImageFilter.h` |
| Params → setters | `gaussianVariance → SetVariance(double)` (scalar overload fills internal per-axis array); `maxKernelWidth → SetMaximumKernelWidth(unsigned int)` |
| Pixel constraints | any numeric pixel type (`HasNumericTraits`); output typically float/double |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | none besides the 2011 modularization moving the header |
| Confidence | High — but see FGA below, near-certain duplicate |

### `FDM` — DanielssonDistanceMapImageFilter (distance output)
| Field | Value |
|---|---|
| **Modern class** | `itk::DanielssonDistanceMapImageFilter<TInputImage,TOutputImage,TVoronoiImage>`, accessed via `GetOutput()`/`GetDistanceMap()` |
| Module | `ITKDistanceMap` |
| Header | `itkDanielssonDistanceMapImageFilter.h` |
| Params → setters | none (matches the zero-param wrapper entry; optional flags `SquaredDistance`/`InputIsBinary`/`UseImageSpacing` left at default) |
| Pixel constraints | input typically binary/label image; distance output typically float |
| Arity | 1 input, 1 output (this accessor), no seeds |
| Drift/risk | none; header now under `Modules/Filtering/DistanceMap` |
| Confidence | High |

### `FDMV` — DanielssonDistanceMapImageFilter (Voronoi-map output)
| Field | Value |
|---|---|
| **Modern class** | same class as FDM, `itk::DanielssonDistanceMapImageFilter`, but read via `GetVoronoiMap()` |
| Module/header | same as FDM |
| Params → setters | none |
| Pixel constraints | Voronoi-map pixel type equals the input's (a nearest-feature-point label map, not a distance) |
| Arity | 1 input, 1 output (Voronoi accessor), no seeds |
| Drift/risk | **"V" identified as Voronoi, not Vector** — `GetVectorDistanceMap()` exists as a third, separate accessor on the same class. This resolution rests on convergent secondary sourcing (a Vincent Chu opcode table), not the original `matitk.cxx`, so treat as provisional |
| Confidence | Medium — class identity solid; the FDM-vs-FDMV accessor distinction is inferred, not directly source-confirmed |

### `FF` — FlipImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::FlipImageFilter<TImage>` (single template — input type == output type) |
| Module | `ITKImageGrid` |
| Header | `itkFlipImageFilter.h` |
| Params → setters | `XDIRECTION, YDIRECTION, ZDIRECTION` are marshaled into **one** `FixedArray<bool,ImageDimension>` and passed via a single `SetFlipAxes(FlipAxesArrayType)` call — not three separate setters |
| Pixel constraints | any pixel type (pure index permutation) |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | `SetFlipAboutOrigin(bool)` added later, default `false` preserves legacy behavior — additive only |
| Confidence | High |

### `FFFT` — Forward FFT (highest API drift of any filter opcode)
| Field | Value |
|---|---|
| ITK 2.4 class | almost certainly `itk::VnlFFTRealToComplexConjugateImageFilter` (VNL was the only forward-FFT backend enabled by default pre-4.0; FFTW was opt-in for licensing reasons) |
| **Modern class** | `itk::ForwardFFTImageFilter<TInputImage,TOutputImage>` (abstract, factory-dispatched front end); `New()` resolves to `itk::PocketFFTForwardFFTImageFilter` by default (bundled pocketfft library), or `itk::FFTWForwardFFTImageFilter` if an FFTW backend was compiled in. `itk::VnlForwardFFTImageFilter` (the ITKv4-era rename of the 2.4 class) still exists but is **now deprecated**, reduced to a thin subclass of `PocketFFTForwardFFTImageFilter` — the underlying VNL/Temperton FFT implementation was deleted outright |
| Module | `ITKFFT` |
| Header | `itkForwardFFTImageFilter.h` (+ `itkVnlForwardFFTImageFilter.h` for the deprecated concrete class) |
| Params → setters | `"Real Or Complex Output" (0/1)` — the forward-FFT filter itself has **no** real/complex switch; its output is always `Image<std::complex<PixelType>>`. This parameter most plausibly gates a downstream chain: `itk::ComplexToRealImageFilter` or `itk::ComplexToModulusImageFilter` (both module `ITKImageIntensity`) applied when "Real" (0) is selected, vs. returning the raw complex image when "Complex" (1) is selected. **Not confirmed** against original wrapper source which of the two (Real vs. Modulus) MATITK actually chains |
| Pixel constraints | input should be floating point (Vnl/PocketFFT require it) |
| Arity | 1 input, 1 output (complex, or real/modulus after an added downstream filter) |
| Drift/risk | **major**: class renamed twice (2.4 concrete Vnl class → ITKv4 `VnlForwardFFTImageFilter` → now deprecated in favor of `PocketFFTForwardFFTImageFilter` via the `ForwardFFTImageFilter` front end); backend library replaced outright (VNL/Temperton deleted, pocketfft bundled); `ITKFFT` module dependency is easy to miss entirely in a naive port |
| Confidence | Medium-high on the class lineage/drift narrative (directly source-verified); Low on the exact real/complex switch semantics (unverified against primary MATITK source) — net **Medium** |

### `FGA` — likely duplicate of FDG
| Field | Value |
|---|---|
| **Modern class** | same conclusion as FDG: `itk::DiscreteGaussianImageFilter<TInputImage,TOutputImage>` — best-supported by parameter-shape elimination. Ruled out: `SmoothingRecursiveGaussianImageFilter`/`RecursiveGaussianImageFilter`/`GradientMagnitudeRecursiveGaussianImageFilter` expose only `SetSigma`, no kernel-width; `itk::GaussianBlurImageFunction` has `SetSigma`+`SetMaximumKernelWidth` but no `SetVariance` and is a point-evaluated `ImageFunction`, not a whole-image filter, inconsistent with MATITK's per-example generation pattern |
| Module/header/setters | identical to FDG entry |
| Pixel/arity | identical to FDG entry |
| Drift/risk | **likely a duplicate-opcode artifact** of the Perl auto-generator (two differently-pathed ITK 2.4 example files, both wrapping `DiscreteGaussianImageFilter`) rather than two genuinely distinct filters. Flag in any downstream implementation rather than silently building it twice; confirm against `matitk.cxx`/`matitkcode.pl` if the original source ever surfaces |
| Confidence | Medium — solid by elimination, not confirmed against MATITK's own source |

### `FGAD` — GradientAnisotropicDiffusionImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::GradientAnisotropicDiffusionImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKAnisotropicSmoothing` |
| Header | `itkGradientAnisotropicDiffusionImageFilter.h` |
| Params → setters | `numberOfIterations → SetNumberOfIterations(IdentifierType)`; `timeStep → SetTimeStep(TimeStepType)`; `conductance → SetConductanceParameter(double)` (all inherited from `AnisotropicDiffusionImageFilter`) |
| Pixel constraints | floating-point pixel types strongly recommended (PDE finite-difference solver) |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | none functional; **shares FCA's time-step CFL stability behavior** (same base class) — see the dedicated FCA section above, applies verbatim here |
| Confidence | High |

### `FGM` — GradientMagnitudeImageFilter
| Field | Value |
|---|---|
| ITK 2.4 class | `itk::GradientMagnitudeImageFilter` — **confirmed by the original paper**, worked example `G=matitk('FGM',[],D)` |
| **Modern class** | `itk::GradientMagnitudeImageFilter<TInputImage,TOutputImage>` |
| Module | **`ITKImageGradient`** (directly confirmed via GitHub directory listing — corrects an `ITKImageFeature` misattribution found in one research pass) |
| Header | `itkGradientMagnitudeImageFilter.h` |
| Params → setters | none (matches paper's zero-param example) |
| Pixel constraints | only requires `itk::Concept::HasNumericTraits<InputPixelType>` — **not** floating point; simple central-difference/Neumann-boundary gradient, integer input is fine |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | none besides module directory |
| Confidence | High |

### `FGMRG` — GradientMagnitudeRecursiveGaussianImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::GradientMagnitudeRecursiveGaussianImageFilter<TInputImage,TOutputImage>` |
| Module | **`ITKImageGradient`** (directly confirmed — not `ITKImageFeature`) |
| Header | `itkGradientMagnitudeRecursiveGaussianImageFilter.h` |
| Params → setters | `sigma → SetSigma(RealType)` (floating-point scalar) |
| Pixel constraints | requires floating-point pixel types internally (recursive/Deriche IIR Gaussian implementation) |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | gained an optional `NormalizeAcrossScale` flag since 2.4 (default preserves legacy behavior) — additive only. Distinct algorithm from FGM (recursive-Gaussian vs. simple central-difference) |
| Confidence | High |

### `FGMS` — Gradient Magnitude with Smoothing (**flagged, low confidence**)
| Field | Value |
|---|---|
| ITK 2.4 class | unknown — no ITK class named "GradientMagnitudeWithSmoothingFilter" exists anywhere in the ITK 5.x tree (checked `Modules/Filtering/ImageFeature` and `Modules/Filtering/Smoothing`) |
| **Modern class (hypothesis only)** | two-stage classic-example pipeline: `itk::SmoothingRecursiveGaussianImageFilter` (`SetSigma`) feeding `itk::GradientMagnitudeImageFilter` (parameterless) |
| Module | `ITKSmoothing` (stage 1) + `ITKImageGradient` (stage 2, corrected from an earlier `ITKImageFeature` misattribution) |
| Header | `itkSmoothingRecursiveGaussianImageFilter.h` + `itkGradientMagnitudeImageFilter.h` |
| Params → setters | `Sigma → SmoothingRecursiveGaussianImageFilter::SetSigma(double)`, feeding the parameterless `GradientMagnitudeImageFilter` |
| Pixel constraints | scalar float/double preferred (internal `RealType`) |
| Arity | 1 input, 1 output (hypothesized) |
| Drift/risk | **the identity itself is the risk** — this is the only opcode in the entire set that could not be pinned to a specific stock ITK class from naming/parameter-shape evidence alone. It is clearly distinct from FGMRG (same-shaped single-sigma param but FGMRG is confirmed as `GradientMagnitudeRecursiveGaussianImageFilter`) |
| Confidence | **Low** — recommend running `matitk('fgms')` and a live `matitk('FGMS',[sigma],testVolume)` call against the real MATITK binary (per the project's real-data-only testing policy) and diffing its numeric output against FGMRG's before committing to an implementation |

### `FLS` — LaplacianRecursiveGaussianImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::LaplacianRecursiveGaussianImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKImageFeature` (confirmed via directory listing) |
| Header | `itkLaplacianRecursiveGaussianImageFilter.h` |
| Params → setters | `sigma → SetSigma(RealType)` (also has `SetNormalizeAcrossScale(bool)`, not in MATITK's param list, default `false`) |
| Pixel constraints | scalar, real (`RealType` = float/double internally) |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | none; name unchanged since 2.4 |
| Confidence | High |

### `FMEAN` — MeanImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::MeanImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKSmoothing` (`SetRadius` inherited from `itk::BoxImageFilter`, module `ITKImageFilterBase`) |
| Header | `itkMeanImageFilter.h` |
| Params → setters | `XRADIUS/YRADIUS/ZRADIUS` assembled into one `RadiusType` (`=SizeType`), passed via `SetRadius(const RadiusType&)` |
| Pixel constraints | requires `HasNumericTraits<InputPixelType>` (scalar numeric) |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | none |
| Confidence | High |

### `FMEDIAN` — MedianImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::MedianImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKSmoothing` |
| Header | `itkMedianImageFilter.h` |
| Params → setters | same `SetRadius` mechanism as FMEAN (`BoxImageFilter` base) |
| Pixel constraints | requires `LessThanComparable` pixel type (`operator<`) |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | none |
| Confidence | High |

### `FMMCF` — MinMaxCurvatureFlowImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::MinMaxCurvatureFlowImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKCurvatureFlow` |
| Header | `itkMinMaxCurvatureFlowImageFilter.h` |
| Params → setters | `numberOfIterations → SetNumberOfIterations(unsigned int)` (inherited via the `CurvatureFlowImageFilter`/`DenseFiniteDifferenceImageFilter` chain); `timeStep → SetTimeStep(double)` (inherited); `stencilRadius → SetStencilRadius(RadiusValueType)` (declared locally on this class) |
| Pixel constraints | header explicitly warns output image pixels must be a **real type** (float/double) — hard drift risk if fed integer images |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | none in class identity |
| Confidence | **Medium** — class identity itself high confidence; exact inherited setter parameter *types* (`SetNumberOfIterations`/`SetTimeStep`) were not directly viewed in this specific header (they live one hop up, in `itkCurvatureFlowImageFilter.h`/`itkDenseFiniteDifferenceImageFilter.h`) — very likely `unsigned int`/`double` per standard ITK convention and consistent with FCF's confirmed signatures, but not independently re-verified for this class |

### `FOMT` — OtsuMultipleThresholdsImageFilter
See the dedicated load-bearing section above. Summary: renamed from
`OtsuMultipleThresholdImageFilter` (singular) to
`OtsuMultipleThresholdsImageFilter` (plural). Module `ITKThresholding`,
header `itkOtsuMultipleThresholdsImageFilter.h`. Params:
`numberOfThresholds → SetNumberOfThresholds(SizeValueType)`;
`numberOfBins → SetNumberOfHistogramBins(SizeValueType)`. **1 input, 1
output** (single labeled image; N binary masks are derived post-hoc via
`GetThresholds()` + N calls to `BinaryThresholdImageFilter`). Confidence:
**High**.

### `FSN` — SigmoidImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::SigmoidImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKImageIntensity` |
| Header | `itkSigmoidImageFilter.h` |
| Params → setters (exact order) | `outputMinimum → SetOutputMinimum(OutputPixelType)`; `outputMaximum → SetOutputMaximum(OutputPixelType)`; `alpha → SetAlpha(double)`; `beta → SetBeta(double)` |
| Pixel constraints | input convertible to `double`; output supports additive/multiply-by-double operators; implemented via internal `Functor::Sigmoid` wrapped in `UnaryFunctorImageFilter` |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | none |
| Confidence | High |

### `FVBIH` — VotingBinaryIterativeHoleFillingImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::VotingBinaryIterativeHoleFillingImageFilter<TImage>` (single template — input type == output type) |
| Module | **`ITKLabelVoting`** (module **moved** — not `ITKBinaryMathematicalMorphology`, confirmed by a 404 there and direct location in `Modules/Segmentation/LabelVoting`) |
| Header | `itkVotingBinaryIterativeHoleFillingImageFilter.h` |
| Params → setters | `radiusX/Y/Z` assembled into `itk::Size<3>`, `SetRadius(InputSizeType)`; `binaryImageBackgroundColor → SetBackgroundValue(InputPixelType)`; `binaryImageForegroundColor → SetForegroundValue(InputPixelType)`; `SetMajorityThreshold → SetMajorityThreshold(unsigned int)` (literal setter name confirmed present in the header, exactly as the opcode's param name suggests); `numberOfIterations → SetMaximumNumberOfIterations(unsigned int)` |
| Pixel constraints | requires `EqualityComparable` + `OStreamWritable`; typically binary `unsigned char` |
| Arity | 1 input, 1 output, no seeds |
| Drift/risk | **module moved** to `ITKLabelVoting` — a naive `find_package(ITK COMPONENTS ITKBinaryMathematicalMorphology)` guess fails to link this filter. `SetMajorityThreshold` is an OFFSET above 50% of the neighborhood, not an absolute vote count: internally (`itkVotingBinaryHoleFillingImageFilter.hxx`, the class this filter delegates each iteration to) `birthThreshold = floor((N-1)/2) + MajorityThreshold`, where `N` is the full neighborhood size including the center pixel (`prod(2*radius[i]+1)`), and an OFF pixel flips ON only once its ON-neighbor count reaches `birthThreshold`. A large `MajorityThreshold` silently makes the filter a no-op rather than erroring; this is the class's own documented semantics, reproduced on purpose. |
| Confidence | High |

### `FVMI` — Vesselness (two-filter pipeline)
| Field | Value |
|---|---|
| **Modern classes** | `itk::HessianRecursiveGaussianImageFilter<TInputImage>` (computes the Hessian; default output `Image<SymmetricSecondRankTensor<RealType,Dim>,Dim>`) feeding `itk::Hessian3DToVesselnessMeasureImageFilter<TPixel>` (**hardcoded to 3-D** — its `Superclass` is `ImageToImageFilter<Image<SymmetricSecondRankTensor<double,3>,3>, Image<TPixel,3>>`) |
| Module | `ITKImageFeature` (both classes, confirmed via directory listing) |
| Header | `itkHessianRecursiveGaussianImageFilter.h`, `itkHessian3DToVesselnessMeasureImageFilter.h` |
| Params → setters | `SetSigma → HessianRecursiveGaussianImageFilter::SetSigma(RealType)`; `SetAlpha1 → Hessian3DToVesselnessMeasureImageFilter::SetAlpha1(double)`; `SetAlpha2 → Hessian3DToVesselnessMeasureImageFilter::SetAlpha2(double)` |
| Pixel constraints | input scalar; output `TPixel` convertible from `double` |
| Arity | 1 input volume (**must be 3-D** — 2-D unsupported by `Hessian3DToVesselnessMeasureImageFilter`), 1 output scalar vesselness image, no seeds |
| Drift/risk | no API rename; the two-stage pipeline split (three setters landing on two different classes) is the implementation trap, not a rename |
| Confidence | High |

---

## Segmentation (11)

### `SCC` — ConfidenceConnectedImageFilter
| Field | Value |
|---|---|
| ITK 2.4 class | `itk::ConfidenceConnectedImageFilter` — **confirmed by the original paper** |
| **Modern class** | `itk::ConfidenceConnectedImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKRegionGrowing` |
| Header | `itkConfidenceConnectedImageFilter.h` |
| Params → setters | `multiplier → SetMultiplier(double)`; `NumberOfIteration → SetNumberOfIterations(unsigned int)`; `ReplaceValue → SetReplaceValue(OutputImagePixelType)`; seed(s) → `AddSeed(IndexType)` (modern container-based multi-seed API; legacy single-seed `SetSeed(IndexType)` still exists but deprecated; `ClearSeeds()` also available) |
| Pixel constraints | `InputHasNumericTraitsCheck`/`OutputHasNumericTraitsCheck` (scalar numeric pixels only — multi-component images need the separate `VectorConfidenceConnectedImageFilter`) |
| Arity | 1 input image, 1..N seeds (`AddSeed` supports multiple — matches MATITK's general seedsArray design), 1 output |
| Drift/risk | `SetSeed → AddSeed`/seeds-container rename (single-seed API kept as a deprecated alias, low risk); an `InitialNeighborhoodRadius` parameter exists that old MATITK never exposed (defaults apply) |
| Confidence | High |

### `SCSS` — highest-risk opcode in the whole set
**Not** `SimpleFuzzyConnectednessScalarImageFilter`/fuzzy-connectedness as
initially hypothesized. `itk::SimpleFuzzyConnectednessScalarImageFilter`
and `itk::FuzzyConnectednessImageFilterBase` are **confirmed removed** —
present only in ITK's pre-modular monolithic tree (archived Doxygen for
v3.1/v3.2 era still resolves via web archive), absent from
`Modules/Segmentation` at every checked modern tag from v4.0.0 (the first
modularized release, 2011) through v5.4.0 and current master. Gone for
15+ years, never modularized, no direct successor filter.

`SetChemoAttractantLowThreshold`/`SetChemoAttractantHighThreshold` are real,
exact-name ITK method calls — just not on a fuzzy-connectedness class.
They are **static methods of `itk::bio::CellBase`**
(`itkBioCellBase.h`), used by the ITK Software Guide example
`Examples/Segmentation/CellularSegmentation2.cxx` in the **`ITKBioCell`
remote module**:

```cpp
CellType::SetChemoAttractantLowThreshold(argv[5]);
CellType::SetChemoAttractantHighThreshold(argv[6]);
// then loop calling cellularAggregate->AdvanceTimeStep() numberOfIterations times
```

| Field | Value |
|---|---|
| **Modern class** | `itk::bio::CellularAggregate<Dimension>` (driver) + `itk::bio::CellBase` (static Chemo setters) |
| Module | CMake component **`BioCell`**, registered only as a **Remote Module** (`Modules/Remote/BioCell.remote.cmake`, `EXCLUDE_FROM_DEFAULT`) — **not built in a stock ITK 5.4 install**; requires `Module_BioCell:BOOL=ON` |
| Header | `itkBioCellularAggregate.h` / `itkBioCellBase.h` |
| Params → setters | `SetChemoAttractantLowThreshold → CellBase::SetChemoAttractantLowThreshold(double)` **(static/global, not per-filter)**; `SetChemoAttractantHighThreshold → CellBase::SetChemoAttractantHighThreshold(double)` **(static)**; `numberOfIterations` → loop count driving `CellularAggregate::AdvanceTimeStep()` (not a filter setter at all) |
| Pixel/arity | input image sampled as `float`; 1 seed point places the initial "egg" cell. **Output is a triangulated surface mesh** (`itkVTKPolyDataWriter`, `.vtk` polydata) — **not an image**, unlike every other opcode in this document |
| Drift/risk | **highest in the entire opcode set**: (1) opt-in remote module that may not be present in a target ITK build at all; (2) global static state shared process-wide across all cell instances — reentrancy/thread hazard; (3) output type mismatch (mesh vs. image) breaks the assumption that this opcode yields a mask like every sibling; (4) it is a stateful mitosis/genome-expression biological growth simulation, not a single-call segmentation filter — there is no drop-in equivalent. If a modern replacement is wanted instead of a literal port, `itk::FastMarchingImageFilter`-based region growing or `itk::ConnectedThresholdImageFilter` with dual thresholds are only superficially similar (no chemotaxis/growth dynamics) |
| Confidence | **Medium** — high confidence this is *not* fuzzy-connectedness and *is* BioCell (exact setter-name and parameter-order match against real source); medium confidence on completeness of the port strategy since the real 2006 MATITK wrapper source was not available to confirm its glue code |
| **Recommendation** | Treat SCSS as a product decision (drop the opcode vs. build a from-scratch bespoke port) rather than a routine class-mapping exercise |

### `SCT` — ConnectedThresholdImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::ConnectedThresholdImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKRegionGrowing` |
| Header | `itkConnectedThresholdImageFilter.h` |
| Params → setters | `LowerThreshold → SetLower(InputImagePixelType)` **(confirmed `SetLower`, not `SetLowerThreshold`)**; `UpperThreshold → SetUpper(InputImagePixelType)` **(confirmed `SetUpper`, not `SetUpperThreshold`)** |
| Other API present but not in this opcode's param list | `SetSeed`/`AddSeed`/`ClearSeeds`, `SetReplaceValue` (presumably hardcoded/defaulted by MATITK, unverifiable without its source), `SetConnectivity` (face vs. full, default preserves legacy face-connectivity behavior) |
| Pixel constraints | input/output must be `EqualityComparable`; input convertible to output pixel type |
| Arity | 1 input, 1..N seeds, 1 output |
| Drift/risk | low API drift, but note the setter name is **not** `SetLowerThreshold`/`SetUpperThreshold` despite the wrapper's parameter names — a naming trap for a naive port |
| Confidence | High |

### `SFM` — FastMarchingImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::FastMarchingImageFilter<TLevelSet,TSpeedImage>` — the classic (non-`FastMarchingBase`) implementation, confirmed to **not** inherit `FastMarchingImageFilterBase`/`FastMarchingBase`, so the ITK-2.4-era API is fully intact |
| Module | **`ITKFastMarching`** (lives under Filtering, not Segmentation, despite this opcode's "S" prefix) |
| Header | `itkFastMarchingImageFilter.h` |
| Params → setters | `stoppingTime → SetStoppingValue(double)` |
| Additional requirements beyond this 1 param | a speed image via `SetInput()` (or `SetSpeedConstant(double)` for a constant-speed shortcut), and at least one seed via `SetTrialPoints(NodeContainer*)` (optionally `SetAlivePoints()`) — without these, `Update()` produces nothing. The classic ITK example derives the speed image from an upstream Sigmoid/threshold filter; how MATITK's wrapper actually supplies this from just a 1-param list plus the seeds array is unverified |
| Pixel constraints | typically `float` for both speed and output arrival-time image |
| Arity | 1 image input (speed) + seed/trial points (usually 1, from the seeds array), 1 output (arrival-time/level-set image — a **separate** thresholding step is needed downstream to get a binary mask, which this opcode alone does not produce) |
| Drift/risk | class-identity risk is low; **completeness risk is high** — a 1-parameter wrapper cannot be self-sufficient, and the actual seed/speed-image plumbing MATITK used is unverified |
| Confidence | Medium |

### `SGAC` — GeodesicActiveContourLevelSetImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::GeodesicActiveContourLevelSetImageFilter<TInputImage,TFeatureImage,TOutputPixelType=float>` — unchanged, still on the classic (non-LevelSetsv4) level-set framework |
| Module | `ITKLevelSets` |
| Header | `itkGeodesicActiveContourLevelSetImageFilter.h` |
| Params → setters (all inherited from base `SegmentationLevelSetImageFilter`) | `propagationScaling → SetPropagationScaling(double)`; `CurvatureScaling → SetCurvatureScaling(double)`; `AdvectionScaling → SetAdvectionScaling(double)`; `MaximumRMSError → SetMaximumRMSError(double)`; `MaxIteration → SetNumberOfIterations(unsigned int)` |
| Arity — confirmed | **two required inputs**: `SetInput()` = initial level set (signed-distance image, zero level set = initial contour, typically from FastMarching) and `SetFeatureImage()` = edge-potential/speed image (typically from Sigmoid); 1 output (final level set, needs downstream thresholding for a binary mask) |
| Pixel constraints | `TOutputPixelType` defaults `float`; input/feature images generally real-valued scalar |
| Drift/risk | low API drift; module-choice risk — do not target the differently-templated LevelSetsv4 classes by mistake |
| Confidence | High |

### `SIC` — IsolatedConnectedImageFilter
Resolved: **not** `ConnectedThresholdImageFilter`.

| Field | Value |
|---|---|
| **Modern class** | `itk::IsolatedConnectedImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKRegionGrowing` |
| Header | `itkIsolatedConnectedImageFilter.h` |
| Params → setters | `LowerThreshold → SetLower(InputImagePixelType)`; `ReplaceValue → SetReplaceValue(OutputImagePixelType)` (usually 255) |
| Seeds | **two required groups**: `AddSeed1(IndexType)` and `AddSeed2(IndexType)` (each multi-seed capable; legacy single-seed `SetSeed1`/`SetSeed2` deprecated but present). No `Upper` threshold is supplied by the caller — the filter binary-searches internally for the maximal isolating upper threshold (`GetIsolatedValue()`), with optional `SetIsolatedValueTolerance`/`SetFindUpperThreshold(false)` |
| Verified against | `Examples/Segmentation/IsolatedConnectedImageFilter.cxx` call pattern: `SetLower(lower); AddSeed1(seed1); AddSeed2(seed2); SetReplaceValue(255);` — matches the 2-param wrapper list exactly |
| Pixel constraints | `InputHasNumericTraitsCheck` (scalar numeric input) |
| Arity | 1 input image, 2 seed groups (≥1 point each), 1 output; also check `GetThresholdingFailed()` (the algorithm can fail to isolate) |
| Drift/risk | low; only additions are the multi-seed containers and the `FindUpperThreshold` direction flag |
| Confidence | High |

### `SLLS` — LaplacianSegmentationLevelSetImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::LaplacianSegmentationLevelSetImageFilter<TInputImage,TFeatureImage,TOutputPixelType=float>` |
| Module | `ITKLevelSets` |
| Header | `itkLaplacianSegmentationLevelSetImageFilter.h` |
| Params → setters (base chain `SparseFieldLevelSetImageFilter → FiniteDifferenceImageFilter → SegmentationLevelSetImageFilter`) | `IsoSurfaceValue → SetIsoSurfaceValue(ValueType)` (`ValueType=TOutputPixelType`, default float); `PropagationScaling → SetPropagationScaling(ValueType)`; `CurvatureScaling → SetCurvatureScaling(ValueType)`; `MaximumRMSError → SetMaximumRMSError(double)`; `MaxIteration → SetNumberOfIterations(IdentifierType)` (`uint64_t` on standard 64-bit builds) |
| Arity | 2 inputs — seed image (`SetInput`/`SetInitialImage`) + feature image (`SetFeatureImage`/`SetInput2`); 1 scalar float/double level-set output |
| Disambiguation | "SLLS" = Segmentation+Laplacian+LevelSet (speed term driven by Laplacian zero-crossing), distinguished from SSDLS = Segmentation+ShapeDetection+LevelSet (edge-potential-map speed term) and SGAC = GeodesicActiveContour — three siblings on the same base class |
| Drift/risk | none — API essentially unchanged since 2.4 |
| Confidence | High |

### `SNC` — NeighborhoodConnectedImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::NeighborhoodConnectedImageFilter<TInputImage,TOutputImage>` |
| Module | `ITKRegionGrowing` |
| Header | `itkNeighborhoodConnectedImageFilter.h` |
| Params → setters | `RadiusX/Y/Z` assembled into one `itk::Size<3>`, `SetRadius(InputImageSizeType)`; `LowerThreshold → SetLower(InputImagePixelType)`; `UpperThreshold → SetUpper(InputImagePixelType)`; `ReplaceValue → SetReplaceValue(OutputImagePixelType)` |
| Arity | 1 input image, seed indices via separate `SetSeed`/`AddSeed` calls (not in the numeric param list — supplied via the seeds array), 1 output label image |
| Drift/risk | none |
| Confidence | High |

### `SOT` — OtsuThresholdImageFilter (single threshold, unchanged name)
| Field | Value |
|---|---|
| **Modern class** | `itk::OtsuThresholdImageFilter<TInputImage,TOutputImage,TMaskImage=TOutputImage>` — confirmed **still present and not pluralized**, distinct from FOMT's `OtsuMultipleThresholdsImageFilter` |
| Module | `ITKThresholding` — module moved from a `Segmentation/Thresholding` grouping (404s) to `Filtering/Thresholding` in the post-4.x modularization |
| Header | `itkOtsuThresholdImageFilter.h` |
| Params → setters | `numberOfHistogram → SetNumberOfHistogramBins(unsigned int)` — unchanged setter name, but now inherited from base `itk::HistogramThresholdImageFilter`; the concrete Otsu class delegates the actual computation to an internal `OtsuThresholdCalculator` (an Insight Journal refactor), though the call-site setter is identical to 2.4. Base-class default `NumberOfHistogramBins` is 256 — a port must still explicitly pass MATITK's 128 default |
| Arity | 1 input, 1 binary/label output |
| Drift/risk | medium (internal implementation refactored; public setter name/signature unchanged) |
| Confidence | High |

### `SSDLS` — ShapeDetectionLevelSetImageFilter
| Field | Value |
|---|---|
| **Modern class** | `itk::ShapeDetectionLevelSetImageFilter<TInputImage,TFeatureImage,TOutputPixelType=float>` |
| Module | `ITKLevelSets` |
| Header | `itkShapeDetectionLevelSetImageFilter.h` |
| Params → setters (same base chain as SLLS) | `propagationScaling → SetPropagationScaling(ValueType)`; `curvatureScaling → SetCurvatureScaling(ValueType)`; `SetMaximumRMSError → SetMaximumRMSError(double)`; `SetNumberOfIterations → SetNumberOfIterations(IdentifierType)` |
| Arity | 2 inputs (initial level set + edge-potential-map feature image, typically from Sigmoid-over-gradient), 1 output |
| Drift/risk | none |
| Confidence | High |

### `SWS` — WatershedImageFilter
See the dedicated load-bearing section above. Summary: class unchanged,
module `ITKWatersheds`. `SETLEVEL → SetLevel(double)`,
`SETTHRESHOLD → SetThreshold(double)`, both remain fractional 0.0–1.0.
Input **must** be a pre-computed gradient-magnitude (or similar edge-map)
image, not raw intensity. Output is a label image,
`Image<IdentifierType,Dim>` where `IdentifierType` is `uint64_t` on standard
modern builds. Confidence: **High**.

---

## Registration (2)

### `RD` — Demons deformable registration (two chained classes)
| Field | Value |
|---|---|
| **Modern classes** | `itk::HistogramMatchingImageFilter<TInputImage,TOutputImage,THistogramMeasurement>` (preprocessing) feeding `itk::DemonsRegistrationFilter<TFixedImage,TMovingImage,TDisplacementField>` (registration) — **confirmed neither is deprecated/renamed**; `SymmetricForcesDemonsRegistrationFilter`/`FastSymmetricForcesDemonsRegistrationFilter` exist alongside as separate sibling classes with different force terms, not replacements |
| Module | `ITKImageIntensity` (HistogramMatching) + `ITKPDEDeformableRegistration` (Demons) |
| Header | `itkHistogramMatchingImageFilter.h`, `itkDemonsRegistrationFilter.h` |
| Params → setters | `NumberOfHistogramLevels → HistogramMatchingImageFilter::SetNumberOfHistogramLevels(SizeValueType)`; `NumberOfMatchPoints → SetNumberOfMatchPoints(SizeValueType)`; `DemonNumberofIterations → DemonsRegistrationFilter::SetNumberOfIterations(IdentifierType)` (inherited via `FiniteDifferenceImageFilter`); `DemonStandardDeviations → SetStandardDeviations(double)` (scalar overload on immediate base `itk::PDEDeformableRegistrationFilter`) |
| **Drift/trap — verified from source, not documentation** | `SetStandardDeviations` is **inert unless smoothing is explicitly enabled**: `PDEDeformableRegistrationFilter::m_SmoothDisplacementField` default-initializes to `false`, and `DemonsRegistrationFilter`'s constructor does not touch this flag. A faithful port **must also call `SmoothDisplacementFieldOn()`**, or `DemonStandardDeviations` is silently ignored — a genuine silent-failure trap that a literal "set these 4 params and go" port would miss |
| Arity | **two** input images (fixed via `SetFixedImage`, moving via `SetMovingImage` on Demons; the moving image typically passes through `HistogramMatchingImageFilter` first). Output of `DemonsRegistrationFilter::GetOutput()`/`GetDisplacementField()` is a **deformation field**, not a resampled image — producing a warped moving image requires an additional `itk::WarpImageFilter`/`ResampleImageFilter` pass (matching the classic two-stage ITK example) |
| Confidence | High on classes/headers/modules/setters; the `SmoothDisplacementField` gotcha is the standout finding |

### `RTPS` — ThinPlateSplineKernelTransform
| Field | Value |
|---|---|
| **Modern class** | `itk::ThinPlateSplineKernelTransform<TParametersValueType, VDimension=3>`, extends `itk::KernelTransform` |
| Module | `ITKTransform` |
| Header | `itkThinPlateSplineKernelTransform.h` |
| Landmark setters (on base `KernelTransform`) | `SetSourceLandmarks(PointSetType*)`, `SetTargetLandmarks(PointSetType*)`; `PointSetType = itk::PointSet<TParametersValueType,VDimension>` |
| Params → setters | none (matches the zero-param wrapper entry) |
| Arity | 0 conventional input images; 2 paired landmark point sets carrying the correspondences (matches the empty param list — everything comes from the seeds array). Output is the fitted `Transform` object itself, not an image; warping an actual image needs a follow-on resample step |
| Drift/risk | low — unchanged since 2.4 |
| Confidence | High |

---

## ITK modules needed (for `find_package(ITK COMPONENTS ...)`)

```
ITKCommon                        (implicit, always required)
ITKFiniteDifference               FAAB, FCA, FCF, FGAD base
ITKAntiAlias                      FAAB
ITKSmoothing                      FBB, FDG, FGA, FMEAN, FMEDIAN, FGMS (stage 1)
ITKBinaryMathematicalMorphology   FBD, FBE
ITKMathematicalMorphology         FBD, FBE (structuring element)
ITKImageFeature                   FBL, FD, FLS, FVMI
ITKThresholding                   FBT, FOMT, SOT
ITKAnisotropicSmoothing           FCA, FGAD
ITKCurvatureFlow                  FCF, FMMCF
ITKDistanceMap                    FDM, FDMV
ITKImageGrid                      FF
ITKFFT                            FFFT
ITKImageGradient                  FGM, FGMRG, FGMS (stage 2)
ITKImageIntensity                 FSN, RD (HistogramMatching)
ITKLabelVoting                    FVBIH
ITKFastMarching                   SFM
ITKRegionGrowing                  SCC, SCT, SIC, SNC
ITKLevelSets                      SGAC, SLLS, SSDLS
ITKWatersheds                     SWS
ITKPDEDeformableRegistration      RD (Demons)
ITKTransform                      RTPS
ITKBioCell                        SCSS  — remote module, EXCLUDE_FROM_DEFAULT,
                                   requires Module_BioCell:BOOL=ON; only needed
                                   if SCSS is ported rather than dropped
```

---

## Confidence tally

**High: 33.** FAAB, FBB, FBD, FBE, FBL, FBT, FCA, FCF, FD, FDG, FDM, FF, FGAD,
FGM, FGMRG, FLS, FMEAN, FMEDIAN, FOMT, FSN, FVBIH, FVMI, SCC, SCT, SGAC, SIC,
SLLS, SNC, SOT, SSDLS, SWS, RD, RTPS.

**Medium: 6.** FDMV, FFFT, FGA, FMMCF, SCSS, SFM.

**Low: 1.** FGMS.

---

## Sources consulted

- `matitk_opcode_params.txt` — real MATITK binary self-documentation (ground truth for parameter names/order).
- `matitk-paper-ij2005.pdf` — original MATITK paper (Chu & Hamarneh), confirms FCA, SCC, FGM, FOMT identities and their exact worked-example call signatures.
- Vincent Chu's own MATITK opcode-documentation page (external, independent of the ITK source) — cross-checked several ambiguous identities (FBB, FGMS pipeline hypothesis, FSN, FVBIH).
- `github.com/InsightSoftwareConsortium/ITK` (`master`/`v5.4.0`) — primary source of truth for every modern class, header, module, and setter signature in this document; fetched directly, header by header, and via directory listings to resolve module placement.
- `docs.itk.org` Doxygen — rate-limited (HTTP 429) during this research pass; not used as a direct source, though its URL structure (`docs.itk.org/projects/doxygen/en/stable/classitk_1_1ClassName.html`) is noted here for future reference since `itk.org/Doxygen/html/` now redirects there.
- ITK Examples tree (`Examples/Segmentation/*.cxx`, `Examples/Filtering/*.cxx`) — used to disambiguate SIC vs. SCT and confirm exact call-site parameter order for several segmentation opcodes.
